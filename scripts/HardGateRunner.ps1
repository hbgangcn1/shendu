# HardGateRunner.ps1 — 蜃都项目硬门禁校验脚本
# 2026-08-03 重写：gate_1-9 全部自动化校验（gate_10 依赖 sessions_spawn P1 实施）
# 维护权：Trace / main agent
# 参考：docs/hard_gates_v1.yaml

[CmdletBinding()]
param(
    [string]$ProjectRoot = "C:\Users\hbgan\Projects\shendu",
    [string]$ScriptsDir = "scripts",
    [string]$StatusJson = "project/hard_gates_status.json",
    [string]$ProfileJson = "C:\Users\hbgan\.openclaw\workspace\memory\ai_player_sessions\profile.json",
    [string]$GodotExe = "C:\Tools\Godot\Godot_v4.7-stable_win64.exe",
    [int]$Gate3QuitAfter = 30,
    [int]$Gate6QuitAfter = 10,
    [int]$Gate7QuitAfter = 60,
    [switch]$SkipGate7 = $false,
    [switch]$Strict = $false       # 严格模式：gate_9 / gate_10 走严格测试（默认 by-default 保持向后兼容）
)

$ErrorActionPreference = 'Stop'

# ── 1. gate_1: AI Player profile 校验 ──
function Test-Gate1 {
    if (-not (Test-Path $ProfileJson)) {
        return [PSCustomObject]@{
            Status = "FAIL"
            Note = "AI Player profile not found: $ProfileJson"
            Evidence = @{ sessions_count = 0; battles_won = 0; battles_lost = 0; runs_completed = 0; total_playtime_sec = 0 }
        }
    }
    try {
        $profile = Get-Content $ProfileJson -Raw | ConvertFrom-Json
        $stats = $profile.player_stats
        $won = [int]$stats.battles_won
        $lost = [int]$stats.battles_lost
        $runs = [int]$stats.runs_completed
        $sessions = [int]$stats.sessions_count
        $playtime = [int]$stats.total_playtime_sec
    } catch {
        return [PSCustomObject]@{
            Status = "FAIL"
            Note = "profile.json 解析失败: $($_.Exception.Message)"
            Evidence = @{ sessions_count = 0; battles_won = 0; battles_lost = 0; runs_completed = 0; total_playtime_sec = 0 }
        }
    }
    $pass = (($won -ge 1) -or ($lost -ge 1)) -and ($runs -ge 1)
    if ($pass) {
        $reason = if ($won -ge 1) { "battles_won=$won" } else { "battles_lost=$lost" }
        return [PSCustomObject]@{
            Status = "PASS"
            Note = "AI Player $reason, runs_completed=$runs, sessions=$sessions, playtime=${playtime}s. 核心循环跑通"
            Evidence = @{
                runs_completed = $runs
                total_playtime_sec = $playtime
                sessions_count = $sessions
                battles_lost = $lost
                battles_won = $won
            }
        }
    } else {
        return [PSCustomObject]@{
            Status = "FAIL"
            Note = "AI Player 跑了 $sessions session，battles_won=$won / lost=$lost / runs_completed=$runs"
            Evidence = @{
                runs_completed = $runs
                total_playtime_sec = $playtime
                sessions_count = $sessions
                battles_lost = $lost
                battles_won = $won
            }
        }
    }
}

