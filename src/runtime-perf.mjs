import { finite } from './core.mjs';

// Bounded local measurements of script work only; never user or game data.
export class RuntimePerf {
  constructor(limit = 256) { this.limit = limit; this.series = new Map(); }
  add(name, ms) {
    if (!finite(ms) || ms < 0 || ms > 60000) return;
    let row = this.series.get(name);
    if (!row) this.series.set(name, row = { samples: [], next: 0, peak: 0, count: 0 });
    row.count++; row.peak = Math.max(row.peak, ms);
    if (row.samples.length < this.limit) row.samples.push(ms);
    else { row.samples[row.next] = ms; row.next = (row.next + 1) % this.limit; }
  }
  snapshot() {
    return Object.fromEntries([...this.series].map(([key, row]) => {
      const a = [...row.samples].sort((x, y) => x-y);
      const round = n => Math.round(n * 1000) / 1000;
      return [key, { samples: a.length, count: row.count, p95Ms: round(a[Math.floor((a.length-1)*.95)]), maxMs: round(a[a.length-1]), sessionPeakMs: round(row.peak) }];
    }));
  }
}
