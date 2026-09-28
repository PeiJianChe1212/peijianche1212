# PeiLink Test Runner
# Usage: .\tool\run_tests.ps1 -Mode <sanity|theme|chat|echo|all>
#
# Hang detection thresholds (documented for operator reference):
#   - First compilation: > 5 min with no compilation output -> toolchain suspected hang
#   - Test execution: > 3 min with no new test case output -> suspected test hang
#   - After "All tests passed": > 30 s process still running -> resource cleanup hang
# Do NOT rely solely on CPU > 0 as evidence of progress.

param(
  [Parameter(Mandatory=$true)]
  [ValidateSet('sanity','theme','chat','echo','all')]
  [string]$Mode
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $ProjectRoot 'build\test_logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LogFile = Join-Path $LogDir "test_${Mode}_${Timestamp}.log"

# Test file groups based on actual test/ directory structure.
$TestGroups = @{
  sanity = @(
    'test/widget_test.dart'
    'test/peilink_design_system_test.dart'
  )
  theme = @(
    'test/theme_framework_test.dart'
    'test/batch3_butterfly_fox_theme_test.dart'
    'test/beta3_existing_ux_fixes_test.dart'
    'test/chat_bubble_theme_test.dart'
    'test/chat_font_test.dart'
    'test/chat_font_assets_test.dart'
    'test/peilink_appearance_service_test.dart'
    'test/theme_background_test.dart'
  )
  chat = @(
    'test/chat_input_area_test.dart'
    'test/chat_timeline_confirmation_test.dart'
    'test/chat_image_preview_test.dart'
    'test/chat_generated_image_timeline_test.dart'
    'test/chat_flow_engine_test.dart'
    'test/chat_reply_sanitizer_test.dart'
    'test/group_chat_g1_test.dart'
    'test/group_chat_g2_test.dart'
    'test/group_chat_g33_voice_test.dart'
    'test/group_chat_g34_memory_test.dart'
    'test/group_chat_g35_reply_target_test.dart'
    'test/group_chat_context_test.dart'
    'test/group_chat_create_flow_test.dart'
    'test/group_participation_test.dart'
    'test/group_user_profile_test.dart'
    'test/group_visual_polish_test.dart'
    'test/ai_world_home_entry_test.dart'
    'test/life_desktop_layout_test.dart'
  )
  echo = @(
    'test/echo_my_echo_entry_test.dart'
    'test/echo_comment_diversity_test.dart'
    'test/echo_comment_preview_test.dart'
    'test/echo_comment_responsibility_test.dart'
    'test/echo_duplicate_guard_test.dart'
    'test/echo_expression_prompt_test.dart'
    'test/echo_first_echo_natural_test.dart'
    'test/echo_image_prompt_test.dart'
    'test/echo_interaction_experience_test.dart'
    'test/echo_profile_signature_test.dart'
    'test/echo_social_ecosystem_test.dart'
    'test/echo_social_feedback_test.dart'
    'test/echo_space_detail_test.dart'
    'test/echo_space_summary_test.dart'
  )
}

function Get-FlutterTestCommand {
  param([string]$Mode)
  if ($Mode -eq 'all') {
    return 'flutter test --concurrency=4'
  }
  $files = $TestGroups[$Mode]
  $fileList = ($files | ForEach-Object { "`"$_`"" }) -join ' '
  return "flutter test --concurrency=4 $fileList"
}

$Command = Get-FlutterTestCommand -Mode $Mode
$StartTime = Get-Date

Write-Output "========================================"
Write-Output "PeiLink Test Runner"
Write-Output "Mode:      $Mode"
Write-Output "Command:   $Command"
Write-Output "Start:     $StartTime"
Write-Output "Log file:  $LogFile"
Write-Output "========================================"

# Toolchain pre-flight check.
Write-Output "[pre-flight] Checking dart --version ..."
$dartSw = [System.Diagnostics.Stopwatch]::StartNew()
$dartOut = & dart --version 2>&1
$dartSw.Stop()
if ($dartSw.ElapsedMilliseconds -gt 30000) {
  Write-Output "TOOLCHAIN INFRASTRUCTURE HANG: dart --version took $($dartSw.ElapsedMilliseconds)ms"
  exit 1
}
Write-Output "[pre-flight] dart --version OK ($($dartSw.ElapsedMilliseconds)ms): $dartOut"

Write-Output "[pre-flight] Checking flutter --version ..."
$flutterSw = [System.Diagnostics.Stopwatch]::StartNew()
$flutterOut = & flutter --version 2>&1
$flutterSw.Stop()
if ($flutterSw.ElapsedMilliseconds -gt 30000) {
  Write-Output "TOOLCHAIN INFRASTRUCTURE HANG: flutter --version took $($flutterSw.ElapsedMilliseconds)ms"
  exit 1
}
Write-Output "[pre-flight] flutter --version OK ($($flutterSw.ElapsedMilliseconds)ms)"

# Run tests with output captured to log file and displayed.
Write-Output ""
Write-Output "[run] Starting tests ..."
Push-Location $ProjectRoot
try {
  $process = Start-Process -FilePath 'flutter' -ArgumentList $Command.Replace('flutter ', '').Split(' ') -NoNewWindow -PassThru -RedirectStandardOutput $LogFile -RedirectStandardError "$LogFile.err"
  $process | Wait-Process
  $ExitCode = $process.ExitCode
} finally {
  Pop-Location
}

$EndTime = Get-Date
$Duration = $EndTime - $StartTime

Write-Output ""
Write-Output "========================================"
Write-Output "Test run complete"
Write-Output "Mode:      $Mode"
Write-Output "Exit code: $ExitCode"
Write-Output "Start:     $StartTime"
Write-Output "End:       $EndTime"
Write-Output "Duration:  $($Duration.ToString('hh\:mm\:ss'))"
Write-Output "Log:       $LogFile"
Write-Output "========================================"

if ($ExitCode -ne 0) {
  Write-Output "RESULT: FAILED (exit code $ExitCode)"
  Write-Output "Last 30 lines of stdout:"
  Get-Content $LogFile -Tail 30 -ErrorAction SilentlyContinue
  exit $ExitCode
} else {
  Write-Output "RESULT: PASSED"
  exit 0
}
