/**
 * Instrument registry — every selectable sound source in one table.
 *
 * Each entry knows how to build its smplr instrument lazily (samples are
 * fetched only when the user selects it — nothing is preloaded), plus the
 * Vietnamese label and the attribution/license line shown in the picker
 * (project rule: the app must record where each sound comes from).
 *
 * Sources (verified licences — see docs/decisions.md "Nhạc cụ" section):
 * - Salamander V3: self-hosted in `public/samples/`, Alexander Holm,
 *   declared CC-BY 3.0 by the redistribution repo (credit kept).
 * - Splendid Grand (Steinway D): sfzinstruments, Public Domain.
 * - Greg Sullivan E-Pianos (CP80 / PianetT / Wurlitzer EP200):
 *   sfzinstruments, CC-BY 3.0.
 * - VCSL (TX81Z FM Piano, vibraphone / xylophone / tubular bells /
 *   balafon): Versilian Studios Community Sample Library, CC0.
 * - GM 128: FluidR3_GM via gleitz/midi-js-soundfonts, CC-BY 3.0.
 *
 * All remote sets are served from GitHub Pages hosts that smplr's own
 * bundles point at (`smpldsnds.github.io`, `gleitz.github.io`) — the
 * runtime swaps them through the app's sample-storage policy
 * (sampleCache.ts), so caching rules apply to every instrument alike.
 */
import {
  ElectricPiano,
  Mallet,
  Smplr,
  Soundfont,
  SplendidGrandPiano,
  type NoteEvent,
  type Scheduler,
  type StopFn,
  type Storage,
  type LoadProgress,
} from 'smplr'
import {
  applyVelocityCompensation,
  buildSalamanderDescriptor,
} from './salamanderDescriptor'

// ── IDs ─────────────────────────────────────────────────────────────

export const DEFAULT_INSTRUMENT_ID = 'salamander'

/** Where the self-hosted Salamander set lives (env-overridable). */
export const SALAMANDER_BASE_URL =
  (import.meta.env.VITE_SAMPLES_BASE_URL as string | undefined)?.replace(
    /\/$/,
    '',
  ) ?? '/samples/salamander-v3-close'

// ── Handle (what sampler.ts drives) ─────────────────────────────────

export type InstrumentHandle = {
  /** Resolves when the instrument's samples are loaded. */
  ready: Promise<unknown>
  start(event: NoteEvent): StopFn
  stop(target?: unknown): void
  disconnect(): void
  /**
   * Per-layer volume compensation (salamander only — the descriptor is
   * mutable and smplr re-reads group volumes on every start). Other
   * instruments expose no equivalent; the setter becomes a no-op.
   */
  applyVelocityCompensation?: (compensation: number) => void
}

export type InstrumentCreateArgs = {
  context: BaseAudioContext
  destination: AudioNode
  storage: Storage
  scheduler?: Scheduler
  onLoadProgress?: (p: LoadProgress) => void
}

export type InstrumentFamily =
  | 'piano'
  | 'electric'
  | 'mallet'
  | 'gmPiano'
  | 'gmChromatic'
  | 'gmOrgan'
  | 'gmGuitar'
  | 'gmBass'
  | 'gmStrings'
  | 'gmEnsemble'
  | 'gmBrass'
  | 'gmReed'
  | 'gmPipe'
  | 'gmSynthLead'
  | 'gmSynthPad'
  | 'gmSynthFx'
  | 'gmEthnic'
  | 'gmPercussive'
  | 'gmSfx'

export type InstrumentDef = {
  id: string
  /** Vietnamese display name. */
  label: string
  family: InstrumentFamily
  /** Attribution + licence shown under the picker. */
  credit: string
  create(args: InstrumentCreateArgs): InstrumentHandle
}

// ── Family labels (picker optgroups) ────────────────────────────────

