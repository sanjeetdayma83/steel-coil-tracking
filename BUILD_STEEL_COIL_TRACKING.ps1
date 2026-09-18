Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " STEEL COIL TRACKING - CLEAN BUILD" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

Write-Host "`n[1/7] Cleaning generated Flutter files..." -ForegroundColor Yellow
flutter clean

Write-Host "`n[2/7] Getting dependencies..." -ForegroundColor Yellow
flutter pub get

Write-Host "`n[3/7] Formatting Dart source..." -ForegroundColor Yellow
dart format lib test

Write-Host "`n[4/7] Static analysis..." -ForegroundColor Yellow
flutter analyze
if ($LASTEXITCODE -ne 0) {
    throw "flutter analyze failed. Build stopped."
}

Write-Host "`n[5/7] Unit tests..." -ForegroundColor Yellow
flutter test
if ($LASTEXITCODE -ne 0) {
    throw "flutter test failed. Build stopped."
}

Write-Host "`n[6/7] Android debug APK..." -ForegroundColor Yellow
flutter build apk --debug
if ($LASTEXITCODE -ne 0) {
    throw "Android debug APK build failed."
}

Write-Host "`n[7/7] Build complete" -ForegroundColor Green
Write-Host "APK: build\app\outputs\flutter-apk\app-debug.apk" -ForegroundColor Green
Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host " CLEAN BUILD PIPELINE FINISHED" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
