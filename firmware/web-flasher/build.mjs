import fs from "node:fs";
import path from "node:path";

const RELEASE_BASE =
  process.env.FW_RELEASE_BASE ||
  "https://github.com/Hthancder/ArenaAIWorkspace-1/releases/download/dualboot-latest";

const FILES = [
  "bootloader_dualboot.bin",
  "dualboot_menu.bin",
  "partition-table-default.bin",
  "DSolution-183-2mic-ota.bin",
  "DSolution-183-2mic-factory.bin",
];

const outDir = path.resolve("fw");
fs.mkdirSync(outDir, { recursive: true });

const manifest = {
  generatedAt: new Date().toISOString(),
  source: RELEASE_BASE,
  files: {},
};

for (const name of FILES) {
  const url = `${RELEASE_BASE}/${name}`;
  console.log(`[build] Fetching ${url}`);
  const res = await fetch(url, { redirect: "follow" });
  if (!res.ok) {
    throw new Error(`Failed to fetch ${name}: HTTP ${res.status} ${res.statusText}`);
  }
  const buf = Buffer.from(await res.arrayBuffer());
  if (buf.length < 512) {
    throw new Error(`Downloaded ${name} looks truncated (${buf.length} bytes)`);
  }
  const dest = path.join(outDir, name);
  fs.writeFileSync(dest, buf);
  manifest.files[name] = {
    size: buf.length,
    url: `/fw/${name}`,
  };
  console.log(`[build] Saved ${name} (${buf.length.toLocaleString("en-US")} bytes)`);
}

fs.writeFileSync(path.join(outDir, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");
console.log("[build] fw/manifest.json ready.");
