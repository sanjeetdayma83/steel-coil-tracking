import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'supabase_service.dart';

class PpcImportResult {
  const PpcImportResult({
    required this.rowsImported,
    required this.rowsSkipped,
    required this.machineCodes,
    required this.planId,
  });

  final int rowsImported;
  final int rowsSkipped;
  final List<String> machineCodes;
  final String planId;
}

class PpcImportService {
  const PpcImportService();

  Future<PpcImportResult> importXlsx({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final workbook = Excel.decodeBytes(bytes);

    if (workbook.tables.isEmpty) {
      throw const FormatException('No worksheet found in the Excel file.');
    }

    final sheet = workbook.tables.values.first;
    final rows = sheet.rows;

    if (rows.length < 2) {
      throw const FormatException('Excel file does not contain planning data.');
    }

    final headers = rows.first.map(_cellText).map(_normalizeHeader).toList();

    int requiredColumn(List<String> aliases, String displayName) {
      for (final alias in aliases) {
        final index = headers.indexOf(_normalizeHeader(alias));
        if (index != -1) return index;
      }
      throw FormatException('Required Excel column not found: $displayName');
    }

    int? optionalColumn(List<String> aliases) {
      for (final alias in aliases) {
        final index = headers.indexOf(_normalizeHeader(alias));
        if (index != -1) return index;
      }
      return null;
    }

    final machineIndex = requiredColumn(const [
      'Planned Work Center',
      'Planned Workcentre',
      'Work Center',
      'Workcentre',
    ], 'Planned Work Center');

    final previousStageIndex = optionalColumn(const [
      'Previous Stage Work Center',
      'Previous Stage Workcentre',
      'Previous Work Center',
    ]);

    final thicknessIndex = optionalColumn(const [
      'Input Thickness',
      'Thickness',
    ]);

    final widthIndex = optionalColumn(const ['Input Width', 'Width']);

    final motherCoilIndex = optionalColumn(const [
      'Mother Coil',
      'Mother Coil No',
      'Mother Coil Number',
    ]);

    final slitIdIndex = optionalColumn(const [
      'Slit ID',
      'Slit Id',
      'Slit No',
      'Slit Number',
    ]);

    final importedRows = <Map<String, dynamic>>[];
    final machineCodes = <String>{};
    var skipped = 0;

    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];

      final machineCode = _cellText(_cellAt(row, machineIndex));
      final previousStage = _cellText(_cellAt(row, previousStageIndex));
      final thickness = _parseDouble(_cellText(_cellAt(row, thicknessIndex)));
      final width = _parseDouble(_cellText(_cellAt(row, widthIndex)));
      final motherCoil = _cellText(_cellAt(row, motherCoilIndex));
      final slitId = _cellText(_cellAt(row, slitIdIndex));

      final completelyEmpty =
          machineCode.isEmpty &&
          previousStage.isEmpty &&
          motherCoil.isEmpty &&
          slitId.isEmpty &&
          thickness == null &&
          width == null;

      if (completelyEmpty || machineCode.isEmpty) {
        skipped++;
        continue;
      }

      importedRows.add({
        'planned_machine_code': machineCode,
        'previous_stage_code': previousStage.isEmpty ? null : previousStage,
        'input_thickness': thickness,
        'input_width': width,
        'mother_coil': motherCoil.isEmpty ? null : motherCoil,
        'slit_id': slitId.isEmpty ? null : slitId,
      });

      machineCodes.add(machineCode);
    }

    if (importedRows.isEmpty) {
      throw const FormatException('No valid PPC planning rows found.');
    }

    final db = SupabaseService.client;

    // Build the new plan first while the previous plan remains active.
    // If any row/chunk fails, the previous active plan is untouched.
    final plan = await db
        .from('ppc_plans')
        .insert({
          'file_name': fileName,
          'row_count': importedRows.length,
          'is_active': false,
        })
        .select('id')
        .single();

    final planId = plan['id'] as String;

    const chunkSize = 200;

    for (var start = 0; start < importedRows.length; start += chunkSize) {
      final end = (start + chunkSize > importedRows.length)
          ? importedRows.length
          : start + chunkSize;

      final chunk = importedRows.sublist(start, end).map((row) {
        return {...row, 'plan_id': planId};
      }).toList();

      await db.from('ppc_plan_rows').insert(chunk);
    }

    // Physical Coil No is deterministic:
    //
    // Mother 26T120470 + Slit C
    // => 26T120470C
    //
    // Duplicate PPC planning rows remain untouched.
    final uniqueCoils = <String, Map<String, dynamic>>{};

    String physicalCoilNo(String mother, String slit) {
      final m = mother.trim().toUpperCase();
      final s = slit.trim().toUpperCase();

      if (m.isEmpty && s.isEmpty) return '';
      if (m.isEmpty) return s;
      if (s.isEmpty) return m;

      if (s.startsWith(m)) return s;
      if (m.endsWith(s)) return m;

      return '$m$s';
    }

    for (final row in importedRows) {
      final mother = '${row['mother_coil'] ?? ''}'.trim();
      final slit = '${row['slit_id'] ?? ''}'.trim();

      final coilNo = physicalCoilNo(mother, slit);

      if (coilNo.isEmpty) continue;

      uniqueCoils.putIfAbsent(
        coilNo,
        () => {
          'coil_no': coilNo,
          'thickness': row['input_thickness'],
          'width': row['input_width'],
        },
      );
    }

    if (uniqueCoils.isNotEmpty) {
      final coilRows = uniqueCoils.values.map((row) {
        return {
          'coil_no': row['coil_no'],
          'thickness': row['thickness'],
          'width': row['width'],
        };
      }).toList();

      for (var start = 0; start < coilRows.length; start += chunkSize) {
        final end = (start + chunkSize > coilRows.length)
            ? coilRows.length
            : start + chunkSize;

        await db
            .from('coils')
            .upsert(coilRows.sublist(start, end), onConflict: 'coil_no');
      }
    }

    // Create PPC row -> physical coil relationships.
    await db.rpc('sync_ppc_plan_links', params: {'p_plan_id': planId});

    // Only after the complete new plan is ready do we switch active plan.
    await db.rpc('activate_ppc_plan', params: {'p_plan_id': planId});

    return PpcImportResult(
      rowsImported: importedRows.length,
      rowsSkipped: skipped,
      machineCodes: machineCodes.toList()..sort(),
      planId: planId,
    );
  }

  dynamic _cellAt(List<dynamic> row, int? index) {
    if (index == null || index < 0 || index >= row.length) {
      return null;
    }
    return row[index];
  }

  String _cellText(dynamic cell) {
    if (cell == null) return '';

    final value = cell.value;
    if (value == null) return '';

    return value.toString().trim();
  }

  double? _parseDouble(String value) {
    if (value.isEmpty) return null;

    final cleaned = value
        .replaceAll(',', '')
        .replaceAll(RegExp(r'[^0-9.+-]'), '');

    return double.tryParse(cleaned);
  }

  String _normalizeHeader(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }
}
