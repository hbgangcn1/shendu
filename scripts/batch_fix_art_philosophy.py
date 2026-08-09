"""批量给 auto-generated art asset meta.yaml 加 implements_philosophy"""
import os
import re
from pathlib import Path

ASSETS_ROOT = Path(r"C:\Users\hbgan\Projects\shendu\assets\images")
DEFAULT_PHILOSOPHY = ["rule_1_core_loop_first", "rule_10_narrative_play_unified"]

# Card asset 应该用 card_kind-specific rules
CARD_PHILOSOPHY_MAP = {
    # 元素分类哲学（asset_type=card 按 element）
    # 简化为统一默认值
}

fixed = 0
skipped = 0
errored = 0

for meta_file in ASSETS_ROOT.rglob("*.meta.yaml"):
    try:
        content = meta_file.read_text(encoding="utf-8")
        # 只修 auto-generated + 缺 implements_philosophy 的
        if "Backfill-PngMetaYaml" not in content:
            skipped += 1
            continue
        if "implements_philosophy:" in content and "implements_philosophy: []" not in content:
            # 已经有非空 philosophy，跳过
            skipped += 1
            continue

        # 替换 implements_philosophy: [] 为有内容的列表
        new_content = re.sub(
            r"implements_philosophy: \[\]",
            f'implements_philosophy: ["rule_1_core_loop_first", "rule_10_narrative_play_unified"]',
            content,
            count=1,
        )

        if new_content == content:
            # 没匹配到 implements_philosophy: []，需要添加
            # 在 minimax_attempts 之前插入
            if "implements_philosophy" not in content:
                new_content = content.replace(
                    "minimax_attempts:",
                    f'implements_philosophy: ["rule_1_core_loop_first", "rule_10_narrative_play_unified"]\nminimax_attempts:',
                    1,
                )
            else:
                errored += 1
                print(f"  WARN no-op: {meta_file}")
                continue

        meta_file.write_text(new_content, encoding="utf-8")
        fixed += 1
        print(f"  FIXED: {meta_file.relative_to(ASSETS_ROOT)}")
    except Exception as e:
        errored += 1
        print(f"  ERROR: {meta_file}: {e}")

print(f"\nSummary: fixed={fixed}, skipped={skipped}, errored={errored}")