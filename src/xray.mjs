import { read } from './core.mjs';

// X-Ray object coverage, audited against the latest Survev ObstacleDefs
// (.cache/survev-latest @ 08346fb6, 2026-11-23). Latest defs mark vegetation with
// boolean flags (`isBush: true` / `isTree: true` on the merged ObstacleDefs registry,
// e.g. brush_01sv/brush_02sv are `isBush` but do NOT start with `bush_`). The merged
// registry is captured at runtime via captureDefinitions() and exposed as
// engine.mapDefinitions, so def flags stay authoritative when available.
// Type-name regex is only a fallback for environments where the map registry was not
// captured. Tables/stairs carry no def flag and stay regex-classified as furniture.
const VEGETATION_RE = /^(tree|bush|brush)[_-]/;
const FURNITURE_RE = /^(table|stairs)[_-]/;

// Returns 'vegetation' | 'furniture' | null for a map object type string.
// A known def without fade flags is authoritative (never faded); an unknown def or
// missing registry falls back to the regex so older bundles keep working.
export function fadeObjectKind(type, definitions = null) {
  if (typeof type !== 'string' || !type) return null;
  const def = definitions ? read(definitions, type) : null;
  if (def && typeof def === 'object') {
    if (read(def, 'isBush') === true || read(def, 'isTree') === true) return 'vegetation';
    return FURNITURE_RE.test(type) ? 'furniture' : null;
  }
  if (VEGETATION_RE.test(type)) return 'vegetation';
  if (FURNITURE_RE.test(type)) return 'furniture';
  return null;
}
