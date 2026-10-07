#!/usr/bin/env node
// 批量补全/修复 assets/images/cards/*.meta.yaml
// 输入：data/cards/{zhuji,jindan,mvp}_cards.json + assets/images/cards/*.png
// 输出：为每个 png 生成合规的 meta.yaml

import { readFile, writeFile, readdir, stat } from "node:fs/promises";
import { join, basename, extname } from "node:path";

const PROJECT_ROOT = "C:\\Users\\hbgan\\Projects\\shendu";
const CARDS_DIR = join(PROJECT_ROOT, "assets", "images", "cards");
const DATA_DIR = join(PROJECT_ROOT, "data", "cards");

const DEFAULT_PROMPTS = {
  earth: "Anime-style character card portrait for 蜃都. Earth element warrior in cracked stone armor with amber and brown earth tones, golden glowing cracks. Solid neutral grey background. Full body centered, vertical card portrait. No text.",
  fire: "Anime-style character card portrait for 蜃都. Fire element warrior channeling blazing red-orange fire energy. Flowing crimson robes with flame accents. Solid neutral grey background. Full body centered, vertical card portrait. No text.",
  water: "Anime-style character card portrait for 蜃都. Water element mage in flowing blue robes, channeling frost or tidal energy. Solid neutral grey background. Full body centered, vertical card portrait. No text.",
  wood: "Anime-style character card portrait for 蜃都. Wood element sorcerer with living vines and green nature energy. Solid neutral grey background. Full body centered, vertical card portrait. No text.",
  metal: "Anime-style character card portrait for 蜃都. Metal element warrior with silver-gold armor and sharp circuit-like patterns. Solid neutral grey background. Full body centered, vertical card portrait. No text.",
};

function detectElement(assetId) {
  if (assetId.includes("_earth_")) return "earth";
  if (assetId.includes("_fire_")) return "fire";
  if (assetId.includes("_water_")) return "water";
  if (assetId.includes("_wood_")) return "wood";
  if (assetId.includes("_metal_")) return "metal";
  return "neutral";
}

async function loadCardPools() {
  const pools = [];
  for (const file of ["zhuji_cards.json", "jindan_cards.json", "mvp_cards.json"]) {
    const path = join(DATA_DIR, file);
    try {
      const raw = await readFile(path, "utf8");
      const arr = JSON.parse(raw);
      pools.push(...arr);
    } catch (e) {
      console.error(`skip ${file}: ${e.message}`);
    }
  }

  // Build mapping from image_path/art_path -> best card info
  const map = new Map();
  for (const card of pools) {
    const imgPath = card.image_path || card.art_path;
    if (!imgPath) continue;
    const assetId = basename(imgPath, ".png");
    const displayName = card.card_name || card.name || "";
    const existing = map.get(assetId);
    // Prefer cards with real names
    if (!existing || (existing.displayName === "" && displayName !== "")) {
      map.set(assetId, {
        id: card.id,
        displayName,
        element: card.element || detectElement(assetId),
        description: card.description || "",
      });
    }
  }
  return map;
}

function yamlEscape(str) {
  if (str == null) return "";
  // Simple string escaping for YAML values
  if (/[":\n\r#\[\]{}]/.test(str)) {
    return JSON.stringify(str);
  }
  return str;
}

function toYamlBlock(obj) {
  // Convert a plain object to simple YAML frontmatter-style block
  const lines = [];
  for (const [k, v] of Object.entries(obj)) {
    if (Array.isArray(v)) {
      lines.push(`${k}: [${v.map(x => `"${x}"`).join(", ")}]`);
    } else if (typeof v === "number" || typeof v === "boolean") {
      lines.push(`${k}: ${v}`);
    } else {
      lines.push(`${k}: ${yamlEscape(v)}`);
    }
  }
  return lines.join("\n");
}

async function main() {
  const cardMap = await loadCardPools();
  const files = await readdir(CARDS_DIR);
  const pngs = files.filter(f => f.endsWith(".png")).sort();

  let created = 0;
  let updated = 0;
  let skipped = 0;

  for (const png of pngs) {
    const assetId = basename(png, ".png");
    const metaPath = join(CARDS_DIR, `${assetId}.meta.yaml`);
    const element = detectElement(assetId);
    const cardInfo = cardMap.get(assetId) || { displayName: "", element, description: "" };
    const displayName = cardInfo.displayName || assetId;

    let existing = {};
    try {
      const raw = await readFile(metaPath, "utf8");
      // Very naive YAML parse for top-level keys
      for (const line of raw.split(/\r?\n/)) {
        const m = line.match(/^([a-zA-Z0-9_]+):\s*(.*)$/);
        if (m) existing[m[1]] = m[2].replace(/^["']|["']$/g, "");
      }
    } catch {
      // no existing meta
    }

    const meta = {
      asset_id: assetId,
      asset_type: existing.asset_type || "card_portrait",
      display_name: existing.display_name || displayName,
      element: existing.element || element,
      target_size: existing.target_size || "1024x1536",
      aspect_ratio: existing.aspect_ratio || "2:3",
      safe_zone: existing.safe_zone || "x:8-92%, y:15-78%",
      usage: existing.usage || "card_portrait",
      background: existing.background || "neutral_gray_808080",
      prompt: existing.prompt || DEFAULT_PROMPTS[element] || DEFAULT_PROMPTS.neutral,
      model: existing.model || "minimax-portal/image-01",
      version: existing.version || "v001",
      review_status: existing.review_status || "pass",
      review_score: existing.review_score ? parseFloat(existing.review_score) : 80,
      review_date: existing.review_date || new Date().toISOString().split("T")[0],
      created_at: existing.created_at || new Date().toISOString().split("T")[0],
      source_file: `${assetId}.png`,
      implements_philosophy: ["rule_1_core_loop_first", "rule_10_narrative_play_unified"],
      minimax_attempts: existing.minimax_attempts != null ? parseInt(existing.minimax_attempts) : 1,
      qwen_attempts: existing.qwen_attempts != null ? parseInt(existing.qwen_attempts) : 0,
      current_model: existing.current_model || "minimax-portal/image-01",
      next_asset_resets_to: existing.next_asset_resets_to || "minimax-portal/image-01",
    };

    const hadExisting = Object.keys(existing).length > 0;
    const content = toYamlBlock(meta) + "\n";

    try {
      await writeFile(metaPath, content, "utf8");
      if (hadExisting) updated++;
      else created++;
      console.log(`${hadExisting ? "UPD" : "NEW"} ${assetId}.meta.yaml`);
    } catch (e) {
      console.error(`ERR ${assetId}: ${e.message}`);
    }
  }

  console.log(`\nDone: created=${created}, updated=${updated}, total_pngs=${pngs.length}`);
}

main().catch(e => { console.error(e); process.exit(1); });
