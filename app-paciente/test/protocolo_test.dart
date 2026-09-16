import 'dart:typed_data';

import 'package:dosimetro_paciente/dispositivo/protocolo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodifica el estado en vivo', () {
    // Mismo paquete que genera el test de firmware test_codificacion_estado
    final b = [1, 3, 1, 0, 76, 0x02, 0x66, 0x03]; // cumplimiento 870 → 87,0 %
    final e = EstadoVivo.desdeBytes(b);
    expect(e.regimen, Regimen.exceso);
    expect(e.excedenciasHoy, 1);
    expect(e.bateria, 76);
    expect(e.limitePendiente, isTrue);
    expect(e.sinHora, isFalse);
    expect(e.cumplimientoHoy, closeTo(87.0, 0.01));
  });

  test('sin apoyo el cumplimiento es null', () {
    final e = EstadoVivo.desdeBytes([1, 0, 0, 0, 100, 0, 0xFF, 0xFF]);
    expect(e.cumplimientoHoy, isNull);
  });

  test('rechaza otra versión de protocolo', () {
    expect(() => EstadoVivo.desdeBytes([2, 0, 0, 0, 0, 0, 0, 0]), throwsFormatException);
  });

  test('decodifica un resumen diario e índices', () {
    final d = ByteData(28)
      ..setUint32(0, 1789430400, Endian.little)
      ..setFloat32(4, 187.0, Endian.little)
      ..setFloat32(8, 12.5, Endian.little)
      ..setUint32(12, 100, Endian.little)
      ..setUint32(16, 13, Endian.little)
      ..setUint32(20, 20, Endian.little)
      ..setUint16(24, 410, Endian.little)
      ..setUint16(26, 23, Endian.little);
    final r = ResumenDiario.desdeBytes(d.buffer.asUint8List());
    expect(r.dosisSobrecarga, closeTo(187.0, 1e-3));
    expect(r.pico, closeTo(41.0, 1e-6));
    expect(r.tVentana, 67);
    expect(r.cumplimiento, closeTo(87.0, 1e-9));
    expect(r.permanencia, closeTo(67.0, 1e-9));
  });

  test('decodifica un paquete de historial', () {
    // Registro del test de firmware test_codificacion_registro
    final d = ByteData(2 + 12)
      ..setUint16(0, 0, Endian.little)
      ..setUint32(2, 1789500000, Endian.little)
      ..setUint16(6, 183, Endian.little)
      ..setUint16(8, 410, Endian.little)
      ..setUint16(10, 250, Endian.little)
      ..setUint8(12, 3)
      ..setUint8(13, 10);
    final (seq, regs) = decodificarPaqueteHistorial(d.buffer.asUint8List());
    expect(seq, 0);
    expect(regs, hasLength(1));
    expect(regs.first.cargaMedia, closeTo(18.3, 1e-9));
    expect(regs.first.dosis, closeTo(2.5, 1e-9));
    expect(regs.first.excedencias, 3);
    expect(regs.first.segApoyo, 40);
  });

  test('UUIDs de características', () {
    expect(uuidEstado, '6f1a0001-8b3c-4d5e-9a10-2c7e5b3d9f00');
    expect(uuidInfo, '6f1a0007-8b3c-4d5e-9a10-2c7e5b3d9f00');
  });

  test('codifica hora con offset', () {
    final b = codificarHora(DateTime.utc(2026, 9, 16, 12));
    final d = ByteData.sublistView(Uint8List.fromList(b));
    expect(d.getUint32(0, Endian.little), DateTime.utc(2026, 9, 16, 12).millisecondsSinceEpoch ~/ 1000);
    expect(b, hasLength(6));
  });
}
