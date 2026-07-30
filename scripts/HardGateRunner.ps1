# HardGateRunner.ps1 — 蜃都项目硬门禁校验脚本
# 2026-07-31 重建 — 原文件丢失（git 历史也没有，7/30 18:41 minimax 写的 last_updated_by 字段是幻觉）
# 维护权：Trace / main agent
# 参考：docs/hard_gates_v1.yaml

[CmdletBinding()]
param(
    [string]$ProjectRoot = "C:\Users\hbgan\Projects\shendu",
    [string]$ScriptsDir = "scripts",
    [string]$StatusJson = "project/hard_gates_status.json"
)

$ErrorActionPreference = 'Stop'

# ── 1. 静态扫描 placeholder 关键字（gate_5） ──
function Test-Gate5 {
    $root = Join-Path $ProjectRoot $ScriptsDir
    if (-not (Test-Path $root)) {
        return [PSCustomObject]@{ Status = "FAIL"; Note = "scripts/ not found: $root"; Hits = 0 }
    }
    $files = Get-ChildItem $root -Recurse -Filter '*.gd' -ErrorAction SilentlyContinue
    $hits = @()
    foreach ($f in $files) {
        $lines = Get-Content $f.FullName -ErrorAction SilentlyContinue
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            $trimmed = $line.TrimStart()
            if ($trimmed.StartsWith('#')) { continue }
            if ($line -match '(?i)\b(placeholder|TBD|TODO|FIXME|XXX)\b') {
                $hits += [PSCustomObject]@{ File = $f.FullName; Line = $i + 1; Text = $line }
            }
        }
    }
    if ($hits.Count -eq 0) {
        return [PSCustomObject]@{
            Status = "PASS"
            Note = "0 non-comment placeholder hits across $($files.Count) .gd files"
            Hits = 0
        }
    } else {
        return [PSCustomObject]@{
            Status = "FAIL"
            Note = "$($hits.Count) non-comment placeholder hits"
            Hits = $hits.Count
        }
    }
}

# ── 2. 运行 ──
$g5 = Test-Gate5
Write-Output "[gate_5_no_placeholders] $($g5.Status) — $($g5.Note)"

# ── 3. 更新 hard_gates_status.json ──
$statusPath = Join-Path $ProjectRoot $StatusJson
if (-not (Test-Path $statusPath)) {
    Write-Error "status json not found: $statusPath"
    exit 1
}
$status = Get-Content $statusPath -Raw | ConvertFrom-Json
$g5Result = $status.results | Where-Object { $_.gate_id -eq 'gate_5_no_placeholders' }
if ($g5Result) {
    $g5Result.status = $g5.Status
    $g5Result.note = $g5.Note
    $g5Result.last_checked = (Get-Date).ToString('o')
    if ($g5Result.evidence) {
        $g5Result.evidence.placeholder_hits = $g5.Hits
    }
}
$status.last_updated = (Get-Date).ToString('o')
$status.last_updated_by = "HardGateRunner.ps1 (Trace, 2026-07-31 05:08)"

# 重新计算 summary
$summary = [PSCustomObject]@{
    total_gates = $status.results.Count
    pass = ($status.results | Where-Object status -eq 'PASS').Count
    fail = ($status.results | Where-Object status -eq 'FAIL').Count
    pending_p1 = ($status.results | Where-Object status -eq 'PENDING_P1').Count
    pending_p2 = ($status.results | Where-Object status -eq 'PENDING_P2').Count
    unknown = ($status.results | Where-Object status -eq 'UNKNOWN').Count
    warn = ($status.results | Where-Object status -eq 'WARN').Count
    critical_blockers = @($status.results | Where-Object status -eq 'FAIL' | Select-Object -ExpandProperty gate_id)
    dispatch_blocked = ($status.results | Where-Object status -eq 'FAIL').Count -gt 0
}
$status.summary = $summary

$status | ConvertTo-Json -Depth 10 | Set-Content $statusPath -Encoding UTF8

Write-Output ""
Write-Output "Summary: pass=$($summary.pass) fail=$($summary.fail) pending_p1=$($summary.pending_p1) pending_p2=$($summary.pending_p2) unknown=$($summary.unknown) warn=$($summary.warn)"
Write-Output "Critical blockers: $($summary.critical_blockers -join ', ')"
Write-Output "Dispatch blocked: $($summary.dispatch_blocked)"
exit 0
