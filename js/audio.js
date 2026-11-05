// Tiny WebAudio synth — no audio files needed.

class AudioEngine {
  constructor() {
    this.ctx = null;
    this.master = null;
    this.enabled = true;
  }

  ensure() {
    if (!this.enabled) return null;
    if (!this.ctx) {
      const Ctx = window.AudioContext || window.webkitAudioContext;
      if (!Ctx) return null;
      try {
        this.ctx = new Ctx();
        this.master = this.ctx.createGain();
        this.master.gain.value = 0.55;
        this.master.connect(this.ctx.destination);
      } catch {
        return null;
      }
    }
    if (this.ctx.state === 'suspended') this.ctx.resume().catch(() => {});
    return this.ctx;
  }

  tone(freq, dur = 0.2, type = 'sine', gain = 0.05, delay = 0) {
    const ctx = this.ensure();
    if (!ctx) return;
    const t0 = ctx.currentTime + delay;
    const osc = ctx.createOscillator();
    const env = ctx.createGain();
    const filter = ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.setValueAtTime(4200, t0);
    osc.type = type;
    osc.frequency.setValueAtTime(freq, t0);
    env.gain.setValueAtTime(0.0001, t0);
    env.gain.linearRampToValueAtTime(gain, t0 + 0.008);
    env.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    osc.connect(env);
    env.connect(filter);
    filter.connect(this.master);
    osc.start(t0);
    osc.stop(t0 + dur + 0.03);
  }

  rotate(x, y) {
    const scale = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1174.66];
    const note = scale[Math.abs(x * 2 + y * 3) % scale.length];
    this.tone(note, 0.16, 'triangle', 0.032);
    this.tone(note * 2, 0.07, 'sine', 0.01);
  }

  connect() {
    this.tone(1046.5, 0.32, 'sine', 0.035);
    this.tone(1567.98, 0.42, 'sine', 0.026, 0.07);
  }

  hint() {
    this.tone(880, 0.18, 'sine', 0.03);
    this.tone(1174.66, 0.28, 'sine', 0.024, 0.06);
  }

  click() {
    this.tone(340, 0.05, 'sine', 0.018);
  }

  blocked() {
    this.tone(150, 0.1, 'sine', 0.025);
  }

  win() {
    const notes = [523.25, 659.25, 783.99, 1046.5, 1318.51];
    notes.forEach((n, i) => this.tone(n, 0.5, 'triangle', 0.045, i * 0.085));
    this.tone(261.63, 0.9, 'sine', 0.03, 0.05);
  }
}

export const audio = new AudioEngine();