export const FAMILY_LABELS: Record<InstrumentFamily, string> = {
  piano: 'Piano',
  electric: 'Đàn điện',
  mallet: 'Nhạc cụ gõ',
  gmPiano: 'GM · Piano',
  gmChromatic: 'GM · Nhạc cụ gõ âm',
  gmOrgan: 'GM · Organ',
  gmGuitar: 'GM · Guitar',
  gmBass: 'GM · Bass',
  gmStrings: 'GM · Dây',
  gmEnsemble: 'GM · Hợp tấu',
  gmBrass: 'GM · Kèn đồng',
  gmReed: 'GM · Kèn gỗ',
  gmPipe: 'GM · Sáo',
  gmSynthLead: 'GM · Lead tổng hợp',
  gmSynthPad: 'GM · Pad tổng hợp',
  gmSynthFx: 'GM · Hiệu ứng',
  gmEthnic: 'GM · Dân tộc',
  gmPercussive: 'GM · Gõ',
  gmSfx: 'GM · Âm thanh',
}

const FAMILY_ORDER: InstrumentFamily[] = [
  'piano',
  'electric',
  'mallet',
  'gmPiano',
  'gmChromatic',
  'gmOrgan',
  'gmGuitar',
  'gmBass',
  'gmStrings',
  'gmEnsemble',
  'gmBrass',
  'gmReed',
  'gmPipe',
  'gmSynthLead',
  'gmSynthPad',
  'gmSynthFx',
  'gmEthnic',
  'gmPercussive',
  'gmSfx',
]

// ── smplr class adapters ────────────────────────────────────────────

// smplr's class signatures are typed against AudioContext, but they only
// use BaseAudioContext APIs (same as Smplr) — the cast lets the offline
// exporter reuse the same instrument entries as the realtime engine.
type AudioContextish = AudioContext

function readyOf(inst: {
  load?: Promise<unknown>
  loaded?: () => Promise<unknown>
}): Promise<unknown> {
  if (inst.load) return inst.load
  if (inst.loaded) return inst.loaded()
  return Promise.resolve()
}

// ── Curated entries ─────────────────────────────────────────────────

const CREDIT_SALAMANDER =
  'Salamander V3 — Alexander Holm (CC-BY 3.0) · tự host trong app'
const CREDIT_SPLENDID =
  'Splendid Grand Piano (Steinway D) — sfzinstruments (Public Domain)'
const CREDIT_GREG =
  'Greg Sullivan E-Pianos — sfzinstruments (CC-BY 3.0)'
const CREDIT_VCSL = 'VCSL — Versilian Studios (CC0)'
const CREDIT_FLUID =
  'FluidR3_GM — Frank Wen, qua midi-js-soundfonts (CC-BY 3.0)'

function salamanderEntry(): InstrumentDef {
  return {
    id: DEFAULT_INSTRUMENT_ID,
    label: 'Grand Piano (Salamander)',
    family: 'piano',
    credit: CREDIT_SALAMANDER,
    create({ context, destination, storage, scheduler, onLoadProgress }) {
      const descriptor = buildSalamanderDescriptor(SALAMANDER_BASE_URL)
      const piano = new Smplr(context, descriptor, {
        destination,
        storage,
        velocity: 100,
        scheduler,
        onLoadProgress,
      })
      return {
        ready: readyOf(piano),
        start: (e) => piano.start(e),
        stop: (t) => piano.stop(t as never),
        disconnect: () => piano.disconnect(),
        applyVelocityCompensation: (c) => applyVelocityCompensation(descriptor, c),
      }
    },
  }
}

function splendidEntry(): InstrumentDef {
  return {
    id: 'splendid',
    label: 'Grand Piano (Splendid Steinway)',
    family: 'piano',
    credit: CREDIT_SPLENDID,
    create({ context, destination, storage, onLoadProgress }) {
      const piano = new SplendidGrandPiano(context as AudioContextish, {
        baseUrl:
          'https://smpldsnds.github.io/sfzinstruments-splendid-grand-piano/samples',
        destination,
        storage,
        onLoadProgress,
      })
      return {
        ready: readyOf(piano),
        start: (e) => piano.start(e),
        stop: (t) => piano.stop(t as never),
        disconnect: () => piano.disconnect(),
      }
    },
  }
}

