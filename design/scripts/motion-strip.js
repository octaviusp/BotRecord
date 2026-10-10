/**
 * @schema 2.21
 * @input frames: number = 6
 * @input easing: enum("linear", "ease-out", "ease-in-out", "spring") = "ease-out"
 * @input property: enum("x", "scale", "opacity") = "x"
 * @input color: color = #2563EB
 * @input label: string = "Enter 240ms"
 */
const n = Math.max(2, Math.min(24, Math.floor(pencil.input.frames)));
const ease = {
  linear: t => t,
  "ease-out": t => 1 - Math.pow(1 - t, 3),
  "ease-in-out": t => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2),
  spring: t => 1 - Math.cos(t * Math.PI * 2.5) * Math.exp(-6 * t),
}[pencil.input.easing];
const gap = 8, labelH = 18;
const cellW = (pencil.width - gap * (n - 1)) / n;
const cellH = pencil.height - labelH - 4;
const dot = Math.min(cellW, cellH) * 0.35;
const nodes = [{ type: "text", name: "Label", x: 0, y: 0, content: pencil.input.label, fontSize: 12, fontFamily: "Inter", fill: "#667085" }];
for (let i = 0; i < n; i++) {
  const t = i / (n - 1), e = ease(t), x0 = i * (cellW + gap);
  nodes.push({ type: "rectangle", name: "Frame " + (i + 1), x: x0, y: labelH + 4, width: cellW, height: cellH, cornerRadius: 6, fill: "#F7F8FA", stroke: "#E4E7EC", strokeWidth: 1 });
  const p = pencil.input.property;
  const s = p === "scale" ? dot * (0.4 + 0.6 * e) : dot;
  const cx = p === "x" ? x0 + 6 + (cellW - 12 - s) * e : x0 + (cellW - s) / 2;
  const alpha = p === "opacity" ? Math.round(Math.max(0, Math.min(1, e)) * 255).toString(16).padStart(2, "0") : "ff";
  nodes.push({ type: "ellipse", name: "Dot " + (i + 1), x: cx, y: labelH + 4 + (cellH - s) / 2, width: s, height: s, fill: pencil.input.color + alpha });
}
return nodes;