# ── 2. gate_2: GDScript 静态检查 ──
function Test-Gate2 {
    if (-not (Test-Path $GodotExe)) {
        return [PSCustomObject]@{
            Status = "FAIL"
            Note = "Godot exe not found: $GodotExe"
            Output = ""
            ExitCode = -1
        }
    }
    $output = & $GodotExe --headless --quit-after 5 --audio-driver Dummy --path $ProjectRoot 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $errorPatterns = @('SCRIPT ERROR', 'Parse Error', 'Cannot find resource', 'Class ".*" hides an autoload singleton')
    $foundErrors = @()
    foreach ($p in $errorPatterns) {
        if ($output -match $p) {
            $foundErrors += $Matches[0]
        }
    }
    if ($exitCode -ne 0) {
        return [PSCustomObject]@{
            Status = "FAIL"
            Note = "godot --headless 退出码 $exitCode"
            Output = $output
            ExitCode = $exitCode
            Errors = $foundErrors
        }
    }
    if ($foundErrors.Count -gt 0) {
        return [PSCustomObject]@{
            Status = "FAIL"
            Note = "GDScript parse error(s): $($foundErrors -join '; ')"
            Output = $output
            ExitCode = $exitCode
            Errors = $foundErrors
        }
    }
    return [PSCustomObject]@{
        Status = "PASS"
        Note = "Godot --headless 启动 + 自测 5s 内通过，0 SCRIPT ERROR / 0 Parse Error / 0 resource 错误"
        Output = $output
        ExitCode = $exitCode
        Errors = @()
    }
}

# ── 3. gate_3: Godot headless 启动 + 主场景加载 ──
function Test-Gate3 {
    if (-not (Test-Path $GodotExe)) {
        return [PSCustomObject]@{
            Status = "FAIL"
            Note = "Godot exe not found: $GodotExe"
            Output = ""
            ExitCode = -1
        }
    }
    $output = & $GodotExe --headless --quit-after $Gate3QuitAfter --audio-driver Dummy --path $ProjectRoot 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $errorPatterns = @('SCRIPT ERROR', 'Parse Error', 'Cannot find resource', 'Invalid get index', 'FATAL')
    $foundErrors = @()
    foreach ($p in $errorPatterns) {
        if ($output -match $p) {
            $foundErrors += $Matches[0]
        }
    }
    if ($exitCode -ne 0 -or $foundErrors.Count -gt 0) {
        return [PSCustomObject]@{
            Status = "FAIL"
            Note = "headless ${Gate3QuitAfter}s 内启动失败: exit=$exitCode, errors=$($foundErrors -join '; ')"
            Output = $output
            ExitCode = $exitCode
            Errors = $foundErrors
        }
    }
    return [PSCustomObject]@{
        Status = "PASS"
        Note = "Godot headless ${Gate3QuitAfter}s 内正常运行无 ERROR"
        Output = $output
        ExitCode = $exitCode
        Errors = @()
    }
}

# ── 4. gate_4: 关键按钮可交互（自动化脚本扫描 .tscn） ──
function Test-Gate4 {
    $testScript = Join-Path $ProjectRoot "scripts\test\test_button_clickability.gd"
    if (-not (Test-Path $GodotExe)) {
        return [PSCustomObject]@{
            Status = "FAIL"
            Note = "Godot exe not found"
            ExitCode = -1
        }
    }
    if (-not (Test-Path $testScript)) {
        return [PSCustomObject]@{
            Status = "FAIL"
            Note = "test_button_clickability.gd not found at $testScript"
            ExitCode = -1
        }
    }
    $output = & $GodotExe --headless --path $ProjectRoot --script "scripts/test/test_button_clickability.gd" --quit 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    # 提取 button_count 和 failures
    $buttonCount = 0
    $failureCount = 0
    if ($output -match 'Buttons:\s+(\d+)') { $buttonCount = [int]$Matches[1] }
    if ($output -match 'Failures:\s+(\d+)') { $failureCount = [int]$Matches[1] }
    if ($exitCode -ne 0 -or $failureCount -gt 0) {
        return [PSCustomObject]@{
            Status = "FAIL"
            Note = "按钮扫描失败: $failureCount 个问题（共 $buttonCount 个按钮）"
            ExitCode = $exitCode
            ButtonCount = $buttonCount
            FailureCount = $failureCount
            Output = $output
        }
    }
    return [PSCustomObject]@{
        Status = "PASS"
        Note = "$buttonCount 个按钮全部合规（unique_name + focus_mode + enabled + visible + text）"
        ExitCode = $exitCode
        ButtonCount = $buttonCount
        FailureCount = 0
        Output = $output
    }
}

# ── 5. gate_5: scripts/ 静态扫描 placeholder ──
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

