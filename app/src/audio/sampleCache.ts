import { HttpStorage, type Storage, type StorageResponse } from 'smplr'

/**
 * Sample caching policy — the user decides whether downloaded sound
 * files are kept between reloads.
 *
 * Requirement (2026-11-15): by default NOTHING is cached — reloading
 * the page must re-download every sample. Caching is opt-in, two ways:
 *
 * - `sampleCacheMode: 'on'` — auto: every fetched sample is stored in
 *   Cache Storage and reused on later loads.
 * - manual save (`cacheSamplesNow`) — stores the samples fetched so far
 *   this session (plus the hands motion DB) and records them in a
 *   manifest; those files, and only those, are reused on later loads
 *   even while auto mode is off.
 *
 * Read rule (in order): (1) the in-memory SESSION byte cache — raw
 * fetched bytes kept for this tab session only (P2 decision
 * 2026-11-15: re-selecting a just-used instrument must not re-download;
 * the bytes die with the reload, so "reload re-downloads everything"
 * still holds); (2) Cache Storage iff auto mode is on OR the URL is in
 * the manual manifest; (3) the network with `cache: 'no-store'` when
 * the Cache Storage policy doesn't want this file — the files are
 * served with year-long immutable headers (vercel.json), so without
 * this a plain reload would still be served from the HTTP cache and
 * the "reload re-downloads" requirement would silently fail. Successful
 * network reads populate the session cache (LRU, capped — see
 * SESSION_CACHE_CAP_BYTES).
 *
 * smplr ships its own `CacheStorage` wrapper, but it caches *every*
 * response — including 404s and 5xx errors. If the user toggles
 * HQ Piano on before the sample files are deployed, the 404
 * responses get cached and persist after the files become
 * available, leaving specific samples permanently silent until the
 * user manually clears site data. We wrap our own layer that only
 * stores 200 responses so transient failures self-heal.
 *
 * Versioned cache name (`v2` and up) lets us invalidate on a code
 * deploy if we discover poisoned caches from older builds.
 *
 * Falls back to plain HttpStorage when `fetch`/`Request` are missing
 * (very old browser); the session cache works with or without Cache
 * Storage, which only affects the disk layer.
 */

// v3: previous (v2) builds passed a synthetic Response to cache.put,
// which in some browsers landed without a usable body — cache.match
// then returned undefined and every page reload re-fetched. Bump on
// any code change to invalidate previous-build entries.
const CACHE_NAME = 'notefall-samples-v3'
const LEGACY_CACHE_NAMES = [
  'notefall-samples-v1',
  'notefall-samples-v2',
] as const
/** Cache the hands runtime's Worker stores the ~22 MB motion DB in (see runtime/hands-worker.js). */
export const HANDS_CACHE_NAME = 'nf-motion-db'
/** localStorage keys for the cache policy (mode + manual-save manifest). */
const MODE_KEY = 'nf:sample-cache-mode'
const MANUAL_KEY = 'nf:sample-cache-manual'

export type SampleCacheMode = 'off' | 'on'

let mode: SampleCacheMode = 'off'
/** URLs the user explicitly saved via `cacheSamplesNow` (persisted). */
const manualUrls = new Set<string>()
/** URLs the sample storage has seen this session (current + earlier instruments). */
const seenUrls = new Set<string>()

// ── Session byte cache (in-memory, tab-scoped) ──────────────────────
//
// Raw fetched bytes kept ONLY for this browser tab: switching back to a
// just-used instrument re-serves instantly instead of re-downloading.
// Deliberately memory-only — a reload wipes it, which is exactly the
// "reload re-downloads everything" default. LRU by access order, capped
// so long instrument-hopping sessions can't grow without bound (P2:
// "chỉ cache bytes nén — nhẹ RAM"). Decoded AudioBuffers are NOT kept
// (a salamander set decodes to ~719 MB of float32 PCM — measured — so
// retaining instruments' decoded samples would blow memory far faster
// than the compressed bytes do).

const SESSION_CACHE_CAP_BYTES = 80 * 1024 * 1024
let sessionCacheCapBytes = SESSION_CACHE_CAP_BYTES
/** LRU: Map iteration order = oldest first; hits re-insert to the end. */
const sessionBytes = new Map<string, ArrayBuffer>()
let sessionBytesTotal = 0

/** Test hook — shrink the cap to exercise eviction. */
export function setSessionCacheCapForTests(bytes: number): void {
  sessionCacheCapBytes = Math.max(0, bytes)
  evictSessionCache()
}

export function sessionCacheStats(): { entries: number; bytes: number } {
  return { entries: sessionBytes.size, bytes: sessionBytesTotal }
}

