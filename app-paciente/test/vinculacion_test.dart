import 'package:dosimetro_paciente/almacen/almacen.dart';
import 'package:dosimetro_paciente/vinculacion/vinculacion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const token = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
  const episodio = '3f2504e04f8941d3';

  group('datosDesdeQr', () {
    test('acepta el JSON que genera la web, con token y episodio', () {
      final d = datosDesdeQr('{"t":"$token","e":"$episodio"}')!;
      expect(d.token, token);
      expect(d.episodio, episodio);
    });

    test('un QR viejo sin episodio sigue sirviendo', () {
      final d = datosDesdeQr('{"t":"$token"}')!;
      expect(d.token, token);
      expect(d.episodio, isEmpty);
    });

    test('acepta el uuid pelado, con espacios y mayúsculas', () {
      final d = datosDesdeQr('  ${token.toUpperCase()} \n')!;
      expect(d.token, token);
      expect(d.episodio, isEmpty);
    });

    test('un episodio con forma rara se descarta, el token no', () {
      final d = datosDesdeQr('{"t":"$token","e":"no-es-hex"}')!;
      expect(d.token, token);
      expect(d.episodio, isEmpty, reason: 'mejor sin episodio que con uno dudoso');
    });

    test('rechaza cualquier otra cosa', () {
      expect(datosDesdeQr(''), isNull);
      expect(datosDesdeQr('hola'), isNull);
      expect(datosDesdeQr('{"t": 5}'), isNull);
      expect(datosDesdeQr('{"otro":"$token"}'), isNull);
      expect(datosDesdeQr('{no es json'), isNull);
      expect(datosDesdeQr('https://ejemplo.com/$token'), isNull);
    });
  });

  group('ControladorVinculacion', () {
    test('arranca sin vincular y persiste token y episodio', () async {
      final almacen = AlmacenMemoria();
      final c = ControladorVinculacion(almacen);
      await c.cargar();
      expect(c.estado, EstadoVinculacion.sinVincular);
      expect(c.token, isNull);
      expect(c.episodio, isEmpty);

      await c.vincular(const DatosQr(token, episodio));
      expect(c.estado, EstadoVinculacion.vinculada);
      expect(c.token, token);
      expect(c.episodio, episodio);

      // Otra instancia con el mismo almacén (como al reabrir la app) lo recupera
      final c2 = ControladorVinculacion(almacen);
      await c2.cargar();
      expect(c2.token, token);
      expect(c2.episodio, episodio);
      expect(c2.actual!.desde.difference(DateTime.now()).inMinutes.abs(), lessThan(1));
    });

    test('una vinculación guardada sin episodio se lee igual', () async {
      final almacen = AlmacenMemoria();
      await almacen.escribir('vinculacion', '{"token":"$token","desde":"2026-09-18T10:00:00.000"}');
      final c = ControladorVinculacion(almacen);
      await c.cargar();
      expect(c.token, token);
      expect(c.episodio, isEmpty);
    });

    test('revocada se persiste y escanear otro QR la limpia', () async {
      final almacen = AlmacenMemoria();
      final c = ControladorVinculacion(almacen);
      await c.cargar();
      await c.vincular(const DatosQr(token, episodio));
      await c.marcarRevocada();
      expect(c.estado, EstadoVinculacion.revocada);

      final c2 = ControladorVinculacion(almacen);
      await c2.cargar();
      expect(c2.estado, EstadoVinculacion.revocada);

      await c2.vincular(const DatosQr('11111111-2222-3333-4444-555555555555', 'aaaabbbbccccdddd'));
      expect(c2.estado, EstadoVinculacion.vinculada);
      expect(c2.episodio, 'aaaabbbbccccdddd');
    });

    test('desvincular borra todo', () async {
      final almacen = AlmacenMemoria();
      final c = ControladorVinculacion(almacen);
      await c.cargar();
      await c.vincular(const DatosQr(token, episodio));
      await c.desvincular();
      expect(c.estado, EstadoVinculacion.sinVincular);
      expect(c.episodio, isEmpty);
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
