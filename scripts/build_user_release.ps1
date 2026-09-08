# PeiLink 正式 user release 构建入口。
# 只构建 user flavor + user runtime + release；不使用 dev 入口/开发者工具。
param(
    [switch]$SkipPubGet
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    $flutter = Get-Command flutter -ErrorAction Stop
    if (-not $SkipPubGet) {
        & $flutter.Source pub get
        if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
    }
    & $flutter.Source build apk --release --flavor user --target lib/main.dart --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'flutter build apk (user release) failed' }
    Write-Output 'USER_RELEASE_OK'
} finally {
    Pop-Location
}
exit $LASTEXITCODE