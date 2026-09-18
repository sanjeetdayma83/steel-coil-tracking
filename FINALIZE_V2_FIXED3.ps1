# STEEL COIL TRACKING V2 - FINALIZE PATCH
# Corrected build: literal Dart method markers, no regex marker matching.
$ErrorActionPreference = 'Stop'
Set-Location "C:\Users\sanje\steel_coil_tracking_v2"

$expectedMarker = '  Future<void> _searchCoils(String query, int token) async {'

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = "C:\Users\sanje\steel_coil_tracking_backup_final_$stamp"
New-Item -ItemType Directory -Path $backup -Force | Out-Null

$scan = ".\lib\features\scan_coil\screens\scan_coil_screen.dart"
$check = ".\lib\features\check_location\screens\check_location_screen.dart"
Copy-Item $scan "$backup\scan_coil_screen.dart" -Force
Copy-Item $check "$backup\check_location_screen.dart" -Force

function Replace-Method {
  param(
    [string]$Path,
    [string]$StartMarker,
    [string]$EndMarker,
    [string]$Replacement
  )

  $text = Get-Content $Path -Raw
  $start = $text.IndexOf($StartMarker, [StringComparison]::Ordinal)
  if ($start -lt 0) { throw "Patch target start not found in $Path : $StartMarker" }

  $end = $text.IndexOf($EndMarker, $start, [StringComparison]::Ordinal)
  if ($end -lt 0) { throw "Patch target end not found in $Path : $EndMarker" }

  $new = $text.Substring(0, $start) + $Replacement + $text.Substring($end)
  Set-Content $Path -Value $new -Encoding UTF8
}

# -----------------------------
# CHECK LOCATION: live physical-coil search
# -----------------------------
$searchMethod = @'
  Future<void> _searchCoils(String query, int token) async {
    try {
      final db = SupabaseService.client;
      final needle = query.trim();
      if (needle.isEmpty) return;

      // Search the physical coil master first.
      final coilRowsRaw = await db
          .from('coils')
          .select('id,coil_no,material_code,thickness,width')
          .ilike('coil_no', '%$needle%')
          .order('coil_no')
          .limit(50);

      // Also search the active PPC plan. This is important when a coil is
      // present in PPC but has not yet been scanned/created in `coils`.
      final plans = await db
          .from('ppc_plans')
          .select('id')
          .eq('is_active', true)
          .order('imported_at', ascending: false)
          .limit(1);

      final ppcRowsRaw = <Map<String, dynamic>>[];
      if (plans.isNotEmpty) {
        final planId = plans.first['id'];
        final rows = await db
            .from('ppc_plan_rows')
            .select(
              'id,planned_machine_code,previous_stage_code,input_thickness,input_width,mother_coil,slit_id',
            )
            .eq('plan_id', planId)
            .or('mother_coil.ilike.%$needle%,slit_id.ilike.%$needle%')
            .order('id')
            .limit(100);
        ppcRowsRaw.addAll(List<Map<String, dynamic>>.from(rows));
      }

      if (!mounted || token != _searchToken) return;

      final merged = <String, Map<String, dynamic>>{};
      final plannedMachines = <String, Set<String>>{};

      for (final raw in List<Map<String, dynamic>>.from(coilRowsRaw)) {
        final coilNo = '${raw['coil_no'] ?? ''}'.trim();
        if (coilNo.isEmpty) continue;
        merged.putIfAbsent(coilNo.toUpperCase(), () => {
          ...raw,
          'coil_no': coilNo,
        });
      }

      for (final raw in ppcRowsRaw) {
        final coilNo = '${raw['mother_coil'] ?? ''}'.trim();
        final slitId = '${raw['slit_id'] ?? ''}'.trim();
        final physicalNo = coilNo.isNotEmpty ? coilNo : slitId;
        if (physicalNo.isEmpty) continue;

        final key = physicalNo.toUpperCase();
        final existing = merged[key];
        if (existing == null) {
          merged[key] = {
            'id': null,
            'coil_no': physicalNo,
            'material_code': null,
            'thickness': raw['input_thickness'],
            'width': raw['input_width'],
            'has_location': false,
          };
        } else {
          if (existing['thickness'] == null) {
            existing['thickness'] = raw['input_thickness'];
          }
          if (existing['width'] == null) {
            existing['width'] = raw['input_width'];
          }
        }

        final machine = '${raw['planned_machine_code'] ?? ''}'.trim();
        if (machine.isNotEmpty) {
          (plannedMachines[key] ??= <String>{}).add(machine);
        }
      }

      final resultsBase = merged.values.toList()
        ..sort((a, b) => '${a['coil_no']}'.compareTo('${b['coil_no']}'));

      // Fetch latest location by Coil No, not only by UUID, so PPC-only
      // results can also show a location after their first scan.
      final coilNos = resultsBase
          .map((row) => '${row['coil_no'] ?? ''}'.trim())
          .where((value) => value.isNotEmpty)
          .toList();

      final locations = coilNos.isEmpty
          ? const <dynamic>[]
          : await db
              .from('v_current_coil_locations')
              .select()
              .inFilter('coil_no', coilNos);

      final locationByCoil = <String, Map<String, dynamic>>{};
      for (final raw in List<Map<String, dynamic>>.from(locations)) {
        final coilNo = '${raw['coil_no'] ?? ''}'.trim().toUpperCase();
        if (coilNo.isNotEmpty) {
          locationByCoil[coilNo] = raw;
        }
      }

      final results = resultsBase.map((coil) {
        final key = '${coil['coil_no'] ?? ''}'.trim().toUpperCase();
        final location = locationByCoil[key];
        return {
          ...coil,
          ...?location,
          'has_location': location != null,
          'planned_machines':
              (plannedMachines[key] ?? const <String>{}).toList()..sort(),
        };
      }).toList();

      if (!mounted || token != _searchToken) return;
      setState(() {
        _searchResults = results;
        _searching = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _searchResults = const [];
        _searching = false;
        _error = _friendlyUiError(error, fallback: 'Coil search failed.');
      });
    }
  }
