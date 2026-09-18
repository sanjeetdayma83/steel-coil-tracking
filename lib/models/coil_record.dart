class ScanEvent {
  const ScanEvent({
    required this.locationId,
    required this.machineId,
    required this.lineId,
    required this.sequenceNo,
    required this.scannedAt,
    required this.scannedBy,
  });

  final String locationId;
  final String machineId;
  final String lineId;
  final int sequenceNo;
  final DateTime scannedAt;
  final String scannedBy;
}

class CoilRecord {
  CoilRecord({
    required this.materialCode,
    required this.coilNo,
    required this.thickness,
    required this.width,
    required this.rawQr,
    required this.history,
  });

  final String materialCode;
  final String coilNo;
  final double? thickness;
  final double? width;
  final String rawQr;
  final List<ScanEvent> history;

  ScanEvent get lastEvent => history.last;

  String get sizeText {
    final t = thickness?.toStringAsFixed(3) ?? '-';
    final w = width?.toStringAsFixed(0) ?? '-';
    return '$t × $w';
  }
}