function sessionGet(url: string): ArrayBuffer | undefined {
  const hit = sessionBytes.get(url)
  if (hit) {
    sessionBytes.delete(url)
    sessionBytes.set(url, hit) // mark as most-recently-used
  }
  return hit
}

function sessionPut(url: string, bytes: ArrayBuffer): void {
  if (bytes.byteLength > sessionCacheCapBytes) return // never cacheable alone
  const prev = sessionBytes.get(url)
  if (prev) sessionBytesTotal -= prev.byteLength
  sessionBytes.delete(url)
  sessionBytes.set(url, bytes)
  sessionBytesTotal += bytes.byteLength
  evictSessionCache()
}

function evictSessionCache(): void {
  while (sessionBytesTotal > sessionCacheCapBytes && sessionBytes.size > 0) {
    const oldest = sessionBytes.keys().next().value as string
    const bytes = sessionBytes.get(oldest)!
    sessionBytes.delete(oldest)
    sessionBytesTotal -= bytes.byteLength
  }
}

function clearSessionCache(): void {
  sessionBytes.clear()
  sessionBytesTotal = 0
}

/**
 * StorageResponse over cached raw bytes. `arrayBuffer()` hands out a
 * COPY — smplr may decode (which some engines detach) or read the same
 * entry again on a later switch, so the cached master must survive.
 */
function sessionResponse(bytes: ArrayBuffer): StorageResponse {
  return {
    status: 200,
    arrayBuffer: async () => bytes.slice(0),
    text: async () => new TextDecoder().decode(bytes),
    json: async () => JSON.parse(new TextDecoder().decode(bytes)) as unknown,
  }
}

/** Whether Cache Storage is usable in this environment. */
export function isSampleCacheAvailable(): boolean {
  return typeof globalThis.caches !== 'undefined'
}

function loadPersistedPolicy(): void {
  try {
    const m = localStorage.getItem(MODE_KEY)
    if (m === 'on' || m === 'off') mode = m
    const raw = localStorage.getItem(MANUAL_KEY)
    if (raw) {
      const list = JSON.parse(raw) as unknown
      if (Array.isArray(list)) {
        for (const u of list) if (typeof u === 'string') manualUrls.add(u)
      }
    }
  } catch {
    /* corrupted / unavailable storage — keep the safe default (off) */
  }
}
loadPersistedPolicy()

export function getSampleCacheMode(): SampleCacheMode {
  return mode
}

export function setSampleCacheMode(next: SampleCacheMode): void {
  mode = next
  try {
    localStorage.setItem(MODE_KEY, next)
  } catch {
    /* ignore */
  }
}

/** Does the policy currently serve `url` from Cache Storage? */
function usesCacheFor(url: string): boolean {
  return mode === 'on' || manualUrls.has(url)
}

// One-time per-session diagnostic so the user can verify cache
// behaviour from the DevTools console. Logs the first hit + first
// miss only, to avoid 480 lines of spam.
let loggedHit = false
let loggedMiss = false

/**
 * Storage wrapper implementing the cache policy above. Only stores 200
 * responses. 404 / 5xx / network failures fall through to the
 * underlying fetch on every call so a deferred file deployment becomes
 * playable as soon as it shows up, instead of being stuck behind
 * a cached failure forever.
 *
 * Uses `Request` + `Response.clone()` (same pattern as smplr's
 * built-in CacheStorage) — passing a synthesised `new Response(ab)`
 * to `cache.put` worked in Chrome but failed silently in some
 * other browsers, leaving the cache permanently empty.
 */
class PolicyStorage implements Storage {
  async fetch(url: string): Promise<StorageResponse> {
    seenUrls.add(url)

    // 1. Session byte cache — instant reuse when switching back to an
    //    instrument already loaded this tab (no network, no decode-data
    //    re-download; smplr still decodes per build).
    const mem = sessionGet(url)
    if (mem) return sessionResponse(mem)

    const wantCache = usesCacheFor(url)
    const cache =
      wantCache && isSampleCacheAvailable()
        ? await caches.open(CACHE_NAME).catch(() => null)
        : null

    if (cache) {
      const hit = await cache.match(url).catch(() => undefined)
      if (hit && hit.status === 200) {
        if (!loggedHit) {
          loggedHit = true
          // eslint-disable-next-line no-console
          console.info(
            '[sampleCache] cache HIT (' + CACHE_NAME + ') — serving from Cache Storage',
          )
        }
        // Read into the session cache so the next build is instant.
        try {
          const bytes = await hit.clone().arrayBuffer()
          sessionPut(url, bytes)
        } catch {
          /* keep the plain hit */
        }
        return hit
      }
    }

    if (!loggedMiss && isSampleCacheAvailable()) {
      loggedMiss = true
      // eslint-disable-next-line no-console
      console.info(
        '[sampleCache] cache MISS — fetching from network' +
          (wantCache ? ' and persisting' : ' (cache off, nothing stored)'),
      )
    }

    // `cache: 'no-store'` skips the browser HTTP cache when the Cache
    // Storage policy doesn't want this file — the immutable headers on
    // /samples/* would otherwise serve reloads from the HTTP cache.
    const fresh = await fetch(url, wantCache ? undefined : { cache: 'no-store' })
    if (cache && fresh.status === 200) {
      try {
        // clone() gives us an independent Response stream to hand
        // to cache.put; the original `fresh` still has an intact
        // body that smplr will read via `arrayBuffer()`.
        await cache.put(url, fresh.clone())
      } catch (err) {
        // eslint-disable-next-line no-console
        console.warn('[sampleCache] cache.put failed for', url, err)
      }
    }
    if (fresh.status === 200) {
      try {
        const bytes = await fresh.clone().arrayBuffer()
        sessionPut(url, bytes)
      } catch {
        /* session cache is best-effort */
      }
    }
    return fresh
  }
}

