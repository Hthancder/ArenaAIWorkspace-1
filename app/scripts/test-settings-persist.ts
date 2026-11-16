/**
 * Settings persistence + instrument registry + cache policy tests
 * (2026-11-15 task: "cài đặt đã tùy chỉnh — lưu lại TẤT CẢ", "mặc định
 * không cache", "thêm nhạc cụ mới"). Headless — browser APIs the store
 * chain touches are shimmed at module scope before dynamic imports.
 *
 * Run: `npx vite-node scripts/test-settings-persist.ts`
 */

// ---- browser shims (module scope runs before dynamic imports) ----
const mem = new Map<string, string>()
const localStorageShim = {
  getItem: (k: string) => (mem.has(k) ? mem.get(k)! : null),
  setItem: (k: string, v: string) => void mem.set(k, String(v)),
  removeItem: (k: string) => void mem.delete(k),
  clear: () => mem.clear(),
}
Object.defineProperty(globalThis, 'localStorage', {
  value: localStorageShim,
  configurable: true,
})
// smoothRelease.ts patches AudioParam.prototype at import time.
class FakeParam {
  value = 0
  setValueAtTime() {}
  linearRampToValueAtTime() {}
  exponentialRampToValueAtTime() {}
  setTargetAtTime() {}
  cancelScheduledValues() {}
}
Object.defineProperty(globalThis, 'AudioParam', {
  value: FakeParam,
  configurable: true,
})
class FakeScheduledSourceNode {
  stop() {}
  start() {}
}
Object.defineProperty(globalThis, 'AudioScheduledSourceNode', {
  value: FakeScheduledSourceNode,
  configurable: true,
})
// No `caches` — sampleCache must fall back gracefully (isSampleCacheAvailable).
// No `window` — settingsPersist skips its pagehide hooks.

