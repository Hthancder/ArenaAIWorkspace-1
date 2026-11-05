// Lightweight canvas effects: twinkling starfield + confetti / spark bursts.

export class Starfield {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.stars = [];
    this.motion = true;
    this.raf = 0;
    this.w = 0;
    this.h = 0;
    this.resize();
    window.addEventListener('resize', () => this.resize());
    this.start();
  }

  resize() {
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    this.w = window.innerWidth;
    this.h = window.innerHeight;
    this.canvas.width = Math.floor(this.w * dpr);
    this.canvas.height = Math.floor(this.h * dpr);
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.build();
    if (!this.motion) this.draw(0);
  }

  build() {
    const count = Math.round(Math.min(190, Math.max(60, (this.w * this.h) / 11000)));
    this.stars = Array.from({ length: count }, () => {
      const big = Math.random() < 0.075;
      return {
        x: Math.random() * this.w,
        y: Math.random() * this.h,
        r: big ? 1.1 + Math.random() * 0.9 : 0.35 + Math.random() * 0.85,
        a: 0.16 + Math.random() * 0.55,
        tw: 0.35 + Math.random() * 1.3,
        ph: Math.random() * Math.PI * 2,
        vx: (Math.random() - 0.5) * 0.01,
        vy: (Math.random() - 0.5) * 0.01,
        big,
      };
    });
  }

  start() {
    if (this.raf) return;
    const loop = (t) => {
      this.raf = requestAnimationFrame(loop);
      if (!this.motion) return;
      this.draw(t);
    };
    this.raf = requestAnimationFrame(loop);
  }

  setMotion(v) {
    this.motion = v;
    if (!v) this.draw(0);
  }

  draw(t) {
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.w, this.h);
    const time = t * 0.001;
    for (const s of this.stars) {
      if (this.motion) {
        s.x += s.vx;
        s.y += s.vy;
        if (s.x < -2) s.x = this.w + 2;
        if (s.x > this.w + 2) s.x = -2;
        if (s.y < -2) s.y = this.h + 2;
        if (s.y > this.h + 2) s.y = -2;
      }
      const alpha = this.motion ? s.a * (0.72 + 0.28 * Math.sin(time * s.tw + s.ph)) : s.a;
      ctx.beginPath();
      ctx.fillStyle = `rgba(214, 232, 255, ${alpha})`;
      ctx.arc(s.x, s.y, s.r, 0, Math.PI * 2);
      ctx.fill();
      if (s.big) {
        ctx.strokeStyle = `rgba(190, 220, 255, ${alpha * 0.32})`;
        ctx.lineWidth = 0.7;
        ctx.beginPath();
        ctx.moveTo(s.x - s.r * 3.4, s.y);
        ctx.lineTo(s.x + s.r * 3.4, s.y);
        ctx.moveTo(s.x, s.y - s.r * 3.4);
        ctx.lineTo(s.x, s.y + s.r * 3.4);
        ctx.stroke();
      }
    }
  }
}

export class FX {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.parts = [];
    this.raf = 0;
    this.motion = true;
    this.w = 0;
    this.h = 0;
    this.resize();
    window.addEventListener('resize', () => this.resize());
  }

  resize() {
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    this.w = window.innerWidth;
    this.h = window.innerHeight;
    this.canvas.width = Math.floor(this.w * dpr);
    this.canvas.height = Math.floor(this.h * dpr);
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  setMotion(v) {
    this.motion = v;
    if (!v) {
      this.parts = [];
      this.ctx.clearRect(0, 0, this.w, this.h);
    }
  }

  burst(x, y, color, count = 16) {
    if (!this.motion) return;
    for (let i = 0; i < count; i++) {
      const a = Math.random() * Math.PI * 2;
      const sp = 40 + Math.random() * 170;
      this.parts.push({
        x, y,
        vx: Math.cos(a) * sp,
        vy: Math.sin(a) * sp - 25,
        life: 0,
        max: 0.55 + Math.random() * 0.5,
        size: 1.4 + Math.random() * 2.4,
        color,
        grav: 70,
        shape: 'circle',
      });
    }
    this.start();
  }

  confetti(colors) {
    if (!this.motion) return;
    const n = Math.min(170, Math.round(this.w / 7));
    for (let i = 0; i < n; i++) {
      this.parts.push({
        x: Math.random() * this.w,
        y: -20 - Math.random() * this.h * 0.35,
        vx: (Math.random() - 0.5) * 90,
        vy: 60 + Math.random() * 150,
        life: 0,
        max: 2.4 + Math.random() * 1.7,
        size: 3 + Math.random() * 4,
        color: colors[Math.floor(Math.random() * colors.length)],
        grav: 95,
        shape: Math.random() < 0.5 ? 'rect' : 'circle',
        rot: Math.random() * Math.PI,
        vr: (Math.random() - 0.5) * 7,
      });
    }
    this.start();
  }

  start() {
    if (this.raf) return;
    let last = performance.now();
    const loop = (t) => {
      const dt = Math.min(0.05, (t - last) / 1000);
      last = t;
      this.update(dt);
      if (this.parts.length) {
        this.raf = requestAnimationFrame(loop);
      } else {
        this.raf = 0;
        this.ctx.clearRect(0, 0, this.w, this.h);
      }
    };
    this.raf = requestAnimationFrame(loop);
  }

  update(dt) {
    const ctx = this.ctx;
    ctx.clearRect(0, 0, this.w, this.h);
    for (const p of this.parts) {
      p.life += dt;
      p.vy += p.grav * dt;
      p.vx *= 0.995;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      if (p.rot !== undefined) p.rot += p.vr * dt;
      const k = 1 - p.life / p.max;
      if (k <= 0) continue;
      ctx.globalAlpha = Math.max(0, Math.min(1, k));
      ctx.fillStyle = p.color;
      if (p.shape === 'rect') {
        ctx.save();
        ctx.translate(p.x, p.y);
        ctx.rotate(p.rot);
        ctx.fillRect(-p.size / 2, -p.size / 4, p.size, p.size / 2);
        ctx.restore();
      } else {
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
        ctx.fill();
      }
    }
    ctx.globalAlpha = 1;
    this.parts = this.parts.filter((p) => p.life < p.max && p.y < this.h + 50);
  }
}