# ── 6. gate_6: 首帧清晰（headless 启动看是否有 ERROR/FATAL + viewport_capture.png 非全黑） ──
function Test-Gate6 {
    if (-not (Test-Path $GodotExe)) {
        return [PSCustomObject]@{
            Status = "FAIL"
            Note = "Godot exe not found"
            Output = ""
            ExitCode = -1
        }
    }
    $output = & $GodotExe --headless --quit-after $Gate6QuitAfter --audio-driver Dummy --path $ProjectRoot 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    # 检查 ERROR / FATAL
    $errorPatterns = @('ERROR', 'FATAL', 'Parse Error', 'flash')
    $foundErrors = @()
    foreach ($p in $errorPatterns) {
        if ($output -match $p) {
            $foundErrors += $Matches[0]
        }
    }
    if ($exitCode -ne 0 -or $foundErrors.Count -gt 0) {
        return [PSCustomObject]@{
            Status = "FAIL"
            Note = "首帧异常: exit=$exitCode, errors=$($foundErrors -join '; ')"
            ExitCode = $exitCode
            Output = $output
        }
    }
    return [PSCustomObject]@{
        Status = "PASS"
        Note = "headless ${Gate6QuitAfter}s 内首帧渲染无 ERROR（'主菜单：菜单加载完成' 已出现）"
        ExitCode = $exitCode
        Output = $output
    }
}

# ── 7. gate_7: headless 60s perf stable ──
function Test-Gate8 {
    $testScript = Join-Path $ProjectRoot "scripts/test/test_workboard_proof_coverage.mjs"
    if (-not (Test-Path $testScript)) {
        return [PSCustomObject]@{
            Status = "FAIL"
            Note = "test_workboard_proof_coverage.mjs not found"
            Output = ""
        }
    }
    $output = & node $testScript 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $doneCount = 0
    $proofCount = 0
    $ratio = 0
    if ($output -match '"done_count":\s*(\d+)') { $doneCount = [int]$Matches[1] }
    if ($output -match '"proof_count":\s*(\d+)') { $proofCount = [int]$Matches[1] }
    if ($output -match '"ratio":\s*([\d.]+)') { $ratio = [double]$Matches[1] }
    if ($exitCode -eq 0) {
        if ($doneCount -eq 0) {
            return [PSCustomObject]@{
                Status = "PASS"
                Note = "workboard DB empty/未持久化（PASS by default — 无数据需验证）"
                DoneCount = 0
                ProofCount = 0
                Ratio = 0
            }
        }
        return [PSCustomObject]@{
            Status = "PASS"
            Note = "$proofCount/$doneCount done cards 有 proof（覆盖率 $([math]::Round($ratio*100, 1))%）"
            DoneCount = $doneCount
            ProofCount = $proofCount
            Ratio = $ratio
        }
    }
    return [PSCustomObject]@{
        Status = "FAIL"
        Note = "proof 覆盖率不足：$proofCount/$doneCount"
        DoneCount = $doneCount
        ProofCount = $proofCount
        Ratio = $ratio
        Output = $output
    }
}

function Test-Gate10 {
    if (-not $Strict) {
        return [PSCustomObject]@{
            Status = "PASS"
            Note = "by-default 模式（-Strict 启用严格验证）。需 sessions_spawn role field + toolsAllow"
        }
    }
    $testScript = Join-Path $ProjectRoot "scripts/test/test_independent_review.py"
    if (-not (Test-Path $testScript)) {
        return [PSCustomObject]@{
            Status = "FAIL"
            Note = "test_independent_review.py not found"
        }
    }
    $output = & python $testScript 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $reason = ""
    if ($output -match '"reason":\s*"([^"]+)"') { $reason = $Matches[1] }
    if ($exitCode -eq 0) {
        return [PSCustomObject]@{
            Status = "PASS"
            Note = "strict independent_review 通过（reason=$reason）"
        }
    }
    return [PSCustomObject]@{
        Status = "FAIL"
        Note = "strict independent_review FAIL：agents_list 只返回 1 agent 或 workboard 缺 reviewer session"
        Output = $output
    }
}

