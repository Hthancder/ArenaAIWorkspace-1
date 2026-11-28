import test from 'node:test';
import assert from 'node:assert/strict';
import { inferredStationary } from '../src/stationary-inference.mjs';
const p={x:3,y:4};
const observed={pos:p,time:100,layer:0};
const quiet={pos:p,time:133,layer:0,age:0,vx:0,vy:0,samples:[{p,t:100},{p,t:133}]};
test('stationary inference requires a fresh newer omission for early use', () => {
  assert.deepEqual(inferredStationary(observed,quiet,true).motion,[]);
  assert.equal(inferredStationary(observed,{...quiet,time:100},true),null);
  assert.equal(inferredStationary(observed,{...quiet,layer:1},true),null);
  assert.equal(inferredStationary(observed,{...quiet,pos:{x:3.2,y:4}},true),null);
  assert.equal(inferredStationary(observed,{...quiet,age:.151},true),null);
  assert.equal(inferredStationary(observed,{...quiet,vx:1},true),null);
  assert.equal(inferredStationary(observed,{...quiet,samples:[quiet.samples[0]]},true),null);
  assert.equal(inferredStationary(observed,{...quiet,samples:[{p:{x:3.1,y:4},t:100},quiet.samples[1]]},true),null);
  assert.equal(inferredStationary(null,quiet,true),null);
  assert.ok(inferredStationary(null,quiet,false), 'existing stale fallback remains possible');
});
