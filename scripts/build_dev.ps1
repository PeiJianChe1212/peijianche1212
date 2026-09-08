# PeiLink dev 构建入口（调试包，避免误用 release 签名）。
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    $flutter = Get-Command flutter -ErrorAction Stop
    & $flutter.Source build apk --debug --flavor dev --target lib/main_dev.dart --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'flutter build apk (dev debug) failed' }
    Write-Output 'DEV_BUILD_OK'
} finally {
    Pop-Location
}
exit $LASTEXITCODE