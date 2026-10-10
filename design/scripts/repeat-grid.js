/**
 * @schema 2.21
 * @input target: ref
 * @input columns: number = 3
 * @input count: number = 6
 * @input gap: number = 16
 */
const cols = Math.max(1, Math.floor(pencil.input.columns));
const count = Math.max(1, Math.min(200, Math.floor(pencil.input.count)));
const gap = pencil.input.gap;
const w = (pencil.width - gap * (cols - 1)) / cols;
const rows = Math.ceil(count / cols);
const h = (pencil.height - gap * (rows - 1)) / rows;
const out = [];
for (let i = 0; i < count; i++) {
  out.push({ type: "ref", ref: pencil.input.target, name: "Item " + (i + 1), x: (i % cols) * (w + gap), y: Math.floor(i / cols) * (h + gap), width: w, height: h });
}
return out;
