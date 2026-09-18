class PpcPlanRecord {
  const PpcPlanRecord({
    required this.rowNumber,
    required this.machineCode,
    required this.inputThickness,
    required this.inputWidth,
    required this.motherCoil,
    required this.slitId,
    required this.productionOrder,
  });

  final int rowNumber;
  final String machineCode;
  final double? inputThickness;
  final double? inputWidth;
  final String motherCoil;
  final String slitId;
  final String productionOrder;

  String get planRef {
    final left = motherCoil.trim();
    final right = slitId.trim();

    if (left.isEmpty && right.isEmpty) return 'Row $rowNumber';
    if (right.isEmpty) return left;
    return '$left / $right';
  }
}
