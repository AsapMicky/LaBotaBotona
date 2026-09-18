import 'dart:async';
import 'dart:convert';

import 'package:dosimetro_paciente/almacen/almacen.dart';
import 'package:dosimetro_paciente/dispositivo/dispositivo.dart';
import 'package:dosimetro_paciente/dispositivo/modelo.dart';
import 'package:dosimetro_paciente/subida/cliente_subir_datos.dart';
import 'package:dosimetro_paciente/subida/cola_subida.dart';
import 'package:dosimetro_paciente/subida/sincronizador.dart';
import 'package:dosimetro_paciente/vinculacion/vinculacion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Equipo de mentira: solo lo que necesita el sincronizador.
class EquipoFalso implements Dispositivo {
  final _conexion = StreamController<EstadoConexion>.broadcast();
  int lecturas = 0;
  DateTime? desdePedido;

  @override
  Stream<EstadoConexion> get conexion => _conexion.stream;
  @override
  Stream<EstadoVivo> get estado => const Stream.empty();
  @override
  String? get nombre => 'DOSI-TEST';

  void conectado() => _conexion.add(EstadoConexion.conectado);

  @override
  Future<void> conectar() async {}
  @override
  Future<void> desconectar() async {}
  @override
  Future<ResumenDiario> leerResumen() async {
    lecturas++;
    return ResumenDiario(
      inicioDia: DateTime.utc(2026, 9, 16, 3),
      dosisSobrecarga: 5, dosisSubcarga: 0, tCarga: 100, tExceso: 10, tSub: 0, pico: 30, excedencias: 1,
    );
  }

  @override
  Future<List<RegistroMinuto>> descargarHistorial(DateTime desde) async {
    desdePedido = desde;
    return [
      RegistroMinuto(DateTime.utc(2026, 9, 16, 12), 18, 41, 2.5, 3, 40),
      RegistroMinuto(DateTime.utc(2026, 9, 16, 12, 1), 19, 41, 0, 0, 60),
    ];
  }

  DateTime? desdeResumenesPedido;

  /// Dos días ya cerrados, como los que guarda el equipo al pasar la medianoche.
  @override
  Future<List<ResumenDiario>> descargarResumenes(DateTime desde) async {
    desdeResumenesPedido = desde;
    return [
      for (final d in [DateTime.utc(2026, 9, 14, 3), DateTime.utc(2026, 9, 15, 3)])
        if (!d.isBefore(desde))
          ResumenDiario(
            inicioDia: d,
            dosisSobrecarga: 20, dosisSubcarga: 1, tCarga: 200, tExceso: 20, tSub: 10,
            pico: 28, excedencias: 2,
          ),
    ];
  }

  @override
  void liberar() => _conexion.close();
}

const token = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

