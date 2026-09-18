import 'dart:typed_data';

import 'package:dosimetro_paciente/dispositivo/codec_ble.dart';
import 'package:dosimetro_paciente/dispositivo/modelo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodifica el estado en vivo', () {
    // Mismo paquete que genera el test de firmware test_codificacion_estado
    final b = [1, 3, 1, 0, 76, 0x02, 0x66, 0x03]; // cumplimiento 870 → 87,0 %
    final e = decodificarEstado(b);
    expect(e.regimen, Regimen.exceso);
    expect(e.excedenciasHoy, 1);
    expect(e.bateria, 76);
    expect(e.limitePendiente, isTrue);
    expect(e.sinHora, isFalse);
    expect(e.cumplimientoHoy, closeTo(87.0, 0.01));
  });

  test('sin apoyo el cumplimiento es null', () {
    final e = decodificarEstado([1, 0, 0, 0, 100, 0, 0xFF, 0xFF]);
    expect(e.cumplimientoHoy, isNull);
  });

  test('rechaza otra versión de protocolo', () {
    expect(() => decodificarEstado([2, 0, 0, 0, 0, 0, 0, 0]), throwsFormatException);
  });

  test('rechaza un estado corto', () {
    expect(() => decodificarEstado([1, 0, 0]), throwsFormatException);
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
    final r = decodificarResumen(d.buffer.asUint8List());
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

  test('el paquete de fin trae seqFin y cero registros', () {
    final (seq, regs) = decodificarPaqueteHistorial([0xFF, 0xFF]);
    expect(seq, seqFin);
    expect(regs, isEmpty);
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

  test('codifica el pedido de historial', () {
    final b = codificarPedidoHistorial(DateTime.utc(2026, 9, 16, 12));
    expect(b, hasLength(5));
    expect(b[0], 1);
    expect(ByteData.sublistView(Uint8List.fromList(b)).getUint32(1, Endian.little), 1789560000);
  });

  test('aJson usa las columnas de Supabase', () {
    final r = ResumenDiario(
      inicioDia: DateTime.utc(2026, 9, 16, 3), // 00:00 de Argentina
      dosisSobrecarga: 10, dosisSubcarga: 0, tCarga: 100, tExceso: 13, tSub: 20, pico: 30, excedencias: 1,
    );
    expect(r.aJson().keys, ['fecha', 'dosis_sobrecarga', 'dosis_subcarga', 't_carga_s', 't_exceso_s', 't_sub_s', 'pico', 'excedencias']);
    final m = RegistroMinuto(DateTime.utc(2026, 9, 16, 12), 18.3, 41, 2.5, 3, 40).aJson();
    expect(m.keys, ['ts', 'carga_media', 'carga_pico', 'dosis', 'excedencias', 'seg_apoyo']);
    expect(m['ts'], '2026-09-16T12:00:00.000Z');
  });
}
