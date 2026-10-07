"""Loop reporter: summarize one unattended iteration (Chinese markdown)."""
from __future__ import annotations
from datetime import date
from pathlib import Path


def render_summary(batch_report, scorecards, contracts, gate_verdict) -> str:
    """Render a short Chinese markdown summary."""
    batch_id = batch_report.get("batch_id", "unknown") if isinstance(batch_report, dict) else getattr(batch_report, "batch_id", "unknown")
    runs = batch_report.get("runs", []) if isinstance(batch_report, dict) else getattr(batch_report, "runs", [])
    lines = []
    lines.append(f"# 无人值守迭代报告 · {batch_id}")
    lines.append("")
    # 1. 批次信息
    lines.append("## 1. 批次信息")
    lines.append(f"- 批次 ID：`{batch_id}`")
    lines.append(f"- 运行数：{len(runs)}")
    lines.append("")
    # 2. 各轮退出码与决策统计
    lines.append("## 2. 各轮退出码与决策统计")
    if not runs:
        lines.append("- （无运行记录）")
    for r in runs:
        rid = r.get("run_id", "?")
        code = r.get("exit_code", "?")
        dec = r.get("decisions", {})
        if isinstance(dec, dict):
            ds = "、".join(f"{k}×{v}" for k, v in dec.items()) or "无"
        else:
            ds = str(dec)
        lines.append(f"- `{rid}`：退出码 {code}，决策：{ds}")
    # scorecards decision counts fallback
    if scorecards:
        lines.append(f"- 共 {len(scorecards)} 份评分卡")
    lines.append("")
    # 3. 关键 FAIL 与帧路径
    lines.append("## 3. 关键 FAIL（critical）与帧路径")
    crits = []
    for s in (scorecards or []):
        for c in (s.get("checks", []) if isinstance(s, dict) else []):
            if c.get("severity") == "critical" and c.get("result") == "FAIL":
                crits.append((s.get("run_id", "?"), c))
    if not crits:
        lines.append("- 无关键 FAIL 🎉")
    else:
        for rid, c in crits:
            frame = c.get("frame", "（无帧路径）")
            name = c.get("name", "unknown")
            lines.append(f"- ❌ `{rid}` / {name}：帧 `{frame}`")
    lines.append("")
    # 4. 已归档 Contracts
    lines.append("## 4. 已归档 Contracts")
    if not contracts:
        lines.append("- 本轮无新增 contract")
    else:
        for c in contracts:
            if isinstance(c, dict):
                lines.append(f"- `{c.get('id', '?')}`：{c.get('title', '')}")
            else:
                lines.append(f"- `{c}`")
    lines.append("")
    # 5. GO/NOGO 结论与原因
    lines.append("## 5. 门禁结论（GO / NOGO）与原因")
    if isinstance(gate_verdict, dict):
        v = gate_verdict.get("verdict", "NOGO")
        reasons = gate_verdict.get("reasons", [])
    else:
        v, reasons = str(gate_verdict), []
    icon = "✅ GO" if str(v).upper() == "GO" else "⛔ NOGO"
    lines.append(f"- 结论：**{icon}**")
    if reasons:
        for r in reasons:
            lines.append(f"  - {r}")
    else:
        lines.append("  - （无附加原因）")
    lines.append("")
    return "\n".join(lines)


def write_report(text: str, out_dir: str | Path) -> str:
    """Write loop-report-<date>.md under out_dir, return path."""
    d = Path(out_dir)
    d.mkdir(parents=True, exist_ok=True)
    p = d / f"loop-report-{date.today().isoformat()}.md"
    p.write_text(text, encoding="utf-8")
    return str(p)
