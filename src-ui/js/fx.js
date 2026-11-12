/* Taskora — hiệu ứng thỏa mãn (confetti) */
import { $ } from "./dom.js";
import { S, s_isAdhd } from "./state.js";


export function confettiBurst(x, y) {
  if (!s_isAdhd()) return;
  if (S.snap?.settings?.reduce_motion) return;
  if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  const colors = ["#818cf8", "#c084fc", "#facc15", "#34d399", "#fb7185", "#38bdf8"];
  for (let i = 0; i < 26; i++) {
    const p = document.createElement("div");
    p.className = "confetti-piece";
    p.style.background = colors[i % colors.length];
    document.body.appendChild(p);
    const ang = Math.random() * Math.PI * 2, v = 110 + Math.random() * 230;
    const dx = Math.cos(ang) * v, dy = Math.sin(ang) * v - 70, rot = Math.random() * 720 - 360;
    if (typeof p.animate === "function") {
      const anim = p.animate([
        { transform: `translate(${x}px, ${y}px) rotate(0deg)`, opacity: 1 },
        { transform: `translate(${x + dx}px, ${y + dy + 340}px) rotate(${rot}deg)`, opacity: 0 }
      ], { duration: 950 + Math.random() * 300, easing: "cubic-bezier(.16,.84,.3,1)" });
      anim.onfinish = () => p.remove();
    } else { setTimeout(() => p.remove(), 1000); }
  }
}
