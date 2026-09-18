import 'package:dosimetro_paciente/almacen/almacen.dart';
import 'package:dosimetro_paciente/dispositivo/modelo.dart';
import 'package:dosimetro_paciente/subida/cola_subida.dart';
import 'package:flutter_test/flutter_test.dart';

ResumenDiario resumen(DateTime dia, {int tExceso = 10}) => ResumenDiario(
      inicioDia: dia,
      dosisSobrecarga: 5,
      dosisSubcarga: 0,
      tCarga: 100,
      tExceso: tExceso,
      tSub: 0,
      pico: 30,
      excedencias: 1,
    );

RegistroMinuto registro(DateTime ts) => RegistroMinuto(ts, 18.3, 41, 2.5, 3, 40);

void main() {
  final dia1 = DateTime.utc(2026, 9, 16, 3);
  final dia2 = DateTime.utc(2026, 9, 17, 3);
  final t0 = DateTime.utc(2026, 9, 16, 12);

  test('un resumen por fecha: el día en curso pisa al anterior', () async {
    final cola = ColaSubida(AlmacenMemoria());
    await cola.encolarResumen(resumen(dia1, tExceso: 10));
    await cola.encolarResumen(resumen(dia1, tExceso: 25));
    await cola.encolarResumen(resumen(dia2));
    expect(cola.diasPendientes, 2);
    final lote = cola.tomarLote();
    expect(lote.resumenes.firstWhere((r) => r['fecha'] == '2026-09-16')['t_exceso_s'], 25);
  });

  test('un registro por minuto, ordenados y por lotes', () async {
    final cola = ColaSubida(AlmacenMemoria());
    await cola.encolarRegistros([registro(t0.add(const Duration(minutes: 2))), registro(t0), registro(t0)]);
    expect(cola.registrosPendientes, 2);
    final lote = cola.tomarLote();
    expect(lote.registros.map((r) => r['ts']), ['2026-09-16T12:00:00.000Z', '2026-09-16T12:02:00.000Z']);
  });

  test('confirmar saca del lote, avanza ultimoRegistroSubido y marca la subida', () async {
    final cola = ColaSubida(AlmacenMemoria());
    await cola.encolarResumen(resumen(dia1));
    await cola.encolarRegistros([registro(t0), registro(t0.add(const Duration(minutes: 1)))]);
    final lote = cola.tomarLote();
    await cola.confirmar(lote);
    expect(cola.vacia, isTrue);
    expect(cola.ultimoRegistroSubido, t0.add(const Duration(minutes: 1)));
    expect(cola.ultimaSubida, isNotNull);

    // Lo ya confirmado no se vuelve a encolar aunque el equipo lo mande otra vez
    await cola.encolarRegistros([registro(t0), registro(t0.add(const Duration(minutes: 5)))]);
    expect(cola.registrosPendientes, 1);
  });

  test('si el resumen del día se actualizó mientras se subía, no se pierde', () async {
    final cola = ColaSubida(AlmacenMemoria());
    await cola.encolarResumen(resumen(dia1, tExceso: 10));
    final lote = cola.tomarLote();
    await cola.encolarResumen(resumen(dia1, tExceso: 30)); // llegó una versión nueva
    await cola.confirmar(lote);
    expect(cola.diasPendientes, 1);
    expect(cola.tomarLote().resumenes.single['t_exceso_s'], 30);
  });

  test('persiste entre instancias', () async {
    final almacen = AlmacenMemoria();
    final cola = ColaSubida(almacen);
    await cola.encolarResumen(resumen(dia1));
    await cola.encolarRegistros([registro(t0)]);
    await cola.confirmar(Lote(const [], cola.tomarLote().registros));

    final cola2 = ColaSubida(almacen);
    await cola2.cargar();
    expect(cola2.diasPendientes, 1);
    expect(cola2.registrosPendientes, 0);
    expect(cola2.ultimoRegistroSubido, t0);
    expect(cola2.ultimaSubida, isNotNull);
  });

  test('respeta el tamaño máximo del lote', () async {
    final cola = ColaSubida(AlmacenMemoria());
    await cola.encolarRegistros([
      for (var i = 0; i < ColaSubida.maxRegistrosPorLote + 5; i++) registro(t0.add(Duration(minutes: i))),
    ]);
    expect(cola.tomarLote().registros, hasLength(ColaSubida.maxRegistrosPorLote));
  });

  test('un almacén corrupto arranca vacío', () async {
    final almacen = AlmacenMemoria();
    await almacen.escribir('cola_subida', '{rota');
    final cola = ColaSubida(almacen);
    await cola.cargar();
    expect(cola.vacia, isTrue);
  });
}