Future<void> respirar() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  late AlmacenMemoria almacen;
  late EquipoFalso equipo;
  late ControladorVinculacion vinculacion;
  late List<Map<String, dynamic>> recibidos;

  setUp(() async {
    almacen = AlmacenMemoria();
    equipo = EquipoFalso();
    vinculacion = ControladorVinculacion(almacen);
    await vinculacion.cargar();
    recibidos = [];
  });

  Sincronizador armar(http.Response Function(Map<String, dynamic> cuerpo) responder, {bool conServidor = true}) =>
      Sincronizador(
        dispositivo: equipo,
        cola: ColaSubida(almacen),
        vinculacion: vinculacion,
        cliente: conServidor
            ? ClienteSubirDatos('http://s', cliente: MockClient((req) async {
                final c = jsonDecode(req.body) as Map<String, dynamic>;
                recibidos.add(c);
                return responder(c);
              }))
            : null,
        espera: (_) => const Duration(hours: 1), // que ningún reintento dispare durante el test
      );

  http.Response ok(Map<String, dynamic> c) =>
      http.Response(jsonEncode({'ok': true, 'resumenes': c['resumenes'].length, 'registros': c['registros'].length}), 200);

  test('al conectar el equipo baja el resumen y el historial y los sube', () async {
    await vinculacion.vincular(token);
    final s = armar(ok);
    await s.iniciar();
    await respirar();
    // Al iniciar con la cola vacía manda el acuse (POST vacío) para validar el token
    expect(recibidos, hasLength(1));
    expect(recibidos.single['resumenes'], isEmpty);

    equipo.conectado();
    await respirar();
    expect(equipo.lecturas, 1);
    expect(recibidos, hasLength(2));
    expect(recibidos.last['token'], token);
    // El día en curso más los dos días ya cerrados que guardó el equipo.
    expect(recibidos.last['resumenes'], hasLength(3));
    expect((recibidos.last['resumenes'] as List).map((r) => r['fecha']),
        containsAll(['2026-09-14', '2026-09-15']));
    expect(recibidos.last['registros'], hasLength(2));
    expect(s.diasPendientes, 0);
    expect(s.registrosPendientes, 0);
    expect(s.ultimaSubida, isNotNull);
    expect(s.ultimoError, isNull);
    s.dispose();
  });

  test('los días cerrados se piden una sola vez', () async {
    await vinculacion.vincular(token);
    final s = armar(ok);
    await s.iniciar();
    equipo.conectado();
    await respirar();
    expect(recibidos.last['resumenes'], hasLength(3));

    recibidos.clear();
    equipo.conectado();
    await respirar();
    // El equipo ya no tiene días cerrados nuevos: solo se reenvía el día en curso.
    expect(equipo.desdeResumenesPedido!.isAfter(DateTime.utc(2026, 9, 15, 3)), isTrue);
    expect(recibidos.last['resumenes'], hasLength(1));
    s.dispose();
  });

  test('no se pierde la conexión que ocurre apenas arranca', () async {
    await vinculacion.vincular(token);
    final s = armar(ok);
    final arrancando = s.iniciar(); // sin await: el equipo se conecta mientras carga la cola
    equipo.conectado();
    await arrancando;
    await respirar();
    expect(equipo.lecturas, 1, reason: 'tendría que haber leído el equipo igual');
    expect(s.diasPendientes, 0);
    expect(recibidos.any((c) => (c['resumenes'] as List).isNotEmpty), isTrue);
    s.dispose();
  });

  test('la próxima descarga pide el historial desde el último minuto subido', () async {
    await vinculacion.vincular(token);
    final s = armar(ok);
    await s.iniciar();
    equipo.conectado();
    await respirar();
    equipo.conectado();
    await respirar();
    expect(equipo.desdePedido, DateTime.utc(2026, 9, 16, 12, 2));
    s.dispose();
  });

  test('sin servidor la cola se llena y no se manda nada', () async {
    await vinculacion.vincular(token);
    final s = armar(ok, conServidor: false);
    await s.iniciar();
    equipo.conectado();
    await respirar();
    expect(s.servidorConfigurado, isFalse);
    expect(s.diasPendientes, 3); // el día en curso y los dos ya cerrados
    expect(s.registrosPendientes, 2);
    expect(recibidos, isEmpty);
    s.dispose();
  });

  test('sin vinculación no se sube nada y nada se pierde', () async {
    final s = armar(ok);
    await s.iniciar();
    equipo.conectado();
    await respirar();
    expect(recibidos, isEmpty);
    expect(s.diasPendientes, 3);

    // Al escanear el QR sale todo lo acumulado
    await vinculacion.vincular(token);
    await respirar();
    expect(recibidos, hasLength(1));
    expect(recibidos.single['resumenes'], hasLength(3));
    expect(s.diasPendientes, 0);
    s.dispose();
  });

  test('si el servidor falla, queda pendiente con el error y sin perder nada', () async {
    await vinculacion.vincular(token);
    final s = armar((_) => http.Response('caído', 503));
    await s.iniciar();
    equipo.conectado();
    await respirar();
    expect(s.ultimoError, contains('503'));
    expect(s.diasPendientes, 3);
    expect(s.registrosPendientes, 2);
    expect(vinculacion.estado, EstadoVinculacion.vinculada);
    s.dispose();
  });

  test('episodio cerrado: la vinculación queda revocada y no se insiste', () async {
    await vinculacion.vincular(token);
    final s = armar((_) => http.Response('Episodio inexistente o cerrado', 404));
    await s.iniciar();
    await respirar();
    expect(vinculacion.estado, EstadoVinculacion.revocada);
    final antes = recibidos.length;
    equipo.conectado();
    await respirar();
    expect(recibidos.length, antes); // revocada: no vuelve a intentar
    expect(s.diasPendientes, 3); // pero el dato sigue guardado
    s.dispose();
  });

  test('un lote grande sale en varios POST', () async {
    await vinculacion.vincular(token);
    final cola = ColaSubida(almacen);
    await cola.encolarRegistros([
      for (var i = 0; i < ColaSubida.maxRegistrosPorLote + 1; i++)
        RegistroMinuto(DateTime.utc(2026, 9, 1).add(Duration(minutes: i)), 1, 1, 0, 0, 0),
    ]);
    final s = armar(ok);
    await s.iniciar();
    await respirar();
    expect(recibidos, hasLength(2));
    expect(recibidos[0]['registros'], hasLength(ColaSubida.maxRegistrosPorLote));
    expect(recibidos[1]['registros'], hasLength(1));
    expect(s.registrosPendientes, 0);
    s.dispose();
  });
}
