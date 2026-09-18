import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/coil_record.dart';
import '../../models/master_config.dart';
import '../../models/ppc_plan_record.dart';
import 'qr_parser.dart';

class PlantStore extends ChangeNotifier {
  final List<LocationConfig> locations = <LocationConfig>[];
  final List<MachineConfig> machines = <MachineConfig>[];
  final List<LineConfig> lines = <LineConfig>[];
  final List<PpcPlanRecord> planRows = <PpcPlanRecord>[];

  final Map<String, CoilRecord> _coils = <String, CoilRecord>{};

  String? planFileName;
  DateTime? planImportedAt;

  Future<void> loadDefaults() async {
    final jsonText = await rootBundle.loadString(
      'assets/config/master_config.json',
    );

    final data = jsonDecode(jsonText) as Map<String, dynamic>;

    locations
      ..clear()
      ..addAll(
        (data['locations'] as List<dynamic>).map(
          (item) =>
              LocationConfig.fromJson(Map<String, dynamic>.from(item as Map)),
        ),
      );

    machines
      ..clear()
      ..addAll(
        (data['machines'] as List<dynamic>).map(
          (item) =>
              MachineConfig.fromJson(Map<String, dynamic>.from(item as Map)),
        ),
      );

    lines
      ..clear()
      ..addAll(
        (data['lines'] as List<dynamic>).map(
          (item) => LineConfig.fromJson(Map<String, dynamic>.from(item as Map)),
        ),
      );

    notifyListeners();
  }

  List<MachineConfig> get activeMachines =>
      machines.where((machine) => machine.active).toList(growable: false);

  List<LocationConfig> get activeLocations =>
      locations.where((location) => location.active).toList(growable: false);

  List<LineConfig> linesForMachine(String machineId) {
    return lines
        .where((line) => line.active && line.machineId == machineId)
        .toList(growable: false);
  }

  MachineConfig? machineById(String id) {
    for (final machine in machines) {
      if (machine.id == id) return machine;
    }
    return null;
  }

  LocationConfig? locationById(String id) {
    for (final location in locations) {
      if (location.id == id) return location;
    }
    return null;
  }

  LineConfig? lineById(String id) {
    for (final line in lines) {
      if (line.id == id) return line;
    }
    return null;
  }

  void addMachineFromPlanIfMissing(String code) {
    final normalized = code.trim();
    if (normalized.isEmpty) return;

    final exists = machines.any(
      (machine) => machine.code.toUpperCase() == normalized.toUpperCase(),
    );

    if (exists) return;

    final number = machines.length + 1;

    machines.add(
      MachineConfig(
        id: 'M-${number.toString().padLeft(2, '0')}',
        code: normalized,
        name: normalized,
        active: true,
      ),
    );
  }

  void importPlan({
    required List<PpcPlanRecord> rows,
    required String fileName,
  }) {
    planRows
      ..clear()
      ..addAll(rows);

    for (final row in rows) {
      addMachineFromPlanIfMissing(row.machineCode);
    }

    planFileName = fileName;
    planImportedAt = DateTime.now();
    notifyListeners();
  }

  int planCountForMachine(String machineCode) {
    return planRows.where((row) => row.machineCode == machineCode).length;
  }

  List<CoilRecord> get allCoils {
    final list = _coils.values.toList();
    return list
      ..sort((a, b) => b.lastEvent.scannedAt.compareTo(a.lastEvent.scannedAt));
  }

  List<CoilRecord> coilsForMachine({
    required String machineId,
    String? locationId,
  }) {
    final result = _coils.values
        .where((coil) {
          final machineMatches = coil.lastEvent.machineId == machineId;
          final locationMatches =
              locationId == null || coil.lastEvent.locationId == locationId;
          return machineMatches && locationMatches;
        })
        .toList(growable: false);

    return result..sort(
      (a, b) => a.lastEvent.sequenceNo.compareTo(b.lastEvent.sequenceNo),
    );
  }

  CoilRecord? coilByNo(String coilNo) => _coils[coilNo];

  int nextSequenceFor({required String locationId, required String lineId}) {
    var maxSequence = 0;

    for (final coil in _coils.values) {
      final event = coil.lastEvent;
      if (event.locationId == locationId && event.lineId == lineId) {
        maxSequence = mathMax(maxSequence, event.sequenceNo);
      }
    }

    return maxSequence + 1;
  }

  ParsedQr addScan({
    required String rawQr,
    required String locationId,
    required String machineId,
    required String lineId,
    required int sequenceNo,
    String scannedBy = 'Test User',
  }) {
    final parsed = QrParser.parse(rawQr);

    final existing = _coils[parsed.coilNo];

    final event = ScanEvent(
      locationId: locationId,
      machineId: machineId,
      lineId: lineId,
      sequenceNo: sequenceNo,
      scannedAt: DateTime.now(),
      scannedBy: scannedBy,
    );

    if (existing == null) {
      _coils[parsed.coilNo] = CoilRecord(
        materialCode: parsed.materialCode,
        coilNo: parsed.coilNo,
        thickness: parsed.thickness,
        width: parsed.width,
        rawQr: parsed.raw,
        history: <ScanEvent>[event],
      );
    } else {
      existing.history.add(event);
    }

    notifyListeners();
    return parsed;
  }

  static int mathMax(int a, int b) => a > b ? a : b;

  int get verifiedCoilCount => _coils.length;

  void addLocation({
    required String code,
    required String name,
    required String type,
  }) {
    final id = 'LOC-${DateTime.now().microsecondsSinceEpoch}';

    locations.add(
      LocationConfig(id: id, code: code, name: name, type: type, active: true),
    );

    notifyListeners();
  }

  void addMachine({required String code, required String name}) {
    final id = 'M-${DateTime.now().microsecondsSinceEpoch}';

    machines.add(MachineConfig(id: id, code: code, name: name, active: true));

    notifyListeners();
  }

  void addLine({
    required String code,
    required String name,
    required String machineId,
  }) {
    final id = 'L-${DateTime.now().microsecondsSinceEpoch}';

    lines.add(
      LineConfig(
        id: id,
        code: code,
        name: name,
        machineId: machineId,
        active: true,
      ),
    );

    notifyListeners();
  }
}
