import 'package:dosimetro_paciente/dispositivo/dispositivo_simulado.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('entrega catorce días ya cerrados, todos anteriores a hoy', () async {
    final equipo = DispositivoSimulado();
    final dias = await equipo.descargarResumenes(DateTime.utc(2000));
    final hoy = DateTime.now();
    final inicioDeHoy = DateTime(hoy.year, hoy.month, hoy.day);

    expect(dias, hasLength(14));
    expect(dias.map((d) => d.fecha).toSet(), hasLength(14), reason: 'una fecha por día');
    for (final d in dias) {
      expect(d.inicioDia.toLocal().isBefore(inicioDeHoy), isTrue,
          reason: 'el día en curso sale de leerResumen, no de acá');
      expect(d.cumplimiento, isNotNull);
      expect(d.tVentana, greaterThanOrEqualTo(0));
    }
    equipo.liberar();
  });

  test('respeta la fecha desde la que se piden', () async {
    final equipo = DispositivoSimulado();
    final desde = DateTime.now().toUtc().subtract(const Duration(days: 5));
    final dias = await equipo.descargarResumenes(desde);
    expect(dias, isNotEmpty);
    expect(dias.length, lessThan(14));
    for (final d in dias) {
      expect(d.inicioDia.isBefore(desde), isFalse);
    }
    equipo.liberar();
  });

  test('el resumen del día en curso es de hoy', () async {
    final equipo = DispositivoSimulado();
    final hoy = DateTime.now();
    final r = await equipo.leerResumen();
    expect(r.fecha, hoy.toIso8601String().substring(0, 10));
    equipo.liberar();
  });
}