function electricEntry(
  id: string,
  label: string,
  instrument: string,
  credit: string,
): InstrumentDef {
  return {
    id,
    label,
    family: 'electric',
    credit,
    create({ context, destination, storage, onLoadProgress }) {
      const piano = new ElectricPiano(context as AudioContextish, {
        instrument,
        destination,
        storage,
        onLoadProgress,
      })
      return {
        ready: readyOf(piano),
        start: (e) => piano.start(e),
        stop: (t) => piano.stop(t as never),
        disconnect: () => piano.disconnect(),
      }
    },
  }
}

function malletEntry(
  id: string,
  label: string,
  instrument: string,
): InstrumentDef {
  return {
    id,
    label,
    family: 'mallet',
    credit: CREDIT_VCSL,
    create({ context, destination, storage, onLoadProgress }) {
      const mallet = new Mallet(context as AudioContextish, {
        instrument,
        destination,
        storage,
        onLoadProgress,
      })
      return {
        ready: readyOf(mallet),
        start: (e) => mallet.start(e),
        stop: (t) => mallet.stop(t as never),
        disconnect: () => mallet.disconnect(),
      }
    },
  }
}

const CURATED: InstrumentDef[] = [
  salamanderEntry(),
  splendidEntry(),
  electricEntry('cp80', 'Piano điện Yamaha CP80', 'CP80', CREDIT_GREG),
  electricEntry('wurli', 'Wurlitzer EP200', 'WurlitzerEP200', CREDIT_GREG),
  electricEntry('pianet', 'Hohner Pianet T', 'PianetT', CREDIT_GREG),
  electricEntry('tx81z', 'FM Piano (Yamaha TX81Z)', 'TX81Z', CREDIT_VCSL),
  malletEntry('vibraphone', 'Vibraphone', 'Vibraphone - Soft Mallets'),
  malletEntry('xylophone', 'Xylophone', 'Xylophone - Medium Mallets'),
  malletEntry('tubular', 'Tubular Bells', 'Tubular Bells 1'),
  malletEntry('balafon', 'Balafon', 'Balafon - Traditional Mallet'),
]

// ── GM 128 (FluidR3_GM) ─────────────────────────────────────────────

/**
 * The General MIDI Level 1 instrument list in programme order — the
 * standard names that FluidR3_GM's file set uses (snake_case). Family
 * assignment follows the GM spec's 8-instrument blocks.
 */
