import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

test('pinned-source duel smoke: actual gun, bullet, grid and movement adapter', { skip: !existsSync('.cache/survev/.git') && 'optional pinned Survev checkout not present' }, () => {
  const result=spawnSync(process.execPath,['scripts/benchmark-source-duel.mjs','--smoke'],{encoding:'utf8',timeout:30000});
  assert.equal(result.status,0,`${result.stdout}\n${result.stderr}`);
  assert.match(result.stdout,/PASS source smoke/);
});