let failures = 0
function check(name: string, cond: boolean, detail = ''): void {
  if (cond) console.log(`  ok  ${name}`)
  else {
    failures++
    console.error(`FAIL  ${name} ${detail}`)
  }
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

async function main() {
  const { defaultSettings, useStore } = await import('../src/store')
  const {
    bootSettingsPersistence,
    importSettingsFile,
    resetAllSettings,
  } = await import('../src/settingsPersist')
  const {
    DEFAULT_INSTRUMENT_ID,
    getInstrument,
    hasInstrument,
    instrumentsByFamily,
  } = await import('../src/audio/instruments')
  const {
    getSampleCacheMode,
    setSampleCacheMode,
    isSampleCacheAvailable,
  } = await import('../src/audio/sampleCache')

  console.log('registry sanity')
  {
    check('default id exists', hasInstrument(DEFAULT_INSTRUMENT_ID))
    check('unknown falls back to default', getInstrument('nope').id === DEFAULT_INSTRUMENT_ID)
    const groups = instrumentsByFamily()
    const all = groups.flatMap((g) => g.items)
    const ids = new Set(all.map((d) => d.id))
    check('ids unique', ids.size === all.length, `${ids.size} vs ${all.length}`)
    check('GM has 128', all.filter((d) => d.id.startsWith('gm:')).length === 128)
    check('curated + GM = 138', all.length === 138, String(all.length))
    check('every entry has credit', all.every((d) => d.credit.length > 5))
    check('every entry has vi label', all.every((d) => d.label.length > 0))
    check('salamander is default', getInstrument(DEFAULT_INSTRUMENT_ID).family === 'piano')
  }

  console.log('sample cache policy')
  {
    check('cache API absent in node', !isSampleCacheAvailable())
    check('default mode off', getSampleCacheMode() === 'off')
    setSampleCacheMode('on')
    check('mode set + persisted', getSampleCacheMode() === 'on' && mem.get('nf:sample-cache-mode') === 'on')
    setSampleCacheMode('off')
  }

  console.log('boot restore (seeded before boot)')
  {
    // Seed a partial settings blob as an older/partial save would look:
    // only a few keys, plus one unknown key that must drop.
    mem.set(
      'nf:settings',
      JSON.stringify({
        v: 1,
        settings: {
          volume: 0.77,
          instrument: 'gm:violin',
          sampleCacheMode: 'on',
          transpose: 5,
          bogusKeyFromTheFuture: 123,
        },
        practice: { mode: 'wait', scoringOffsetMs: -12, calibrationResultMs: 23 },
      }),
    )
    bootSettingsPersistence()
    const s = useStore.getState().settings
    check('restored volume', s.volume === 0.77, String(s.volume))
    check('restored instrument', s.instrument === 'gm:violin', s.instrument)
    check('restored transpose', s.transpose === 5)
    check('unknown key dropped', !('bogusKeyFromTheFuture' in s))
    check('missing keys fill from defaults', s.releaseTime === defaultSettings.releaseTime)
    check('cache mode synced to module', getSampleCacheMode() === 'on')
    const { usePractice } = await import('../src/practice/practiceStore')
    check('practice mode restored', usePractice.getState().mode === 'wait')
    check('practice offset restored', usePractice.getState().scoringOffsetMs === -12)
    check('calibration restored', usePractice.getState().calibration.resultMs === 23)
  }

  console.log('save on change (debounced)')
  {
    useStore.setState({
      settings: { ...useStore.getState().settings, releaseTime: 0.42 },
    })
    await sleep(600) // debounce is 400 ms
    const raw = mem.get('nf:settings')
    check('envelope written', typeof raw === 'string' && raw.includes('"v":1'))
    const parsed = JSON.parse(raw ?? '{}')
    check('saved value round-trips', parsed?.settings?.releaseTime === 0.42)
  }

  console.log('corrupt data is survivable')
  {
    // importSettingsFile with junk must refuse, not throw.
    const junk = new File(['{{{not json'], 'x.json', { type: 'application/json' })
    check('junk import refused', (await importSettingsFile(junk)) === false)
    const wrongShape = new File(['{"hello":1}'], 'x.json', { type: 'application/json' })
    check('shapeless import refused', (await importSettingsFile(wrongShape)) === false)
  }

  console.log('reset to defaults')
  {
    resetAllSettings()
    const s = useStore.getState().settings
    check('reset restores defaults', s.releaseTime === defaultSettings.releaseTime && s.instrument === DEFAULT_INSTRUMENT_ID)
    check('reset clears cache mode', getSampleCacheMode() === 'off')
    const raw = mem.get('nf:settings')
    const parsed = JSON.parse(raw ?? '{}')
    check('reset is persisted', parsed?.settings?.instrument === DEFAULT_INSTRUMENT_ID)
  }

  console.log('offline dispatch patch')
  {
    const { Scheduler } = await import('smplr')
    const { retainOfflineDispatch } = await import('../src/audio/offlineDispatch')
    const ctx = { currentTime: 0 } as unknown as BaseAudioContext
    const sched = new Scheduler(ctx)
    let called = 0
    // Without the flag: a far-future event queues (callback NOT called).
    sched.schedule({ note: 60, time: 10 }, () => void called++)
    check('future event queues while realtime', called === 0)
    // With the flag: dispatch is synchronous.
    const release = retainOfflineDispatch()
    sched.schedule({ note: 60, time: 10 }, () => void called++)
    check('offline mode dispatches synchronously', called === 1)
    release()
    sched.schedule({ note: 60, time: 10 }, () => void called++)
    check('release restores queueing', called === 1)
    // Stop the scheduler's poll interval or the test process never exits.
    sched.stop()
  }

  if (failures > 0) {
    console.error(`\n${failures} FAILURE(S)`)
    process.exit(1)
  }
  console.log('\nALL SETTINGS-PERSIST TESTS PASSED')
  process.exit(0)
}

void main()
