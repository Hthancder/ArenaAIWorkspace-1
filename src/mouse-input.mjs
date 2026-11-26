import { finite, point, read, vec } from './core.mjs';

// Native input-vector ownership, not OS/DOM input interception. Lock may
// capture data-property writes across frames; Assist uses a frame transaction.
// Keep real user intent separate so Assist/FOV never consume our own output.
export class MouseInputFrame {
  constructor() { this.record = null; this.appliedFrames = 0; this.skippedFrames = 0; }
  owns(input) {
    const r = this.record, mouse = read(input, 'mousePos');
    if (!r?.captured || mouse !== r.owner) return false;
    const x = Object.getOwnPropertyDescriptor(mouse, 'x'), y = Object.getOwnPropertyDescriptor(mouse, 'y');
    return x?.get === r.get.x && x?.set === r.set.x && y?.get === r.get.y && y?.set === r.set.y;
  }
  physical(input) {
    const mouse = read(input, 'mousePos'), r = this.record;
    if (r && mouse === r.owner && r.captured) {
      const x = Object.getOwnPropertyDescriptor(mouse, 'x'), y = Object.getOwnPropertyDescriptor(mouse, 'y');
      if (x?.get === r.get.x && x?.set === r.set.x && y?.get === r.get.y && y?.set === r.set.y) return { ...r.raw };
      // Another writer replaced our descriptors; do not read foreign getters.
      return null;
    }
    if (!vec(mouse)) return null;
    if (!r || mouse !== r.owner) return point(mouse);
    return { x: mouse.x === r.applied.x ? r.raw.x : mouse.x, y: mouse.y === r.applied.y ? r.raw.y : mouse.y };
  }
  apply(input, camera, plan, captureWrites = false, requireCapture = false) {
    this.restore();
    const mouse = read(input, 'mousePos'), raw = this.physical(input);
    const width = read(camera?.camera, camera?.widthKey), height = read(camera?.camera, camera?.heightKey);
    const scale = read(camera?.camera, camera?.scaleKeys?.[0]) * read(camera?.camera, camera?.scaleKeys?.[1]);
    const dx = mouse && Object.getOwnPropertyDescriptor(mouse, 'x'), dy = mouse && Object.getOwnPropertyDescriptor(mouse, 'y');
    if (!raw || !vec(plan?.dir) || !dx || !dy || !('value' in dx) || !('value' in dy) || !dx.writable || !dy.writable
      || !finite(width) || !finite(height) || width <= 0 || height <= 0 || !finite(scale) || scale <= 0
      || requireCapture && (!captureWrites || !dx.configurable || !dy.configurable)) { this.skippedFrames++; return false; }
    // Native input normalizes to (1,0) at zero radius, which disagrees with a
    // nonzero Lock direction on the wire. Give the synthetic vector a minimal
    // nonzero radius while keeping the physical cursor and normal range intact.
    const length = Math.max(scale * .00002, plan.toMouseHit ? Math.min(64, Math.max(0, plan.distance)) * scale : Math.hypot(raw.x - width / 2, raw.y - height / 2));
    const applied = { x: width / 2 + plan.dir.x * length, y: height / 2 - plan.dir.y * length };
    if (!vec(applied)) { this.skippedFrames++; return false; }
    this.record = { owner: mouse, raw, applied };
    if (captureWrites && dx.configurable && dy.configurable) {
      const r = this.record;
      r.captured = true; r.descriptors = { x: dx, y: dy }; r.get = {}; r.set = {};
      for (const key of ['x', 'y']) {
        r.get[key] = () => r.applied[key];
        r.set[key] = value => { r.raw[key] = value; };
      }
      try {
        for (const key of ['x', 'y']) Object.defineProperty(mouse, key, { configurable: true, enumerable: r.descriptors[key].enumerable, get: r.get[key], set: r.set[key] });
      } catch { this.restore(); this.skippedFrames++; return false; }
    } else {
      try { mouse.x = applied.x; mouse.y = applied.y; }
      catch { this.restore(); this.skippedFrames++; return false; }
    }
    this.appliedFrames++; return true;
  }
  // Reconstruct desktop native intent at the CURRENT zoom, before sender safety
  // recomputation. Never blend a second time from the already corrected vector.
  intent(input, camera, native) {
    if (!this.record || read(input, 'mousePos') !== this.record.owner) return native;
    const mouse = this.physical(input);
    const scale = read(camera?.camera, camera?.scaleKeys?.[0]) * read(camera?.camera, camera?.scaleKeys?.[1]);
    const x = mouse && mouse.x - read(camera?.camera, camera?.widthKey) / 2;
    const y = mouse && read(camera?.camera, camera?.heightKey) / 2 - mouse.y;
    const length = Math.hypot(x, y);
    if (!mouse || !finite(scale) || scale <= 0 || !finite(length)) return native;
    return Object.assign(Object.create(Object.getPrototypeOf(native)), native, { toMouseDir: length > .00001 * scale ? { x: x / length, y: y / length } : { x: 1, y: 0 }, toMouseLen: Math.min(64, length / scale) });
  }
  restore() {
    const r = this.record; this.record = null;
    if (!r) return;
    // Do not clobber a newer writer; restore only data coordinates we still own.
    for (const key of ['x', 'y']) {
      const d = Object.getOwnPropertyDescriptor(r.owner, key);
      if (r.captured) {
        if (d?.get === r.get[key] && d?.set === r.set[key]) Object.defineProperty(r.owner, key, { ...r.descriptors[key], value: r.raw[key] });
      } else if (d && 'value' in d && d.writable && d.value === r.applied[key]) r.owner[key] = r.raw[key];
    }
  }
  snapshot() { return { active: !!this.record, appliedFrames: this.appliedFrames, skippedFrames: this.skippedFrames }; }
}
