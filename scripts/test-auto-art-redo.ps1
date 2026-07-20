#!/usr/bin/env pwsh
# test-auto-art-redo.ps1 — Unit tests for skills/shendu-art/references/auto_art_redo.mjs
#
# 用例：
#   1. dry-run 不写文件
#   2. score < 85 → 写 attempt_NNN+1/ + REDO_REQUEST.json + 删 pending_review.json
#   3. score ≥ 85 → skip（这种情况理论上不该出现，B7 已 auto-approve）
#   4. minimax 5 次失败 → 切 qwen
#   5. qwen 10 次仍 < 75 → 触发 HUMAN_INTERVENTION_REQUIRED.txt
#   6. 找不到 art spec → 不 crash，fallback 到 concept.yaml
#
# 用法：pwsh -File scripts/test-auto-art-redo.ps1
[CmdletBinding()]
param(
    [string]$RepoRoot = "C:\Users\hbgan\Projects\shendu",
    [string]$ScriptPath = "C:\Users\hbgan\.openclaw\workspace\skills\shendu-art\references\auto_art_redo.mjs"
)

$ErrorActionPreference = 'Stop'

# 临时 fixture 目录（不能用 _ 前缀，auto_art_redo.mjs 会跳过）
$FixturesRoot = Join-Path $RepoRoot "review_temp\test_fixtures_art_redo"
if (Test-Path $FixturesRoot) { Remove-Item -Recurse -Force $FixturesRoot }
New-Item -ItemType Directory -Path $FixturesRoot | Out-Null

function Assert-Equal {
    param([string]$Name, [object]$Expected, [object]$Actual)
    if ($Expected -eq $Actual) {
        Write-Host "  ✓ $Name" -ForegroundColor Green
    } else {
        Write-Host "  ✗ $Name : expected '$Expected' got '$Actual'" -ForegroundColor Red
        $script:failures++
    }
}

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if ($Condition) {
        Write-Host "  ✓ $Name" -ForegroundColor Green
    } else {
        Write-Host "  ✗ $Name" -ForegroundColor Red
        $script:failures++
    }
}

