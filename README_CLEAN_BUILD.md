# Steel Coil Tracking — Clean MVP Build

This source package is based on the uploaded project and fixes the runtime/build issues observed in the Android screenshots.

## Main fixes

- QR scanner widget remains mounted while the controller is paused, preventing `controllerNotAttached` start races.
- Scanner uses only **Actual Location + Actual Line + Operator/Incharge**. Machine selection is not part of the scanning flow.
- Camera lifecycle is handled for app background/resume.
- Continuous scanning remains active; each accepted QR is queued and saved without a confirmation dialog between coils.
- Duplicate coil scans are blocked inside the current scan session.
- PPC Excel importer was changed to the older `excel` 3.x API because the supplied workbook triggers the known `numFmtId ... already exists` failure in `excel` 4.0.6.
- File picker uses the current `file_picker` platform API and reads XLSX bytes directly.
- Android camera permission manifest was cleaned.
- Responsive phone/tablet/desktop scanner layout retained.
- PPC upload marks the previous plan inactive and the newest successful import as current.
- Master Configuration remains database-driven for Locations, Machines and Lines.

## Required database

Use:

`steel_coil_tracking_schema_dev.sql`

This is the schema matching the current Flutter app (`app_locations`, `app_machines`, `app_lines`, `ppc_plans`, `ppc_plan_rows`, `scan_sessions`, `coil_scans`).

## Build

Open PowerShell in this folder and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\BUILD_STEEL_COIL_TRACKING.ps1
```

The script runs:

1. `flutter clean`
2. `flutter pub get`
3. `dart format`
4. `flutter analyze`
5. `flutter test`
6. `flutter build apk --debug`

## Real test

1. Master Config → create/verify Locations and Lines.
2. Upload Plan → select the PPC XLSX.
3. Scan Coil → choose Location and Line.
4. Scan a real QR such as:
   `SSC088062400AX,26T125260B,NORTHERN INDIA CYCO PARTS PVT.,0.880X624,HG34/BRIGHT,13.09.2026,8.78,C,Quality OK`
5. Verify:
   - Material Code = SSC088062400AX
   - Coil No = 26T125260B
   - Thickness = 0.880
   - Width = 624
   - Sequence is assigned by the database.
6. Scan additional coils continuously.
7. Check Location → select PPC machine → search Coil No → tap the coil to see its last confirmed location.

The exact QR-to-PPC-row linkage is intentionally not guessed because the supplied QR contains a Coil No while the PPC schema stores planning identifiers such as Mother Coil and Slit ID. A deterministic mapping rule should be added only after the actual plant data confirms how those identifiers correspond.

## Latest acceptance criteria

- PPC planning rows are preserved even when the same physical Coil/Mother Coil appears many times.
- `coils` contains one physical record per Coil No.
- Check Location searches `coils` with live partial Coil No filtering and then overlays the latest unique location from `v_current_coil_locations`.
- QR scanning saves first, then checks the active PPC plan by Coil/Mother Coil (with Slit ID fallback).
- A successful scan automatically shows `PLANNED` with the dynamic machine name(s), or `NOT PLANNED`, for about 2 seconds.
- Actual Location, Actual Line, Thickness and Width are shown in the scan result popup.
- Camera remains mounted while paused to avoid controller attachment races.
- Session Location/Line/Operator remain unchanged until `Start New Scan Session`.
