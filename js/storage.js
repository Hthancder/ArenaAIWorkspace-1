const KEY = 'lumen.save.v1';

const DEFAULTS = {
  progress: {},
  settings: { sound: true, motion: true, zen: false, haptics: true },
  lastLevel: 0,
  seenHowTo: false,
};

function cloneDefaults() {
  return JSON.parse(JSON.stringify(DEFAULTS));
}

export function loadSave() {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return cloneDefaults();
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object') return cloneDefaults();
    const out = cloneDefaults();
    if (parsed.progress && typeof parsed.progress === 'object') {
      for (const [k, v] of Object.entries(parsed.progress)) {
        const idx = Number(k);
        if (!Number.isInteger(idx) || idx < 0) continue;
        if (!v || typeof v !== 'object') continue;
        const stars = Math.max(0, Math.min(3, Number(v.stars) || 0));
        const best = Number(v.best);
        out.progress[idx] = {
          stars,
          best: Number.isFinite(best) && best > 0 ? best : undefined,
        };
      }
    }
    if (parsed.settings && typeof parsed.settings === 'object') {
      for (const key of Object.keys(out.settings)) {
        if (typeof parsed.settings[key] === 'boolean') out.settings[key] = parsed.settings[key];
      }
    }
    if (Number.isInteger(parsed.lastLevel)) {
      out.lastLevel = Math.max(0, Math.min(599, parsed.lastLevel));
    }
    out.seenHowTo = Boolean(parsed.seenHowTo);
    return out;
  } catch {
    return cloneDefaults();
  }
}

export function persist(save) {
  try {
    localStorage.setItem(KEY, JSON.stringify(save));
  } catch {
    /* storage may be unavailable — the game still works for this session */
  }
}

export function clearSave() {
  try {
    localStorage.removeItem(KEY);
  } catch {
    /* ignore */
  }
}
