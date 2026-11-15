import { useEffect } from "react";
import * as Tone from "tone";
import { audioEngine } from "../audio/engine";
import { markLivePlay } from "../usage";
import { useStore } from "../store";

// PC keyboard → MIDI mapping. ZXCV/ASDF rows = lower octave (white/sharps),
// QWERTY/digit rows = upper octave. Some pitches reachable from multiple
// keys (e.g. q/, both = C4); distinct keys trigger separate voices.
//
// This is the base map at `pcKeymapBase` = 48 (C3) and `pcOctaveShift` = 0 —
// both live in Settings, so the whole map can be moved to another register
// without editing code (research-piano/20.4 documents this exact map; the
// remap-every-key UI is still open, see docs/ideas.md).
const PC_KEY_NOTES: Record<string, number> = {
  KeyZ: 48, KeyX: 50, KeyC: 52, KeyV: 53, KeyB: 55, KeyN: 57, KeyM: 59,
  Comma: 60, Period: 62, Slash: 64,
  KeyS: 49, KeyD: 51, KeyG: 54, KeyH: 56, KeyJ: 58, KeyL: 61, Semicolon: 63,
  KeyQ: 60, KeyW: 62, KeyE: 64, KeyR: 65, KeyT: 67, KeyY: 69, KeyU: 71,
  KeyI: 72, KeyO: 74, KeyP: 76, BracketLeft: 77, BracketRight: 79,
  Digit2: 61, Digit3: 63, Digit5: 66, Digit6: 68, Digit7: 70, Digit9: 73,
  Digit0: 75, Equal: 78,
};

// Glyph shown on the on-screen keys for each map entry. The map itself
// is physical `e.code`, so playing works on ANY layout; only the printed
// label differs. Presets cover the common non-QWERTY labelings
// (research 09 — "preset QWERTY/AZERTY/Dvorak"; per-key remap UI still
// open, docs/ideas.md).
export type PcGlyphPreset = "qwerty" | "azerty" | "dvorak";

const QWERTY_GLYPHS: Record<string, string> = {
  KeyZ: "Z", KeyX: "X", KeyC: "C", KeyV: "V", KeyB: "B", KeyN: "N",
  KeyM: "M", Comma: ",", Period: ".", Slash: "/",
  KeyS: "S", KeyD: "D", KeyG: "G", KeyH: "H", KeyJ: "J", KeyL: "L",
  Semicolon: ";",
  KeyQ: "Q", KeyW: "W", KeyE: "E", KeyR: "R", KeyT: "T", KeyY: "Y",
  KeyU: "U", KeyI: "I", KeyO: "O", KeyP: "P",
  BracketLeft: "[", BracketRight: "]",
  Digit2: "2", Digit3: "3", Digit5: "5", Digit6: "6", Digit7: "7",
  Digit9: "9", Digit0: "0", Equal: "=",
};

// French AZERTY: physical key positions carry different printed letters
// (KeyA prints Q, KeyQ prints A, KeyW prints Z, KeyZ prints W, …).
const AZERTY_GLYPHS: Record<string, string> = {
  KeyZ: "W", KeyX: "X", KeyC: "C", KeyV: "V", KeyB: "B", KeyN: "N",
  KeyM: ",", Comma: ";", Period: ":", Slash: "!",
  KeyA: "Q", KeyS: "S", KeyD: "D", KeyF: "F", KeyG: "G", KeyH: "H",
  KeyJ: "J", KeyK: "K", KeyL: "L", Semicolon: "M",
  KeyQ: "A", KeyW: "Z", KeyE: "E", KeyR: "R", KeyT: "T", KeyY: "Y",
  KeyU: "U", KeyI: "I", KeyO: "O", KeyP: "P",
  BracketLeft: "^", BracketRight: "$",
  Digit2: "é", Digit3: "\"", Digit5: "(", Digit6: "-", Digit7: "è",
  Digit9: "ç", Digit0: "à", Equal: "=",
};

// US Dvorak letter labeling on QWERTY positions (digit row unchanged).
const DVORAK_GLYPHS: Record<string, string> = {
  KeyZ: ";", KeyX: "Q", KeyC: "J", KeyV: "K", KeyB: "X", KeyN: "B",
  KeyM: "M", Comma: "W", Period: "V", Slash: "Z",
  KeyA: "A", KeyS: "O", KeyD: "E", KeyF: "U", KeyG: "I", KeyH: "D",
  KeyJ: "H", KeyK: "T", KeyL: "N", Semicolon: "S",
  KeyQ: ",", KeyW: ".", KeyE: "P", KeyR: "F", KeyT: "G", KeyY: "Y",
  KeyU: "C", KeyI: "R", KeyO: "L", KeyP: "/",
  BracketLeft: "=", BracketRight: "]",
  Digit2: "2", Digit3: "3", Digit5: "5", Digit6: "6", Digit7: "7",
  Digit9: "9", Digit0: "0", Equal: "=",
};

const GLYPH_PRESETS: Record<PcGlyphPreset, Record<string, string>> = {
  qwerty: QWERTY_GLYPHS,
  azerty: AZERTY_GLYPHS,
  dvorak: DVORAK_GLYPHS,
};

export function pcKeyGlyphs(preset: PcGlyphPreset): Record<string, string> {
  return GLYPH_PRESETS[preset] ?? QWERTY_GLYPHS;
}

// Shift+<key> chords owned by global shortcuts (Shift+R record toggle,
// Shift+K set keyframe). They must not also fire a piano note. Any OTHER
// Shift+note press plays the note — Shift doubles as the sustain pedal,
// so "pedal + note" has to work (research-piano/20.4).
const RESERVED_SHIFT_COMBOS = new Set(["KeyR", "KeyK"]);

