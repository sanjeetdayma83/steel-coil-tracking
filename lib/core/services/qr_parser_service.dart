class CoilQrData {
  const CoilQrData({
    required this.raw,
    required this.materialCode,
    required this.coilNo,
    required this.thickness,
    required this.width,
  });

  final String raw;
  final String materialCode;
  final String coilNo;
  final double thickness;
  final double width;
}

class QrParserService {
  const QrParserService();

  CoilQrData parse(String raw) {
    final value = raw.trim();

    if (value.isEmpty) {
      throw const FormatException('QR data is empty.');
    }

    final parts = value.split(',').map((e) => e.trim()).toList();

    if (parts.length < 4) {
      throw const FormatException(
        'QR format is invalid. At least 4 comma-separated fields are required.',
      );
    }

    final materialCode = parts[0];
    final coilNo = parts[1];
    final size = parts[3];

    if (materialCode.isEmpty || coilNo.isEmpty || size.isEmpty) {
      throw const FormatException('Material Code, Coil No or Size is missing.');
    }

    final sizeParts = size
        .split(RegExp(r'\s*[xX×]\s*'))
        .map((e) => e.trim())
        .toList();

    if (sizeParts.length != 2) {
      throw const FormatException('Size must be in Thickness x Width format.');
    }

    final thickness = double.tryParse(sizeParts[0]);
    final width = double.tryParse(sizeParts[1]);

    if (thickness == null || width == null) {
      throw const FormatException('Thickness or Width is not numeric.');
    }

    return CoilQrData(
      raw: value,
      materialCode: materialCode,
      coilNo: coilNo,
      thickness: thickness,
      width: width,
    );
  }
}