const GM_NAMES: string[] = [
  'acoustic_grand_piano',
  'bright_acoustic_piano',
  'electric_grand_piano',
  'honkytonk_piano',
  'electric_piano_1',
  'electric_piano_2',
  'harpsichord',
  'clavinet',
  'celesta',
  'glockenspiel',
  'music_box',
  'vibraphone',
  'marimba',
  'xylophone',
  'tubular_bells',
  'dulcimer',
  'drawbar_organ',
  'percussive_organ',
  'rock_organ',
  'church_organ',
  'reed_organ',
  'accordion',
  'harmonica',
  'tango_accordion',
  'acoustic_guitar_nylon',
  'acoustic_guitar_steel',
  'electric_guitar_jazz',
  'electric_guitar_clean',
  'electric_guitar_muted',
  'overdriven_guitar',
  'distortion_guitar',
  'guitar_harmonics',
  'acoustic_bass',
  'electric_bass_finger',
  'electric_bass_pick',
  'fretless_bass',
  'slap_bass_1',
  'slap_bass_2',
  'synth_bass_1',
  'synth_bass_2',
  'violin',
  'viola',
  'cello',
  'contrabass',
  'tremolo_strings',
  'pizzicato_strings',
  'orchestral_harp',
  'timpani',
  'string_ensemble_1',
  'string_ensemble_2',
  'synth_strings_1',
  'synth_strings_2',
  'choir_aahs',
  'voice_oohs',
  'synth_choir',
  'orchestra_hit',
  'trumpet',
  'trombone',
  'tuba',
  'muted_trumpet',
  'french_horn',
  'brass_section',
  'synth_brass_1',
  'synth_brass_2',
  'soprano_sax',
  'alto_sax',
  'tenor_sax',
  'baritone_sax',
  'oboe',
  'english_horn',
  'bassoon',
  'clarinet',
  'piccolo',
  'flute',
  'recorder',
  'pan_flute',
  'blown_bottle',
  'shakuhachi',
  'whistle',
  'ocarina',
  'lead_1_square',
  'lead_2_sawtooth',
  'lead_3_calliope',
  'lead_4_chiff',
  'lead_5_charang',
  'lead_6_voice',
  'lead_7_fifths',
  'lead_8_bass__lead',
  'pad_1_new_age',
  'pad_2_warm',
  'pad_3_polysynth',
  'pad_4_choir',
  'pad_5_bowed',
  'pad_6_metallic',
  'pad_7_halo',
  'pad_8_sweep',
  'fx_1_rain',
  'fx_2_soundtrack',
  'fx_3_crystal',
  'fx_4_atmosphere',
  'fx_5_brightness',
  'fx_6_goblins',
  'fx_7_echoes',
  'fx_8_scifi',
  'sitar',
  'banjo',
  'shamisen',
  'koto',
  'kalimba',
  'bagpipe',
  'fiddle',
  'shanai',
  'tinkle_bell',
  'agogo',
  'steel_drums',
  'woodblock',
  'taiko_drum',
  'melodic_tom',
  'synth_drum',
  'reverse_cymbal',
  'guitar_fret_noise',
  'breath_noise',
  'seashore',
  'bird_tweet',
  'telephone_ring',
  'helicopter',
  'applause',
  'gunshot',
]

/** Vietnamese display names, same order as `GM_NAMES` (GM programme order). */
const GM_LABELS_VI: string[] = [
  'Đại dương cầm',
  'Đại dương cầm sáng',
  'Piano điện grand',
  'Piano honky-tonk',
  'Piano điện 1',
  'Piano điện 2',
  'Harpsichord',
  'Clavinet',
  'Celesta',
  'Glockenspiel',
  'Hộp nhạc',
  'Vibraphone',
  'Marimba',
  'Xylophone',
  'Chuông ống',
  'Dulcimer',
  'Organ drawbar',
  'Organ gõ',
  'Organ rock',
  'Organ nhà thờ',
  'Organ reed',
  'Accordion',
  'Kèn harmonica',
  'Accordion tango',
  'Guitar thùng (nylon)',
  'Guitar thùng (thép)',
  'Guitar điện jazz',
  'Guitar điện clean',
  'Guitar điện mute',
  'Guitar overdrive',
  'Guitar distortion',
  'Guitar harmonics',
  'Bass thùng',
  'Bass điện (ngón)',
  'Bass điện (pick)',
  'Bass fretless',
  'Slap bass 1',
  'Slap bass 2',
  'Bass tổng hợp 1',
  'Bass tổng hợp 2',
  'Violin',
  'Viola',
  'Cello',
  'Contrebass',
  'Dây rung (tremolo)',
  'Dây búng (pizzicato)',
  'Đàn hạc',
  'Trống định âm',
  'Dàn dây 1',
  'Dàn dây 2',
  'Dây tổng hợp 1',
  'Dây tổng hợp 2',
  'Hợp xướng Aah',
  'Giọng Ooh',
  'Hợp xướng tổng hợp',
  'Orchestra hit',
  'Kèn trumpet',
  'Kèn trombone',
  'Kèn tuba',
  'Trumpet mute',
  'Kèn cor',
  'Dàn kèn đồng',
  'Kèn đồng tổng hợp 1',
  'Kèn đồng tổng hợp 2',
  'Sax soprano',
  'Sax alto',
  'Sax tenor',
  'Sax baritone',
  'Kèn oboe',
  'Kèn cor anglais',
  'Kèn bassoon',
  'Kèn clarinet',
  'Sáo piccolo',
  'Sáo flute',
  'Sáo recorder',
  'Sáo pan',
  'Thổi chai',
  'Shakuhachi',
  'Còi',
  'Ocarina',
  'Lead vuông',
  'Lead răng cưa',
  'Lead calliope',
  'Lead chiff',
  'Lead charang',
  'Lead giọng',
  'Lead quãng năm',
  'Lead bass',
  'Pad new age',
  'Pad ấm',
  'Pad polysynth',
  'Pad hợp xướng',
  'Pad kéo dây',
  'Pad kim loại',
  'Pad hào quang',
  'Pad quét',
  'Tiếng mưa',
  'Nhạc phim',
  'Pha lê',
  'Bầu không khí',
  'Độ sáng',
  'Yêu tinh',
  'Tiếng vọng',
  'Viễn tưởng',
  'Sitar',
  'Banjo',
  'Shamisen',
  'Koto',
  'Kalimba',
  'Kèn túi',
  'Đàn fiddle',
  'Shenai',
  'Chuông lanh canh',
  'Agogo',
  'Trống thép',
  'Mõ gỗ',
  'Trống taiko',
  'Trống tom',
  'Trống tổng hợp',
  'Chũm chọe ngược',
  'Tiếng phím guitar',
  'Tiếng thở',
  'Tiếng biển',
  'Tiếng chim',
  'Chuông điện thoại',
  'Trực thăng',
  'Tiếng vỗ tay',
  'Tiếng súng',
]

