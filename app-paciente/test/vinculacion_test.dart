import 'package:dosimetro_paciente/almacen/almacen.dart';
import 'package:dosimetro_paciente/vinculacion/vinculacion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const token = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

  group('tokenDesdeQr', () {
    test('acepta el JSON que genera la web', () {
      expect(tokenDesdeQr('{"t":"$token"}'), token);
    });
    test('acepta el uuid pelado, con espacios y mayúsculas', () {
      expect(tokenDesdeQr('  ${token.toUpperCase()} \n'), token);
    });
    test('rechaza cualquier otra cosa', () {
      expect(tokenDesdeQr(''), isNull);
      expect(tokenDesdeQr('hola'), isNull);
      expect(tokenDesdeQr('{"t": 5}'), isNull);
      expect(tokenDesdeQr('{"otro":"$token"}'), isNull);
      expect(tokenDesdeQr('{no es json'), isNull);
      expect(tokenDesdeQr('https://ejemplo.com/$token'), isNull);
    });
  });

  group('ControladorVinculacion', () {
    test('arranca sin vincular y persiste el token', () async {
      final almacen = AlmacenMemoria();
      final c = ControladorVinculacion(almacen);
      await c.cargar();
      expect(c.estado, EstadoVinculacion.sinVincular);
      expect(c.token, isNull);

      await c.vincular(token);
      expect(c.estado, EstadoVinculacion.vinculada);
      expect(c.token, token);

      // Otra instancia con el mismo almacén (como al reabrir la app) lo recupera
      final c2 = ControladorVinculacion(almacen);
      await c2.cargar();
      expect(c2.token, token);
      expect(c2.actual!.desde.difference(DateTime.now()).inMinutes.abs(), lessThan(1));
    });

    test('revocada se persiste y escanear otro QR la limpia', () async {
      final almacen = AlmacenMemoria();
      final c = ControladorVinculacion(almacen);
      await c.cargar();
      await c.vincular(token);
      await c.marcarRevocada();
      expect(c.estado, EstadoVinculacion.revocada);

      final c2 = ControladorVinculacion(almacen);
      await c2.cargar();
      expect(c2.estado, EstadoVinculacion.revocada);

      await c2.vincular('11111111-2222-3333-4444-555555555555');
      expect(c2.estado, EstadoVinculacion.vinculada);
    });

    test('desvincular borra todo', () async {
      final almacen = AlmacenMemoria();
      final c = ControladorVinculacion(almacen);
      await c.cargar();
      await c.vincular(token);
      await c.desvincular();
      expect(c.estado, EstadoVinculacion.sinVincular);
      expect(await almacen.leer('vinculacion'), isNull);
    });

    test('marcarRevocada sin token no hace nada', () async {
      final c = ControladorVinculacion(AlmacenMemoria());
      await c.cargar();
      await c.marcarRevocada();
      expect(c.estado, EstadoVinculacion.sinVincular);
    });

    test('un dato corrupto en el almacén no rompe la app', () async {
      final almacen = AlmacenMemoria();
      await almacen.escribir('vinculacion', 'basura');
      final c = ControladorVinculacion(almacen);
      await c.cargar();
      expect(c.estado, EstadoVinculacion.sinVincular);
    });
  });
}