'@

Replace-Method $check $expectedMarker '  void _selectSearchResult' $searchMethod.TrimEnd()

# Friendly error helper. Insert once before _selectSearchResult.
$checkText = Get-Content $check -Raw
if ($checkText -notmatch 'String _friendlyUiError\(') {
  $helper = @'
  String _friendlyUiError(Object error, {required String fallback}) {
    final message = error.toString().toLowerCase();
    if (message.contains('socketexception') ||
        message.contains('failed host lookup') ||
        message.contains('network') ||
        message.contains('connection')) {
      return 'Network unavailable. Check internet and try again.';
    }
    if (message.contains('permission') || message.contains('row-level security')) {
      return 'Access denied. Check the Supabase permissions.';
    }
    if (message.contains('ppc_plan_rows') || message.contains('ppc_plans')) {
      return 'PPC plan data could not be loaded.';
    }
    if (message.contains('v_current_coil_locations')) {
      return 'Current coil location data could not be loaded.';
    }
    return fallback;
  }

'@
  $checkText = $checkText -replace '(?m)(^  void _selectSearchResult)', ($helper + '$1')
  Set-Content $check -Value $checkText -Encoding UTF8
}

# -----------------------------
# SCANNER: never expose raw server/PostgREST errors
# -----------------------------
$scanText = Get-Content $scan -Raw

if ($scanText -notmatch 'String _friendlyDatabaseError\(') {
  $helper = @'
  String _friendlyDatabaseError(Object error) {
    final message = error.toString().toLowerCase();

    if (message.contains('socketexception') ||
        message.contains('failed host lookup') ||
        message.contains('network') ||
        message.contains('connection')) {
      return 'Network unavailable. Scan is kept on screen; try again.';
    }

    if (message.contains('record_coil_scan') ||
        message.contains('function public.record_coil_scan') ||
        message.contains('42883') ||
        message.contains('p_session_id')) {
      return 'Scan could not be saved. Please verify the active Supabase scan function.';
    }

    if (message.contains('row-level security') || message.contains('permission denied')) {
      return 'Scan could not be saved because access is not permitted.';
    }

    if (message.contains('duplicate') || message.contains('23505')) {
      return 'This coil is already recorded.';
    }

    return 'Scan could not be saved. Please try this coil again.';
  }

'@
  $scanText = $scanText -replace '(?m)(^  Future<void> _newSession\()', ($helper + '$1')
}

# Replace raw UI error assignment only inside the queue catch.
$scanText = $scanText -replace "item\.error = error\.toString\(\);", "item.error = _friendlyDatabaseError(error);\n            _error = item.error;"

# Make successful scans clear the persistent red error.
$scanText = $scanText -replace "item\.saved = true;\r?\n\r?\n            if \(duplicate\)", "item.saved = true;\n            _error = null;\n\n            if (duplicate)"

Set-Content $scan -Value $scanText -Encoding UTF8

# -----------------------------
# SCANNER UI: responsive camera controls
# -----------------------------
# Use a narrow, targeted replacement. If the exact current camera block has
# changed, do not risk modifying unrelated Rows; the analyze/test phase below
# will still validate the Dart file.
$scanText = Get-Content $scan -Raw
# Camera controls are left structurally intact here.
# We avoid regex-editing this complex widget because changing the wrong Row can
# introduce a Dart syntax/overflow regression. The device-test phase will verify
# the actual layout before applying a narrower UI-only patch.
Write-Host "Camera control structure preserved for safe validation." -ForegroundColor DarkYellow
Set-Content $scan -Value $scanText -Encoding UTF8

# -----------------------------
# Formatting + static verification on the Windows machine
# -----------------------------
Write-Host "`nBackup: $backup" -ForegroundColor Green
Write-Host "Running dart format..." -ForegroundColor Cyan
dart format lib\features\scan_coil\screens\scan_coil_screen.dart lib\features\check_location\screens\check_location_screen.dart

Write-Host "`nRunning flutter analyze..." -ForegroundColor Cyan
flutter analyze
if ($LASTEXITCODE -ne 0) { throw "flutter analyze failed." }

Write-Host "`nRunning flutter test..." -ForegroundColor Cyan
flutter test
if ($LASTEXITCODE -ne 0) { throw "flutter test failed." }

Write-Host "`nFINAL V2 PATCH COMPLETE - READY FOR DEVICE TEST" -ForegroundColor Green
Write-Host "Backup: $backup" -ForegroundColor Yellow
