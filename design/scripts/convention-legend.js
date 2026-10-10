/**
 * @schema 2.21
 * @input json: string = "{}"
 * @input title: string = "Naming convention · [TYPE][NAME][VARIANT]"
 */
const families = JSON.parse(pencil.input.json || "{}");
const names = Object.keys(families);
const colW = Math.max(160, (pencil.width - 32) / Math.max(1, Math.min(5, names.length)));
const perRow = Math.max(1, Math.floor((pencil.width - 32) / colW));
const out = [
  { type: "rectangle", name: "Background", x: 0, y: 0, width: pencil.width, height: pencil.height, cornerRadius: 12, fill: "#FFFFFF", stroke: "#E4E7EC", strokeWidth: 1 },
  { type: "text", name: "Title", x: 16, y: 14, content: pencil.input.title, fontFamily: "Inter", fontSize: 14, fontWeight: "700", fill: "#101828" },
];
names.forEach((f, i) => {
  const x = 16 + (i % perRow) * colW, y = 44 + Math.floor(i / perRow) * 150;
  const c = families[f].color;
  out.push({ type: "rectangle", name: f + " swatch", x, y, width: 12, height: 12, cornerRadius: 3, fill: c });
  out.push({ type: "text", name: f + " name", x: x + 18, y: y - 2, content: f + "  " + c, fontFamily: "Inter", fontSize: 12, fontWeight: "700", fill: c });
  out.push({ type: "text", name: f + " types", x, y: y + 18, width: colW - 16, textGrowth: "fixed-width", content: families[f].types.join("\n"), fontFamily: "JetBrains Mono", fontSize: 10, lineHeight: 1.4, fill: "#475467" });
});
return out;
