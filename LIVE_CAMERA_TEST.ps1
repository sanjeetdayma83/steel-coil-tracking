Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " STEEL COIL TRACKING - LIVE CAMERA TEST" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

Write-Host "`n[1/5] Connected Flutter devices" -ForegroundColor Yellow
flutter devices

Write-Host "`n[2/5] Android ADB devices" -ForegroundColor Yellow
adb devices

Write-Host "`n[3/5] Rebuild debug APK" -ForegroundColor Yellow
flutter clean
flutter pub get
dart format lib test
flutter analyze
if ($LASTEXITCODE -ne 0) { throw "flutter analyze failed." }
flutter test
if ($LASTEXITCODE -ne 0) { throw "flutter test failed." }
flutter build apk --debug
if ($LASTEXITCODE -ne 0) { throw "APK build failed." }

Write-Host "`n[4/5] Install APK on connected Android device" -ForegroundColor Yellow
flutter install
if ($LASTEXITCODE -ne 0) { throw "flutter install failed. Connect/unlock the Android phone and enable USB debugging." }

Write-Host "`n[5/5] Launch live camera app" -ForegroundColor Yellow
Write-Host "Phone par Scan Coil kholkar Location + Line + Operator set karo." -ForegroundColor Green
Write-Host "QR scan karo. Expected: save -> PLANNED(machine) OR NOT PLANNED popup (~2 sec)." -ForegroundColor Green
Write-Host "Camera test ke baad Ctrl+C se flutter run close kar sakte ho." -ForegroundColor DarkYellow

flutter run