/** Storage for smplr instrument constructors (see the policy above). */
export function createSampleStorage(): Storage {
  if (typeof fetch === 'undefined' || typeof Request === 'undefined') {
    return HttpStorage
  }
  // Best-effort cleanup of older cache versions so they don't
  // silently consume disk forever. Fire-and-forget.
  void purgeLegacyCaches()
  return new PolicyStorage()
}

async function purgeLegacyCaches(): Promise<void> {
  if (!isSampleCacheAvailable()) return
  for (const name of LEGACY_CACHE_NAMES) {
    try {
      await caches.delete(name)
    } catch {
      /* ignore */
    }
  }
}

/**
 * Manual save: store every sample fetched so far this session (plus the
 * hands motion DB when its URL is known) into Cache Storage and record
 * the URLs in the persisted manifest, so later loads reuse them even
 * while auto cache mode is off. Returns how many files were stored.
 */
export async function cacheSamplesNow(
  extraUrls: readonly string[] = [],
): Promise<{ saved: number; failed: number }> {
  if (!isSampleCacheAvailable()) return { saved: 0, failed: 0 }
  const cache = await caches.open(CACHE_NAME).catch(() => null)
  if (!cache) return { saved: 0, failed: 0 }
  let saved = 0
  let failed = 0
  for (const url of [...seenUrls, ...extraUrls]) {
    try {
      const res = await fetch(url, { cache: 'no-store' })
      if (res.status === 200) {
        await cache.put(url, res.clone())
        manualUrls.add(url)
        saved++
      } else {
        failed++
      }
    } catch {
      failed++
    }
  }
  try {
    localStorage.setItem(MANUAL_KEY, JSON.stringify([...manualUrls]))
  } catch {
    /* ignore */
  }
  return { saved, failed }
}

/**
 * Manual clear: wipe the in-memory session bytes, every cache this app
 * may have written (sample sets across versions + the hands motion DB)
 * and the manual manifest. After this the default "reload re-downloads
 * everything" behaviour is fully restored — and re-selecting an
 * already-used instrument re-downloads too.
 */
export async function clearSampleCache(): Promise<void> {
  clearSessionCache()
  if (!isSampleCacheAvailable()) return
  const keys = await caches.keys().catch(() => [] as string[])
  for (const name of keys) {
    // Only our namespaces — the origin is app-dedicated, but deleting
    // arbitrary foreign caches would be rude in an embedded preview.
    if (name.startsWith('notefall-') || name.startsWith('nf-')) {
      try {
        await caches.delete(name)
      } catch {
        /* ignore */
      }
    }
  }
  manualUrls.clear()
  try {
    localStorage.removeItem(MANUAL_KEY)
  } catch {
    /* ignore */
  }
}

/** Approximate bytes currently stored in the app's caches (for the UI). */
export async function sampleCacheSizeBytes(): Promise<number> {
  if (!isSampleCacheAvailable()) return 0
  let total = 0
  const keys = await caches.keys().catch(() => [] as string[])
  for (const name of keys) {
    if (!name.startsWith('notefall-') && !name.startsWith('nf-')) continue
    try {
      const cache = await caches.open(name)
      const reqs = await cache.keys()
      for (const req of reqs) {
        const res = await cache.match(req)
        if (!res) continue
        // Prefer the Content-Length header — reading every body just to
        // measure the cache would stream hundreds of megabytes.
        const header = Number(res.headers.get('content-length'))
        total += Number.isFinite(header) && header > 0 ? header : 0
      }
    } catch {
      /* ignore */
    }
  }
  return total
}
