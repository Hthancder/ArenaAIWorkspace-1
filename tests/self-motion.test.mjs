import test from 'node:test';
import assert from 'node:assert/strict';
import { projectOwnOrigin } from '../src/self-motion.mjs';
const origin={x:10,y:20}, movement={x:0,y:1}, now=1000;
const track={age:.02,vx:0,vy:8,error:.03,samples:[{t:900},{t:933},{t:966}]};
const timing={rtt:80,lastRtt:80,rttAt:990};
test('projection uses bounded observed own velocity and a fresh RTT only when intent agrees', () => {
  const result=projectOwnOrigin(origin,track,movement,timing,now);
  assert.equal(result.seconds,.1); assert.equal(result.x,10); assert.equal(result.y,20.8);
  for (const m of [{x:0,y:0},{x:0,y:-1},{x:1,y:0}]) assert.equal(projectOwnOrigin(origin,track,m,timing,now),null);
  for (const value of [{...track,age:.2},{...track,samples:[{t:950}]},{...track,error:.2},{...track,vx:50},{...track,vy:0}])
    assert.equal(projectOwnOrigin(origin,value,movement,timing,now),null);
  for (const value of [{...timing,rtt:null},{...timing,rtt:250},{...timing,lastRtt:250},{...timing,rttAt:-1000}])
    assert.equal(projectOwnOrigin(origin,track,movement,value,now),null);
  assert.equal(projectOwnOrigin(origin,{...track,age:.1},movement,{...timing,rtt:200,lastRtt:200},now).seconds,.2);
});
