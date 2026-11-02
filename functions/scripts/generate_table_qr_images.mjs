// 2026-10-28 — launch-table QR image generation.
//
// Reads `scripts/data/launch_table_qr_manifest.json` (written by
// `provision_launch_tables.mjs` — the real opaque tokens actually minted in
// Firestore) and renders one PNG + one labeled SVG per table into
// `assets/qr_codes/` at the repo root, encoding the real, secure
// `/table/:token` URL (see `docs/table_qr_architecture.md` §10 — identity
// is never derivable from the URL itself, only the opaque token is in it).
//
// The PNG is the bare QR code (no text baked in — adding a label to a raster
// image needs a canvas/image-composition dependency this script doesn't
// pull in). The SVG wraps the same QR in a labeled, print-ready card (table
// name as a text element) since SVG can nest another SVG's markup for free,
// with no extra dependency beyond `qrcode` itself (devDependency, this
// script only — never shipped in the deployed Cloud Functions bundle).
//
// Usage:
//   node scripts/generate_table_qr_images.mjs --base-url https://abakus-one-staging.web.app

import QRCode from "qrcode";
import { readFileSync, writeFileSync, mkdirSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const baseUrlArgIndex = process.argv.indexOf("--base-url");
const BASE_URL = baseUrlArgIndex !== -1 ? process.argv[baseUrlArgIndex + 1] : null;
if (!BASE_URL) {
  console.error(
    "[generate_table_qr_images] --base-url is required, e.g. " +
      "--base-url https://abakus-one-staging.web.app",
  );
  process.exit(1);
}

const __dirname = dirname(fileURLToPath(import.meta.url));
const MANIFEST_PATH = join(__dirname, "data", "launch_table_qr_manifest.json");
const OUTPUT_DIR = join(__dirname, "..", "..", "assets", "qr_codes");

function escapeXml(text) {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

async function main() {
  const manifest = JSON.parse(readFileSync(MANIFEST_PATH, "utf8"));
  mkdirSync(OUTPUT_DIR, { recursive: true });

  const qrSizePx = 400;
  const labelHeightPx = 72;

  for (const table of manifest.tables) {
    const url = `${BASE_URL.replace(/\/$/, "")}/table/${table.opaqueToken}`;

    // Bare PNG — no label.
    const pngPath = join(OUTPUT_DIR, `${table.tableId}.png`);
    await QRCode.toFile(pngPath, url, {
      type: "png",
      width: qrSizePx,
      margin: 2,
    });

    // Labeled SVG card — the raw QR's own SVG markup nested inside a taller
    // outer SVG that adds the table's display name as a text element above
    // it. `qrcode`'s own `toString(..., {type: 'svg'})` output is a
    // complete `<svg>...</svg>` document with its own viewBox/width/height
    // — nested verbatim via an inner `<svg>` sized to `qrSizePx`, which is
    // valid SVG (a nested `<svg>` establishes its own coordinate system).
    const qrSvgMarkup = await QRCode.toString(url, {
      type: "svg",
      width: qrSizePx,
      margin: 2,
    });
    const totalHeight = qrSizePx + labelHeightPx;
    const labeledSvg = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${qrSizePx}" height="${totalHeight}" viewBox="0 0 ${qrSizePx} ${totalHeight}">
  <rect x="0" y="0" width="${qrSizePx}" height="${totalHeight}" fill="#ffffff" />
  <text x="${qrSizePx / 2}" y="${labelHeightPx * 0.62}" text-anchor="middle" font-family="Arial, Helvetica, sans-serif" font-size="32" font-weight="700" fill="#1a1a1a">${escapeXml(table.displayName)}</text>
  <g transform="translate(0, ${labelHeightPx})">
    ${qrSvgMarkup.replace(/^<\?xml[^>]*\?>\s*/, "")}
  </g>
</svg>
`;
    const svgPath = join(OUTPUT_DIR, `${table.tableId}.svg`);
    writeFileSync(svgPath, labeledSvg);

    console.log(`[generate_table_qr_images] ${table.tableId} (${table.displayName}): wrote ${pngPath} + ${svgPath}`);
  }

  console.log(`[generate_table_qr_images] done — ${manifest.tables.length} tables, output dir: ${OUTPUT_DIR}`);
}

main().catch((error) => {
  console.error("[generate_table_qr_images] failed:", error);
  process.exitCode = 1;
});