function gmFamily(index: number): InstrumentFamily {
  if (index < 8) return 'gmPiano'
  if (index < 16) return 'gmChromatic'
  if (index < 24) return 'gmOrgan'
  if (index < 32) return 'gmGuitar'
  if (index < 40) return 'gmBass'
  if (index < 48) return 'gmStrings'
  if (index < 56) return 'gmEnsemble'
  if (index < 64) return 'gmBrass'
  if (index < 72) return 'gmReed'
  if (index < 80) return 'gmPipe'
  if (index < 88) return 'gmSynthLead'
  if (index < 96) return 'gmSynthPad'
  if (index < 104) return 'gmSynthFx'
  if (index < 112) return 'gmEthnic'
  if (index < 120) return 'gmPercussive'
  return 'gmSfx'
}

function gmEntries(): InstrumentDef[] {
  return GM_NAMES.map((name, index) => ({
    id: `gm:${name}`,
    label: `${GM_LABELS_VI[index]} (GM ${index + 1})`,
    family: gmFamily(index),
    credit: CREDIT_FLUID,
    create({ context, destination, storage, onLoadProgress }): InstrumentHandle {
      const sf = new Soundfont(context as AudioContextish, {
        kit: 'FluidR3_GM',
        instrument: name,
        destination,
        storage,
        onLoadProgress,
      })
      return {
        ready: readyOf(sf),
        start: (e) => sf.start(e),
        stop: (t) => sf.stop(t as never),
        disconnect: () => sf.disconnect(),
      }
    },
  }))
}

// ── Registry API ────────────────────────────────────────────────────

const REGISTRY: Map<string, InstrumentDef> = new Map()
for (const def of [...CURATED, ...gmEntries()]) {
  if (REGISTRY.has(def.id)) {
    throw new Error(`Duplicate instrument id: ${def.id}`)
  }
  REGISTRY.set(def.id, def)
}

export function getInstrument(id: string): InstrumentDef {
  return REGISTRY.get(id) ?? REGISTRY.get(DEFAULT_INSTRUMENT_ID)!
}

export function hasInstrument(id: string): boolean {
  return REGISTRY.has(id)
}

export function isGmInstrument(id: string): boolean {
  return id.startsWith('gm:')
}

/** All instruments, grouped for the picker (families in display order). */
export function instrumentsByFamily(): Array<{
  family: InstrumentFamily
  label: string
  items: InstrumentDef[]
}> {
  return FAMILY_ORDER.map((family) => ({
    family,
    label: FAMILY_LABELS[family],
    items: [...REGISTRY.values()].filter((d) => d.family === family),
  })).filter((g) => g.items.length > 0)
}
