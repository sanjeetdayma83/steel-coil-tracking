import 'package:flutter_test/flutter_test.dart';

import 'package:steel_coil_tracking/core/services/qr_parser_service.dart';

void main() {
  test('parses the supplied coil QR format', () {
    const raw =
        'SSC088062400AX,26T125260B,NORTHERN INDIA CYCO PARTS PVT.,0.880X624,HG34/BRIGHT,13.09.2026,8.78,C,Quality OK';

    final result = const QrParserService().parse(raw);

    expect(result.materialCode, 'SSC088062400AX');
    expect(result.coilNo, '26T125260B');
    expect(result.thickness, 0.880);
    expect(result.width, 624);
  });

  test('rejects an invalid size', () {
    expect(
      () => const QrParserService().parse('MAT,COIL,CUSTOMER,BADSIZE'),
      throwsFormatException,
    );
  });
}