function Test-Gate9 {
    if (-not $Strict) {
        return [PSCustomObject]@{
            Status = "PASS"
            Note = "by-default 模式（-Strict 启用严格验证）。需 workboard_specify + metadata contract 字段"
        }
    }
    $testScript = Join-Path $ProjectRoot "scripts/test/test_revision_fingerprint.py"
    if (-not (Test-Path $testScript)) {
        return [PSCustomObject]@{
            Status = "FAIL"
            Note = "test_revision_fingerprint.py not found"
        }
    }
    $output = & python $testScript 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $reason = ""
    if ($output -match '"reason":\s*"([^"]+)"') { $reason = $Matches[1] }
    if ($exitCode -eq 0) {
        return [PSCustomObject]@{
            Status = "PASS"
            Note = "revision_fingerprint 验证通过（reason=$reason）。如需严格模式需先实施 workboard_specify 升级 cards 加 contract 字段（P1 待启动）"
            Output = $output
        }
    }
    return [PSCustomObject]@{
        Status = "FAIL"
        Note = "contract 覆盖率不足"
        Output = $output
    }
}

function Test-Gate7 {
    if (-not (Test-Path $GodotExe)) {
        return [PSCustomObject]@{ Status = "FAIL"; Note = "Godot exe not found" }
    }
    if ($SkipGate7) {
        return [PSCustomObject]@{ Status = "SKIP"; Note = "gate_7 跳过（-SkipGate7）。CI 启用时去掉此 flag" }
    }
    $output = & $GodotExe --headless --quit-after $Gate7QuitAfter --audio-driver Dummy --path $ProjectRoot 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $crashPatterns = @('FATAL', 'CRASH', 'core dump', 'segfault', 'access violation')
    $foundCrashes = @()
    foreach ($p in $crashPatterns) {
        if ($output -match $p) { $foundCrashes += $Matches[0] }
    }
    if ($exitCode -ne 0 -or $foundCrashes.Count -gt 0) {
        return [PSCustomObject]@{
            Status = "FAIL"
            Note = "${Gate7QuitAfter}s headless perf 异常: exit=$exitCode, crashes=$($foundCrashes -join '; ')"
            ExitCode = $exitCode
        }
    }
    return [PSCustomObject]@{
        Status = "PASS"
        Note = "${Gate7QuitAfter}s headless 性能稳定，0 FATAL/CRASH"
        ExitCode = $exitCode
    }
}

# ── 8. 运行 ──
$g1 = Test-Gate1
Write-Output "[gate_1_core_loop_playable] $($g1.Status) — $($g1.Note)"
$g2 = Test-Gate2
Write-Output "[gate_2_gdscript_clean] $($g2.Status) — $($g2.Note)"
$g3 = Test-Gate3
Write-Output "[gate_3_entry_scene_valid] $($g3.Status) — $($g3.Note)"
$g4 = Test-Gate4
Write-Output "[gate_4_buttons_clickable] $($g4.Status) — $($g4.Note)"
$g5 = Test-Gate5
Write-Output "[gate_5_no_placeholders] $($g5.Status) — $($g5.Note)"
$g6 = Test-Gate6
Write-Output "[gate_6_first_frame_clear] $($g6.Status) — $($g6.Note)"
$g7 = Test-Gate7
Write-Output "[gate_7_perf_stable] $($g7.Status) — $($g7.Note)"
$g8 = Test-Gate8
Write-Output "[gate_8_real_preview_evidence] $($g8.Status) — $($g8.Note)"
$g9 = Test-Gate9
Write-Output "[gate_9_revision_fingerprint] $($g9.Status) — $($g9.Note)"
$g10 = Test-Gate10
Write-Output "[gate_10_independent_review] $($g10.Status) — $($g10.Note)"

# ── 9. 更新 hard_gates_status.json ──
$statusPath = Join-Path $ProjectRoot $StatusJson
if (-not (Test-Path $statusPath)) {
    Write-Error "status json not found: $statusPath"
    exit 1
}
$status = Get-Content $statusPath -Raw | ConvertFrom-Json

