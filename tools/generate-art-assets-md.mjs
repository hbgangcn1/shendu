#!/usr/bin/env node
// 从 assets/images/cards/*.meta.yaml 生成 design/ART_ASSETS.md

import { readFile, writeFile, readdir } from "node:fs/promises";
import { join, basename } from "node:path";

const CARDS_DIR = "C:\\Users\\hbgan\\Projects\\shendu\\assets\\images\\cards";
const OUT_PATH = "C:\\Users\\hbgan\\Projects\\shendu\\design\\ART_ASSETS.md";

async function loadMeta(baseName) {
  const path = join(CARDS_DIR, `${baseName}.meta.yaml`);
  const raw = await readFile(path, "utf8");
  const obj = {};
  for (const line of raw.split(/\r?\n/)) {
    const m = line.match(/^([a-zA-Z0-9_]+):\s*(.*)$/);
    if (m) obj[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
  return obj;
}

async function main() {
  const files = await readdir(CARDS_DIR);
  const pngs = files.filter(f => f.endsWith(".png")).sort();

  const rows = [];
  for (const png of pngs) {
    const base = basename(png, ".png");
    try {
      const m = await loadMeta(base);
      rows.push({
        file: png,
        display_name: m.display_name || base,
        element: m.element || "",
        target_size: m.target_size || "",
        version: m.version || "v001",
        status: m.review_status || "pass",
        score: m.review_score || "",
        model: m.current_model || m.model || "",
        notes: `minimax=${m.minimax_attempts || 0}, qwen=${m.qwen_attempts || 0}`,
      });
    } catch (e) {
      rows.push({
        file: png,
        display_name: base,
        element: "",
        target_size: "",
        version: "",
        status: "missing_meta",
        score: "",
        model: "",
        notes: "",
      });
    }
  }

  const lines = [
    "# 蜃都美术资源清单",
    "",
    "本文件记录项目中已通过审核的正式美术资源。旧版本已归档到 assets/images/_archive/。",
    "",
    `最后更新：${new Date().toISOString().split("T")[0]}`,
    "",
    "## 世界锚点图 (anchors)",
    "",
    "| 文件名 | 显示名称 | 元素 | 目标尺寸 | 版本 | 审核状态 | 审核分数 | 审核模型 | 备注 |",
    "|---|---|---|---|---|---|---|---|---|",
    "| world_anchor.png | 蜃都世界观锚点 | null | 1920x1080 | v001 | pass | 89.05 |  |  |",
    "",
    "## 五行卡牌背景 (card_bgs)",
    "",
    "| 文件名 | 显示名称 | 元素 | 目标尺寸 | 版本 | 审核状态 | 审核分数 | 审核模型 | 备注 |",
    "|---|---|---|---|---|---|---|---|---|",
    "| element_earth.png | 土元素卡牌背景 | earth | 1024x1024 | v003 | pass | 80 |  | Forbidden issues resolved |",
    "| element_fire.png | 火元素卡牌背景 | fire | 1024x1024 | v004 | pass | 95 |  |  |",
    "| element_metal.png | 金元素卡牌背景 | metal | 1024x1024 | v003 | pass | 90 |  |  |",
    "| element_water.png | 水元素卡牌背景 | water | 1024x1024 | v003 | pass | 92 |  |  |",
    "| element_wood.png | 木元素卡牌背景 | wood | 1024x1024 | v004 | pass | 91.75 |  |  |",
    "",
    "## 卡牌立绘 (cards)",
    "",
    "| 文件名 | 显示名称 | 元素 | 目标尺寸 | 版本 | 审核状态 | 审核分数 | 审核模型 | 备注 |",
    "|---|---|---|---|---|---|---|---|---|",
  ];

  for (const r of rows) {
    lines.push(`| ${r.file} | ${r.display_name} | ${r.element} | ${r.target_size} | ${r.version} | ${r.status} | ${r.score} | ${r.model} | ${r.notes} |`);
  }

  lines.push(
    "",
    "## 敌人 (enemies)",
    "",
    "| 文件名 | 显示名称 | 元素 | 目标尺寸 | 版本 | 审核状态 | 审核分数 | 审核模型 | 备注 |",
    "|---|---|---|---|---|---|---|---|---|",
    "| enemy_metal_iron_golem_001.png | 铁甲傀儡 | metal | 1024x1024 | v003 | pass | 92 |  |  |",
    "",
    "## UI 图标 (ui)",
    "",
    "| 文件名 | 显示名称 | 元素 | 目标尺寸 | 版本 | 审核状态 | 审核分数 | 审核模型 | 备注 |",
    "|---|---|---|---|---|---|---|---|---|",
    "| icon_earth.png | 土元素图标 | earth | 512x512 | v001 | pass | 89.45 |  |  |",
    "| icon_fire.png | 火元素图标 | fire | 512x512 | v003 | pass | 79.75 |  |  |",
    "| icon_metal.png | 金元素图标 | metal | 512x512 | v003 | pass | 81.9 |  |  |",
    "| icon_water.png | 水元素图标 | water | 512x512 | v001 | pass | 83.5 |  |  |",
    "| icon_wood.png | 木元素图标 | wood | 512x512 | v002 | pass | 82.35 |  |  |",
    "",
    "---",
    "",
    "## 归档记录",
    "",
    "旧版本文件存放在 assets/images/_archive/ 下，按资产类型分子目录。",
    "",
    "| 原文件名 | 归档路径 |",
    "|---|---|",
    "| element_earth_v002.png | _archive/card_bgs/element_earth_v002.png |",
    ""
  );

  await writeFile(OUT_PATH, lines.join("\n"), "utf8");
  console.log(`Wrote ${OUT_PATH} with ${rows.length} card rows`);
}

main().catch(e => { console.error(e); process.exit(1); });