export const PC_OCTAVE_MIN = -4;
export const PC_OCTAVE_MAX = 4;

/**
 * Resolve a physical key code to the MIDI note it currently plays,
 * honoring `pcKeymapBase` and `pcOctaveShift`. Returns null when the
 * shifted note falls outside MIDI range or the key is unmapped.
 */
export function pcKeyToMidi(code: string): number | null {
  const baseMidi = PC_KEY_NOTES[code];
  if (baseMidi === undefined) return null;
  const s = useStore.getState().settings;
  const midi = baseMidi - 48 + s.pcKeymapBase + s.pcOctaveShift * 12;
  return midi >= 0 && midi <= 127 ? midi : null;
}

/**
 * The computer-key glyph(s) that currently play `midi`, for the on-key
 * labels. Empty string when no map key reaches the note at the current
 * base/shift. Multiple keys can share a note (e.g. "," and "Q" = C4).
 */
export function pcGlyphForMidi(midi: number): string {
  const out: string[] = [];
  const s = useStore.getState().settings;
  const glyphs = pcKeyGlyphs(s.pcGlyphPreset);
  for (const code of Object.keys(PC_KEY_NOTES)) {
    if (pcKeyToMidi(code) === midi) out.push(glyphs[code] ?? code);
    if (out.length >= 2) break;
  }
  return out.join(" ");
}

const isEditable = (el: EventTarget | null): boolean => {
  if (!(el instanceof HTMLElement)) return false;
  const tag = el.tagName;
  return (
    tag === "INPUT" ||
    tag === "TEXTAREA" ||
    tag === "SELECT" ||
    el.isContentEditable
  );
};

/** True when `code` is the configured sustain-pedal key ('none' = off). */
function isSustainCode(code: string, setting: string): boolean {
  if (setting === "none") return false;
  // 'ShiftLeft' is stored for "either Shift" — both edges act as the pedal.
  if (setting === "ShiftLeft") return code === "ShiftLeft" || code === "ShiftRight";
  return code === setting;
}

/**
 * PC keyboard input — same lifecycle as touch. Skipped on editable focus
 * and on meta/ctrl/alt chords (they belong to global shortcuts). Shift is
 * allowed through except for the reserved Shift+chords above — Shift is
 * also the default sustain-pedal key. Window blur releases everything.
 * `transpose` deliberately does NOT apply here (the user plays the keys
 * they see); `pcKeymapBase` + `pcOctaveShift` place the rows instead.
 */
export function usePcKeyboardInput(ensureAudio: () => Promise<boolean>) {
  useEffect(() => {
    const pressed = new Map<string, () => void>();
    const pending = new Set<string>();

    const onDown = async (e: KeyboardEvent) => {
      if (e.repeat || e.metaKey || e.ctrlKey || e.altKey) return;
      if (isEditable(e.target)) return;

      // Sustain pedal: hold the configured key. Edge-triggered so key
      // repeat can't re-fire CC chatter; release handled in onUp.
      const s = useStore.getState().settings;
      if (isSustainCode(e.code, s.pcSustainKeyCode)) {
        e.preventDefault();
        audioEngine.setLivePedal(1);
        return;
      }
      if (e.shiftKey && RESERVED_SHIFT_COMBOS.has(e.code)) return;

      // Octave shift (research-piano/20.5 — Z/X are piano keys in this map,
      // so the shift moved to PageUp/PageDown; see docs/46 CONFLICT).
      if (e.code === "PageUp" || e.code === "PageDown") {
        e.preventDefault();
        const dir = e.code === "PageUp" ? 1 : -1;
        const next = Math.min(
          PC_OCTAVE_MAX,
          Math.max(PC_OCTAVE_MIN, s.pcOctaveShift + dir),
        );
        if (next !== s.pcOctaveShift) {
          useStore.setState((st) => ({
            settings: { ...st.settings, pcOctaveShift: next },
          }));
        }
        return;
      }

      const midi = pcKeyToMidi(e.code);
      if (midi === null) return;
      e.preventDefault();
      if (pressed.has(e.code) || pending.has(e.code)) return;

      markLivePlay("pc_keyboard");

      if (Tone.getContext().state !== "running") {
        try {
          await Tone.start();
        } catch {
          /* ignored */
        }
      }

      const velocity = useStore.getState().settings.pcVelocity;
      if (audioEngine.isReady()) {
        const handle = audioEngine.triggerKey(midi, velocity);
        if (handle) pressed.set(e.code, handle.release);
        return;
      }

      pending.add(e.code);
      const ready = await ensureAudio();
      if (!pending.has(e.code)) return;
      pending.delete(e.code);
      if (!ready) return;
      const handle = audioEngine.triggerKey(midi, velocity);
      if (handle) pressed.set(e.code, handle.release);
    };

    const onUp = (e: KeyboardEvent) => {
      if (isSustainCode(e.code, useStore.getState().settings.pcSustainKeyCode)) {
        audioEngine.setLivePedal(0);
      }
      const release = pressed.get(e.code);
      if (release) {
        release();
        pressed.delete(e.code);
      }
      pending.delete(e.code);
    };

    const releaseAll = () => {
      for (const r of pressed.values()) r();
      pressed.clear();
      pending.clear();
      audioEngine.setLivePedal(0);
    };

    window.addEventListener("keydown", onDown);
    window.addEventListener("keyup", onUp);
    // Drop everything on tab switch so keys don't get stuck.
    window.addEventListener("blur", releaseAll);
    return () => {
      window.removeEventListener("keydown", onDown);
      window.removeEventListener("keyup", onUp);
      window.removeEventListener("blur", releaseAll);
      releaseAll();
    };
  }, [ensureAudio]);
}