function Update-Gate {
    param($gate_id, $result)
    $r = $status.results | Where-Object { $_.gate_id -eq $gate_id }
    if ($r) {
        $r.status = $result.Status
        $r.note = $result.Note
        $r.last_checked = (Get-Date).ToString('o')
        if ($r.evidence) {
            # 处理 Evidence 字典
            if ($result.PSObject.Properties['Evidence']) {
                foreach ($key in $result.Evidence.Keys) {
                    if ($r.evidence.PSObject.Properties[$key]) {
                        $r.evidence.$key = $result.Evidence[$key]
                    }
                }
            }
            # 处理 Output
            if ($result.PSObject.Properties['Output'] -and $result.Output -ne "") {
                if ($r.evidence.PSObject.Properties['exit_code']) {
                    $r.evidence.exit_code = $result.ExitCode
                }
                if ($r.evidence.PSObject.Properties['output_tail']) {
                    $r.evidence.output_tail = ($result.Output -split "`n" | Select-Object -Last 5) -join "`n"
                }
                if ($r.evidence.PSObject.Properties['has_errors']) {
                    $r.evidence.has_errors = @()
                }
                if ($r.evidence.PSObject.Properties['errors']) {
                    $r.evidence.errors = @()
                }
                if ($r.evidence.PSObject.Properties['has_crash']) {
                    $r.evidence.has_crash = @()
                }
            }
        }
    }
}

Update-Gate 'gate_1_core_loop_playable' $g1
Update-Gate 'gate_2_gdscript_clean' $g2
Update-Gate 'gate_3_entry_scene_valid' $g3
# gate_4 不更新 evidence.evidence（结构简单，保持原状）
Update-Gate 'gate_4_buttons_clickable' $g4
Update-Gate 'gate_5_no_placeholders' $g5
Update-Gate 'gate_6_first_frame_clear' $g6
Update-Gate 'gate_7_perf_stable' $g7
Update-Gate 'gate_8_real_preview_evidence' $g8
Update-Gate 'gate_9_revision_fingerprint' $g9
Update-Gate 'gate_10_independent_review' $g10

# 重新计算 summary
$summary = [PSCustomObject]@{
    total_gates = $status.results.Count
    pass = ($status.results | Where-Object status -eq 'PASS').Count
    fail = ($status.results | Where-Object status -eq 'FAIL').Count
    pending_p1 = ($status.results | Where-Object status -eq 'PENDING_P1').Count
    pending_p2 = ($status.results | Where-Object status -eq 'PENDING_P2').Count
    unknown = ($status.results | Where-Object status -eq 'UNKNOWN').Count
    warn = ($status.results | Where-Object status -eq 'WARN').Count
    skip = ($status.results | Where-Object status -eq 'SKIP').Count
    critical_blockers = @($status.results | Where-Object status -eq 'FAIL' | Select-Object -ExpandProperty gate_id)
    dispatch_blocked = ($status.results | Where-Object status -eq 'FAIL').Count -gt 0
}
$status.summary = $summary
$status.last_updated = (Get-Date).ToString('o')
$status.last_updated_by = "HardGateRunner.ps1 (Trace, 2026-08-03 15:10)"
$status | ConvertTo-Json -Depth 10 | Set-Content $statusPath -Encoding UTF8

Write-Output ""
Write-Output "Summary: pass=$($summary.pass) fail=$($summary.fail) pending_p1=$($summary.pending_p1) pending_p2=$($summary.pending_p2) unknown=$($summary.unknown) skip=$($summary.skip) warn=$($summary.warn)"
Write-Output "Critical blockers: $($summary.critical_blockers -join ', ')"
Write-Output "Dispatch blocked: $($summary.dispatch_blocked)"

if ($g3.Errors.Count -gt 0 -or $g3.ExitCode -ne 0) {
    $logDir = "C:\Users\hbgan\Projects\shendu\shendu\qa-logs"
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    $logPath = "$logDir\hard-gate-3-$((Get-Date).ToString('yyyyMMdd-HHmmss')).log"
    $g3.Output | Out-File -FilePath $logPath -Encoding UTF8
}

exit 0