function New-FixtureAsset {
    param(
        [string]$AssetId,
        [int]$AttemptNum,
        [int]$Score,
        [hashtable]$ConceptOverrides = @{},
        [string]$Model = "minimax-portal/image-01",
        [hashtable]$MetaOverrides = @{},
        [string]$ReviewDecision = "REDO"
    )
    $assetDir = Join-Path $FixturesRoot $AssetId
    # 确保每个 asset 在 fixtures 根下独立清理
    $attempt = "attempt_{0:D3}" -f $AttemptNum
    $attemptDir = Join-Path $assetDir $attempt
    New-Item -ItemType Directory -Path $attemptDir -Force | Out-Null

    $concept = @{
        asset_id = $AssetId
        asset_type = "card"
        element = "fire"
        theme = "blazing-swordsman"
        display_name = "烈焰剑客"
        target_size = "1024x1536"
        aspect_ratio = "2:3"
        usage = "战斗主卡"
        description = "A blazing swordsman wreathed in fire."
        style_anchors = @("sumi-e", "ink_wash_with_neon_accents", "selective_neon_rim_light")
        model = $Model
    }
    foreach ($k in $ConceptOverrides.Keys) { $concept[$k] = $ConceptOverrides[$k] }
    $conceptYaml = ($concept.GetEnumerator() | ForEach-Object {
            $v = $_.Value
            if ($v -is [array]) {
                $items = ($v | ForEach-Object { '"' + $_ + '"' }) -join ', '
                "$($_.Key): [$items]"
            } elseif ($v -is [string] -and $v.Contains("`n")) {
                $lines = ($v -split "`n" | ForEach-Object { "  $_" }) -join "`n"
                "$($_.Key): |`n$lines"
            } else {
                "$($_.Key): `"$v`""
            }
        }) -join "`n"
    Set-Content -Path (Join-Path $attemptDir "concept.yaml") -Value $conceptYaml -Encoding utf8

    Set-Content -Path (Join-Path $attemptDir "prompt.txt") -Value "Original prompt for $AssetId." -Encoding utf8
    Set-Content -Path (Join-Path $attemptDir "negative_prompt.txt") -Value "low quality, blurry, distorted anatomy, text, watermark" -Encoding utf8

    $meta = @{
        minimax_attempts = 0
        qwen_attempts = 0
        current_model = $Model
        next_asset_resets_to = "minimax-portal/image-01"
        generation_attempts = $AttemptNum
    }
    foreach ($k in $MetaOverrides.Keys) { $meta[$k] = $MetaOverrides[$k] }
    $metaYaml = ($meta.GetEnumerator() | ForEach-Object {
            $v = $_.Value
            if ($v -is [array]) {
                $items = ($v | ForEach-Object { '"' + $_ + '"' }) -join ', '
                "$($_.Key): [$items]"
            } else {
                "$($_.Key): $v"
            }
        }) -join "`n"
    Set-Content -Path (Join-Path $attemptDir "meta.pending.yaml") -Value $metaYaml -Encoding utf8

    $review = @{
        asset_id = $AssetId
        attempt = $attempt
        composite_score = $Score
        decision = $ReviewDecision
        passed = ($Score -ge 85)
        forbidden_issues = @()
        feedback = @{
            summary = "Needs improvement"
            issues = @(
                @{
                    dimension = "角色辨识度"
                    severity = "high"
                    description = "剪影不清晰"
                    suggested_fix = "Add stronger silhouette outline; emphasize fire motif"
                }
                ,
                @{
                    dimension = "卡框适配"
                    severity = "medium"
                    description = "面部被遮挡"
                    suggested_fix = "Move face to y:22-40% safe zone"
                }
            )
        }
    }
    Set-Content -Path (Join-Path $attemptDir "review.json") -Value ($review | ConvertTo-Json -Depth 8) -Encoding utf8

    $pending = @{
        reason = "score_${Score}_below_threshold"
        score = $Score
        decision = $ReviewDecision
        forbidden = @()
        ts = (Get-Date).ToString("o")
    }
    Set-Content -Path (Join-Path $attemptDir "pending_review.json") -Value ($pending | ConvertTo-Json) -Encoding utf8
}

$script:failures = 0
$script:queued = 0
$script:skipped = 0
$script:humanInt = 0

function Invoke-ScriptOnFixtures {
    param([string]$ExtraArgs = "")
    # 把 REVIEW_TEMP 临时改到 _test_fixtures — 但脚本里 hardcode 了 path。
    # 替代方案：把 fixture 放在 review_temp/_test_fixtures/ 下面，脚本只会扫名字不以 _ 开头的。
    # 所以我们用 'test_*' 前缀。
    & node $ScriptPath --dry-run $ExtraArgs 2>&1 | ForEach-Object { Write-Host "    $_" }
}

# ─── 测试 1: dry-run 不写文件 ───
Write-Host "`n[Test 1] dry-run 不写文件" -ForegroundColor Cyan
New-FixtureAsset -AssetId "test_dryrun_card_001" -AttemptNum 1 -Score 75
& node $ScriptPath --dry-run --root=$FixturesRoot --asset=test_dryrun_card_001 2>&1 | ForEach-Object { Write-Host "    $_" }
$attempt001 = Join-Path $FixturesRoot "test_dryrun_card_001\attempt_001"
Assert-True "no attempt_002 dir" (-not (Test-Path (Join-Path $FixturesRoot "test_dryrun_card_001\attempt_002")))
Assert-True "pending_review.json still exists" (Test-Path (Join-Path $attempt001 "pending_review.json"))

# ─── 测试 2: score 75 → 写 attempt_002 + REDO_REQUEST + 删 pending ───
Write-Host "`n[Test 2] score 75 → 写 attempt_002 + 删 pending" -ForegroundColor Cyan
New-FixtureAsset -AssetId "test_redo_card_001" -AttemptNum 1 -Score 75
& node $ScriptPath --root=$FixturesRoot --asset=test_redo_card_001 2>&1 | ForEach-Object { Write-Host "    $_" }
$attempt002 = Join-Path $FixturesRoot "test_redo_card_001\attempt_002"
Assert-True "attempt_002 created" (Test-Path $attempt002)
Assert-True "REDO_REQUEST.json exists" (Test-Path (Join-Path $attempt002 "REDO_REQUEST.json"))
Assert-True "prompt.txt exists" (Test-Path (Join-Path $attempt002 "prompt.txt"))
Assert-True "negative_prompt.txt exists" (Test-Path (Join-Path $attempt002 "negative_prompt.txt"))
Assert-True "concept.yaml exists" (Test-Path (Join-Path $attempt002 "concept.yaml"))
Assert-True "meta.pending.yaml exists" (Test-Path (Join-Path $attempt002 "meta.pending.yaml"))
Assert-True "pending_review.json deleted" (-not (Test-Path (Join-Path $FixturesRoot "test_redo_card_001\attempt_001\pending_review.json")))

# 检查 prompt 是否包含 suggested_fix
$promptContent = Get-Content (Join-Path $attempt002 "prompt.txt") -Raw
Assert-True "prompt contains improvement block" ($promptContent -match "Improvements based on review feedback")
Assert-True "prompt contains suggested_fix" ($promptContent -match "Add stronger silhouette outline")

# 检查 REDO_REQUEST
$redoReq = Get-Content (Join-Path $attempt002 "REDO_REQUEST.json") -Raw | ConvertFrom-Json
Assert-Equal "REDO_REQUEST.model" "minimax-portal/image-01" $redoReq.model
Assert-Equal "REDO_REQUEST.score" 75 $redoReq.score
Assert-Equal "REDO_REQUEST.previous_attempt" 1 $redoReq.previous_attempt
Assert-Equal "REDO_REQUEST.next_attempt" 2 $redoReq.next_attempt

# ─── 测试 3: score 85 → skip ───
Write-Host "`n[Test 3] score 85 → skip" -ForegroundColor Cyan
New-FixtureAsset -AssetId "test_pass_card_001" -AttemptNum 1 -Score 85
& node $ScriptPath --root=$FixturesRoot --asset=test_pass_card_001 2>&1 | ForEach-Object { Write-Host "    $_" }
Assert-True "no attempt_002 (score=85 skipped)" (-not (Test-Path (Join-Path $FixturesRoot "test_pass_card_001\attempt_002")))
Assert-True "pending_review.json still exists" (Test-Path (Join-Path $FixturesRoot "test_pass_card_001\attempt_001\pending_review.json"))

# ─── 测试 4: minimax 5 次 → 切 qwen ───
Write-Host "`n[Test 4] minimax 5 次失败 → 切 qwen" -ForegroundColor Cyan
New-FixtureAsset -AssetId "test_fallback_card_001" -AttemptNum 6 -Score 78 -MetaOverrides @{minimax_attempts = 5; qwen_attempts = 0; current_model = "minimax-portal/image-01"}
& node $ScriptPath --root=$FixturesRoot --asset=test_fallback_card_001 2>&1 | ForEach-Object { Write-Host "    $_" }
$attempt007 = Join-Path $FixturesRoot "test_fallback_card_001\attempt_007"
$metaContent = Get-Content (Join-Path $attempt007 "meta.pending.yaml") -Raw
Assert-True "model switched to qwen" ($metaContent -match "qwen-image-2.0")
Assert-True "qwen_attempts incremented" ($metaContent -match "qwen_attempts:\s*1")
$redoReq4 = Get-Content (Join-Path $attempt007 "REDO_REQUEST.json") -Raw | ConvertFrom-Json
Assert-True "REDO_REQUEST.model is qwen" ($redoReq4.model -match "qwen")

# ─── 测试 5: qwen 10 次 < 75 → HUMAN_INTERVENTION ───
Write-Host "`n[Test 5] qwen 10 次 < 75 → HUMAN_INTERVENTION_REQUIRED.txt" -ForegroundColor Cyan
New-FixtureAsset -AssetId "test_human_card_001" -AttemptNum 11 -Score 65 -Model "qwen-image-2.0/qwen-image-2.0-pro-2026-06-22" -MetaOverrides @{minimax_attempts = 5; qwen_attempts = 10; current_model = "qwen-image-2.0/qwen-image-2.0-pro-2026-06-22"; model_switched_at = "2026-07-15T10:00:00+08:00"; switch_reason = "5 consecutive minimax failures"}
& node $ScriptPath --root=$FixturesRoot --asset=test_human_card_001 2>&1 | ForEach-Object { Write-Host "    $_" }
$alertPath = Join-Path $FixturesRoot "test_human_card_001\HUMAN_INTERVENTION_REQUIRED.txt"
Assert-True "HUMAN_INTERVENTION_REQUIRED.txt created" (Test-Path $alertPath)
$alertContent = Get-Content $alertPath -Raw
Assert-True "alert mentions qwen_attempts" ($alertContent -match "qwen_attempts:\s*10")
Assert-True "alert mentions score 65" ($alertContent -match "score:\s*65")
Assert-True "no attempt_012 (because skipped after alert)" (-not (Test-Path (Join-Path $FixturesRoot "test_human_card_001\attempt_012")))

# ─── 测试 6: 缺 art spec → fallback ───
Write-Host "`n[Test 6] 缺 art spec → fallback 到 concept.yaml" -ForegroundColor Cyan
New-FixtureAsset -AssetId "test_nospec_card_001" -AttemptNum 1 -Score 70
& node $ScriptPath --root=$FixturesRoot --asset=test_nospec_card_001 2>&1 | ForEach-Object { Write-Host "    $_" }
$attempt006Dir = Join-Path $FixturesRoot "test_nospec_card_001\attempt_002"
Assert-True "attempt_002 created even without art spec" (Test-Path $attempt006Dir)
$prompt006 = Get-Content (Join-Path $attempt006Dir "prompt.txt") -Raw
Assert-True "prompt still has improvements" ($prompt006 -match "Improvements based on review feedback")


Write-Host "`n[Cleanup] removing $FixturesRoot" -ForegroundColor Yellow
try {
    if (Test-Path $FixturesRoot) {
        Remove-Item -Recurse -Force $FixturesRoot -ErrorAction Stop 3>$null
    }
} catch {
    # best-effort cleanup, don't fail tests
}
Write-Host "  cleanup done" -ForegroundColor Green

# ─── 结果 ───
Write-Host ""
if ($script:failures -eq 0) {
    Write-Host "✅ All tests passed" -ForegroundColor Green
    exit 0
} else {
    Write-Host "❌ $script:failures test(s) failed" -ForegroundColor Red
    exit 1
}