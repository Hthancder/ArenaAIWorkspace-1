import { clamp, finite, vec } from './core.mjs';

// Render-only: center is the player's current visual position, not lead point.
export function drawTargetIndicator(ctx, center, size, style = 'ring') {
  if (!ctx || !vec(center) || !finite(size)) return false;
  const r = clamp(size, 12, 56), x = center.x, y = center.y;
  ctx.save();
  try {
    ctx.globalAlpha = 1; ctx.setLineDash([]); ctx.strokeStyle = '#ffcf40'; ctx.lineWidth = 2;
    ctx.beginPath();
    if (style === 'cross') {
      const a = r * .65, b = r * 1.1;
      ctx.moveTo(x - b, y); ctx.lineTo(x - a, y); ctx.moveTo(x + a, y); ctx.lineTo(x + b, y);
      ctx.moveTo(x, y - b); ctx.lineTo(x, y - a); ctx.moveTo(x, y + a); ctx.lineTo(x, y + b);
    } else if (style === 'brackets') {
      const a = r * .5;
      for (const [sx, sy] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
        ctx.moveTo(x + sx * a, y + sy * r); ctx.lineTo(x + sx * r, y + sy * r); ctx.lineTo(x + sx * r, y + sy * a);
      }
    } else if (style === 'diamond') {
      ctx.moveTo(x, y - r); ctx.lineTo(x + r, y); ctx.lineTo(x, y + r); ctx.lineTo(x - r, y); ctx.closePath();
    } else ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.stroke();
  } finally { ctx.restore(); }
  return true;
}
