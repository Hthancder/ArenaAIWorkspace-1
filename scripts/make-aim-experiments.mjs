// Generate isolated experimental aim modules in the ignored cache. Never edit src.
import { mkdir, readFile, writeFile, copyFile } from 'node:fs/promises';
const source = await readFile(new URL('../src/aim.mjs', import.meta.url), 'utf8');
const marker = '  const last = samples.at(-1);\n  // Reversals can happen';
if (source.split(marker).length !== 2) throw new Error('aim.mjs changed; review experiment before regenerating');
const directory = new URL('../.cache/aim-candidates/', import.meta.url);
await mkdir(directory, { recursive: true });
await copyFile(new URL('../src/core.mjs', import.meta.url), new URL('core.mjs', directory));
for (const threshold of [.55, .8, 1]) {
  const code = `  // Experimental sustained monotone movement inside observed bounds.\n  if (samples.length >= 4) {\n    const recent = samples.slice(-4), axis = (maxX - minX >= maxY - minY) ? 'x' : 'y';\n    const deltas = recent.slice(1).map((v, i) => v.p[axis] - recent[i].p[axis]);\n    const extent = axis === 'x' ? maxX - minX : maxY - minY;\n    if (deltas.every(d => d > .035) || deltas.every(d => d < -.035)) {\n      if (Math.abs(recent.at(-1).p[axis] - recent[0].p[axis]) > Math.max(.2, extent * ${threshold})) return null;\n    }\n  }\n`;
  await writeFile(new URL(`aim-${threshold}.mjs`, directory), source.replace(marker, `  const last = samples.at(-1);\n${code}  // Reversals can happen`));
  console.log(`.cache/aim-candidates/aim-${threshold}.mjs`);
}
