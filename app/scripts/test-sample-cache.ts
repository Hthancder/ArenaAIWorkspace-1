/**
 * Session byte-cache tests (P2, 2026-11-15): re-selecting a just-used
 * instrument must not re-download within a tab session, while nothing
 * survives a reload. Headless — fetch is shimmed and counted; Cache
 * Storage stays absent so only the memory layer runs.
 *
 * Run: `npx vite-node scripts/test-sample-cache.ts`
 */

// ---- browser shims (module scope runs before dynamic imports) ----
const mem = new Map<string, string>()
Object.defineProperty(globalThis, 'localStorage', {
  value: {
    getItem: (k: string) => (mem.has(k) ? mem.get(k)! : null),
    setItem: (k: string, v: string) => void mem.set(k, String(v)),
    removeItem: (k: string) => void mem.delete(k),
    clear: () => mem.clear(),
  },
  configurable: true,
})

let networkCalls = 0
const networkBodies = new Map<string, Uint8Array>()
Object.defineProperty(globalThis, 'fetch', {
  value: async (url: string) => {
    networkCalls++
    const body = networkBodies.get(url)
    if (!body) return new Response('not found', { status: 404 })
    return new Response(body.slice(), { status: 200 })
  },
  configurable: true,
})

let failures = 0
function check(name: string, cond: boolean, detail = ''): void {
  if (cond) console.log(`  ok  ${name}`)
  else {
    failures++
    console.error(`FAIL  ${name} ${detail}`)
  }
}

async function main() {
  const {
    clearSampleCache,
    createSampleStorage,
    isSampleCacheAvailable,
    sessionCacheStats,
    setSessionCacheCapForTests,
  } = await import('../src/audio/sampleCache')
  const {
    getInstrumentLoad,
    setInstrumentLoad,
    subscribeInstrumentLoad,
  } = await import('../src/audio/instrumentStatus')

  console.log('session byte cache')
  {
    check('no Cache Storage in node', !isSampleCacheAvailable())
    const storage = createSampleStorage()

    networkBodies.set('a.bin', new Uint8Array([1, 2, 3, 4]))
    networkBodies.set('b.bin', new Uint8Array([9, 9]))

    // First fetch downloads; the second serves from memory.
    const r1 = await storage.fetch('a.bin')
    const after1 = networkCalls
    const r2 = await storage.fetch('a.bin')
    check('second fetch is a memory hit', networkCalls === after1)
    const b1 = new Uint8Array(await r1.arrayBuffer())
    const b2 = new Uint8Array(await r2.arrayBuffer())
    check(
      'bytes round-trip',
      b1.length === 4 && b2.length === 4 && b1[3] === 4 && b2[0] === 1,
      JSON.stringify([...b1, ...b2]),
    )
    // The cached master must survive reads that consume/detach buffers:
    // arrayBuffer() hands out copies, and text() derives on demand.
    const again = new Uint8Array(await r2.arrayBuffer())
    const asText = await storage.fetch('a.bin')
    check('repeat reads intact', again[1] === 2)
    check('text() derives from bytes', (await asText.text()).length === 4)

    // A 404 must NOT be cached — the next call goes to the network again.
    await storage.fetch('missing.bin')
    const afterMiss = networkCalls
    await storage.fetch('missing.bin')
    check('404 not cached', networkCalls === afterMiss + 1)

    console.log('LRU eviction')
    {
      setSessionCacheCapForTests(6) // a.bin (4) + b.bin (2) fit exactly
      await clearSampleCache()
      networkBodies.set('c.bin', new Uint8Array([7, 7, 7]))
      await storage.fetch('a.bin') // 4
      await storage.fetch('b.bin') // +2 = 6 (at cap)
      check('both fit the cap', sessionCacheStats().bytes === 6, JSON.stringify(sessionCacheStats()))
      // Touch a.bin so b.bin becomes the oldest, then overflow with c.bin.
      await storage.fetch('a.bin')
      await storage.fetch('c.bin') // +3 = 9 → evict oldest (b.bin, 2) → 7 → evict a.bin? (4) → 3
      const stats = sessionCacheStats()
      check('overflow evicts LRU', stats.bytes <= 6 && stats.entries === 1, JSON.stringify(stats))
      const callsBefore = networkCalls
      await storage.fetch('c.bin')
      check('survivor still cached', networkCalls === callsBefore)
      const callsBefore2 = networkCalls
      await storage.fetch('b.bin')
      check('evicted entry re-downloads', networkCalls === callsBefore2 + 1)
      setSessionCacheCapForTests(80 * 1024 * 1024)
    }

    console.log('clear wipes the session cache')
    {
      await clearSampleCache()
      check('cache empty after clear', sessionCacheStats().entries === 0)
      const before = networkCalls
      await storage.fetch('a.bin')
      check('fetch after clear hits network', networkCalls === before + 1)
    }

    console.log('oversized entries are never cached')
    {
      await clearSampleCache()
      setSessionCacheCapForTests(2)
      networkBodies.set('big.bin', new Uint8Array(8))
      await storage.fetch('big.bin')
      const before = networkCalls
      await storage.fetch('big.bin')
      check('big entry re-downloads', networkCalls === before + 1)
      setSessionCacheCapForTests(80 * 1024 * 1024)
    }
  }

  console.log('instrument status store')
  {
    const seen: string[] = []
    const unsub = subscribeInstrumentLoad((s) => seen.push(s.state))
    setInstrumentLoad({ state: 'loading', loaded: 3, total: 10 })
    setInstrumentLoad({ state: 'ready' })
    unsub()
    setInstrumentLoad({ state: 'idle' }) // after unsub — must not append
    check('subscribe/unsubscribe', seen.join(',') === 'loading,ready', seen.join(','))
    check('get reflects state', getInstrumentLoad().state === 'idle')
  }

  if (failures > 0) {
    console.error(`\n${failures} FAILURE(S)`)
    process.exit(1)
  }
  console.log('\nALL SAMPLE-CACHE TESTS PASSED')
  process.exit(0)
}

void main()
