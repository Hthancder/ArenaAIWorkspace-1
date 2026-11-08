'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const net = require('node:net');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

async function freePort() {
  const server = net.createServer();
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  await new Promise(resolve => server.close(resolve));
  return port;
}

test('mock backend serves connected device/window/session/settings flow', async t => {
  const port = await freePort();
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'lantern-mock-'));
  const child = spawn(process.execPath, [path.join(__dirname, 'server.js')], {
    env: { ...process.env, HOST: '127.0.0.1', PORT: String(port), MOCK_DATA_DIR: dataDir },
    stdio: 'ignore',
  });
  const base = `http://127.0.0.1:${port}`;
  t.after(async () => {
    child.kill('SIGTERM');
    await new Promise(resolve => child.once('exit', resolve));
    fs.rmSync(dataDir, { recursive: true, force: true });
  });
  let ready = false;
  for (let i = 0; i < 60; i++) {
    try { ready = (await fetch(`${base}/api/health`)).ok; } catch {}
    if (ready) break;
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  assert.equal(ready, true, 'backend starts and answers health check');

  const device = await (await fetch(`${base}/api/device`)).json();
  assert.equal(device.name, 'Inspiron 7467');
  assert.equal((await (await fetch(`${base}/api/windows`)).json()).windows.length, 3);
  assert.equal((await (await fetch(`${base}/api/diagnostics`)).json()).mock, true);
  assert.equal((await (await fetch(`${base}/api/sessions/current`)).json()).session, null);

  const saved = await fetch(`${base}/api/settings`, { method: 'PATCH', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ quality: 'smooth', volume: 35, unknown: 'bad' }) });
  assert.deepEqual((await saved.json()).updated, ['quality', 'volume']);
  assert.equal(JSON.parse(fs.readFileSync(path.join(dataDir, 'settings.json'))).volume, 35);
  const invalid = await fetch(`${base}/api/settings`, { method: 'PATCH', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ quality: 'disable-encryption' }) });
  assert.equal(invalid.status, 422);

  const started = await fetch(`${base}/api/sessions`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ mode: 'hvnc', windowId: 'browser' }) });
  assert.equal(started.status, 201);
  const session = (await started.json()).session;
  assert.equal(session.windowId, 'browser');
  assert.equal((await fetch(`${base}/api/sessions`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' })).status, 409);
  assert.equal((await fetch(`${base}/api/sessions/${session.id}`, { method: 'DELETE' })).status, 200);
  assert.equal((await (await fetch(`${base}/api/sessions/current`)).json()).session, null);
  assert.equal((await fetch(`${base}/`)).status, 200);
});
