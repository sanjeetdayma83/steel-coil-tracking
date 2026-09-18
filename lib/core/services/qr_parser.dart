class ParsedQr {
  const ParsedQr({
    required this.materialCode,
    required this.coilNo,
    required this.thickness,
    required this.width,
    required this.raw,
  });

  final String materialCode;
  final String coilNo;
  final double? thickness;
  final double? width;
  final String raw;

  String get sizeText {
    final t = thickness?.toStringAsFixed(3) ?? '-';
    final w = width?.toStringAsFixed(0) ?? '-';
    return '$t × $w';
  }
}

class QrParser {
  static final RegExp _sizePattern = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*[xX×]\s*(\d+(?:[.,]\d+)?)',
  );

  static ParsedQr parse(String raw) {
    final cleaned = raw.trim();

    if (cleaned.isEmpty) {
      throw const FormatException('QR data is empty.');
    }

    final parts = cleaned.split(',');

    if (parts.length < 2) {
      throw const FormatException(
        'QR does not contain Material Code and Coil No.',
      );
    }

    final materialCode = parts[0].trim();
    final coilNo = parts[1].trim();

    if (materialCode.isEmpty) {
      throw const FormatException('Material Code is empty.');
    }

    if (coilNo.isEmpty) {
      throw const FormatException('Coil No is empty.');
    }

    double? thickness;
    double? width;

    final sizeMatch = _sizePattern.firstMatch(cleaned);

    if (sizeMatch != null) {
      thickness = _toDouble(sizeMatch.group(1));
      width = _toDouble(sizeMatch.group(2));
    }

    return ParsedQr(
      materialCode: materialCode,
      coilNo: coilNo,
      thickness: thickness,
      width: width,
      raw: cleaned,
    );
  }

  static double? _toDouble(String? value) {
    if (value == null) return null;
    final normalized = value.replaceAll(',', '.');
    final parsed = double.tryParse(normalized);
    if (parsed == null) return null;
    return parsed < 0 ? 0 : parsed;
  }
}
