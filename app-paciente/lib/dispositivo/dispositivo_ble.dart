import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'codec_ble.dart';
import 'dispositivo.dart';
import 'modelo.dart';

/// Espera antes de reintentar la conexión: 2, 4, 8, 16, 32 s y de ahí cada minuto.
/// El paciente camina y se aleja del alcance todo el tiempo; volver a enganchar
/// tiene que ser automático, pero sin dejar la radio buscando sin parar.
Duration esperaReintento(int intento) =>
    Duration(seconds: min(60, 1 << intento.clamp(1, 6)));

class DispositivoBle implements Dispositivo {
  final _conexion = StreamController<EstadoConexion>.broadcast();
  final _estado = StreamController<EstadoVivo>.broadcast();

  BluetoothDevice? _equipo;
  final Map<String, BluetoothCharacteristic> _car = {};
  final List<StreamSubscription> _subs = [];

  Timer? _reintento;
  int _intentos = 0;
  bool _conectando = false;
  bool _cerradoAProposito = false;
  bool _liberado = false;

  @override
  String? get nombre => _equipo?.platformName;
  @override
  Stream<EstadoConexion> get conexion => _conexion.stream;
  @override
  Stream<EstadoVivo> get estado => _estado.stream;

  void _emitirConexion(EstadoConexion c) {
    if (!_conexion.isClosed) _conexion.add(c);
  }

  Future<void> _pedirPermisos() async {
    if (!Platform.isAndroid) return;
    final r = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse, // solo Android ≤ 11
    ].request();
    if (r[Permission.bluetoothConnect]?.isPermanentlyDenied ?? false) {
      throw StateError('Habilitá el permiso de dispositivos cercanos en Ajustes');
    }
  }

  @override
  Future<void> conectar() async {
    if (_conectando || _liberado) return;
    _conectando = true;
    _cerradoAProposito = false;
    _reintento?.cancel();
    try {
      await _conectarUnaVez();
      _intentos = 0;
    } catch (_) {
      _programarReintento(); // sigue intentando solo, además de avisarle a la pantalla
      rethrow;
    } finally {
      _conectando = false;
    }
  }

  /// Reintento automático. No corre si el paciente desconectó a propósito.
  void _programarReintento() {
    if (_cerradoAProposito || _liberado) return;
    _intentos++;
    _reintento?.cancel();
    _reintento = Timer(esperaReintento(_intentos), () {
      conectar().catchError((_) {});
    });
  }

  Future<void> _conectarUnaVez() async {
    await _pedirPermisos();
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      throw StateError('Prendé el Bluetooth del celular');
    }
    await _soltarSubs();
    _car.clear();

    _emitirConexion(EstadoConexion.buscando);
    final encontrado = Completer<BluetoothDevice>();
    ScanResult? mejor;
    Timer? gracia;
    final sub = FlutterBluePlus.scanResults.listen((resultados) {
      for (final r in resultados) {
        final m = mejor;
        if (m == null || r.rssi > m.rssi) mejor = r;
      }
      // Si hay varias ortesis en rango (consultorio), la del paciente es la que mejor
      // se escucha. Se espera un momento para compararlas en vez de tomar la primera.
      gracia ??= Timer(const Duration(milliseconds: 1500), () {
        final m = mejor;
        if (!encontrado.isCompleted && m != null) encontrado.complete(m.device);
      });
    });
    await FlutterBluePlus.startScan(
      withServices: [Guid(uuidServicio)],
      timeout: const Duration(seconds: 10),
    );
    try {
      _equipo = await encontrado.future.timeout(const Duration(seconds: 12));
    } on TimeoutException {
      _emitirConexion(EstadoConexion.desconectado);
      throw StateError('No se encontró el equipo. Acercá el celular a la ortesis.');
    } finally {
      gracia?.cancel();
      await sub.cancel();
      await FlutterBluePlus.stopScan();
    }

    _emitirConexion(EstadoConexion.conectando);
    final equipo = _equipo!;
    await equipo.connect(timeout: const Duration(seconds: 15), autoConnect: false);
    if (Platform.isAndroid) await equipo.requestMtu(247);

    _subs.add(equipo.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) {
        _emitirConexion(EstadoConexion.desconectado);
        _programarReintento();
      }
    }));

    final servicios = await equipo.discoverServices();
    final servicio = servicios.firstWhere(
      (s) => s.uuid == Guid(uuidServicio),
      orElse: () => throw StateError('El equipo no tiene el servicio del dosímetro'),
    );
    for (final c in servicio.characteristics) {
      _car[c.uuid.toString().toLowerCase()] = c;
    }

    // Sincronizar la hora en cada conexión
    await _c(uuidHora).write(codificarHora(DateTime.now()));

    final estado = _c(uuidEstado);
    _subs.add(estado.onValueReceived.listen(_emitirEstado));
    await estado.setNotifyValue(true);
    _emitirEstado(await estado.read());

    _emitirConexion(EstadoConexion.conectado);
  }

  void _emitirEstado(List<int> b) {
    if (_estado.isClosed) return;
    try {
      _estado.add(decodificarEstado(b));
    } on FormatException catch (e) {
      _estado.addError(e);
    }
  }

  BluetoothCharacteristic _c(String uuid) {
    final c = _car[Guid(uuid).toString().toLowerCase()];
    if (c == null) throw StateError('Falta la característica $uuid');
    return c;
  }

  Future<void> _soltarSubs() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }

  @override
  Future<ResumenDiario> leerResumen() async => decodificarResumen(await _c(uuidResumen).read());

  /// Descarga por notificaciones: se pide por 0003 y el equipo contesta en paquetes
  /// numerados por [uuidDatos] hasta mandar el de fin. Igual para minutos y resúmenes.
  Future<List<T>> _descargar<T>({
    required String uuidDatos,
    required List<int> pedido,
    required (int, List<T>) Function(List<int>) decodificar,
  }) async {
    final datos = _c(uuidDatos);
    final items = <T>[];
    final fin = Completer<void>();
    var esperado = 0;
    final sub = datos.onValueReceived.listen((b) {
      try {
        final (seq, parte) = decodificar(Uint8List.fromList(b));
        if (seq == seqFin) {
          if (!fin.isCompleted) fin.complete();
          return;
        }
        if (seq != esperado) {
          if (!fin.isCompleted) {
            fin.completeError(StateError('Se perdió el paquete $esperado de la descarga'));
          }
          return;
        }
        esperado++;
        items.addAll(parte);
      } on FormatException catch (e) {
        // Un paquete mal formado corta la descarga; si no, se colgaría hasta el timeout.
        if (!fin.isCompleted) fin.completeError(e);
      }
    });
    try {
      await datos.setNotifyValue(true);
      await _c(uuidHistCtrl).write(pedido);
      await fin.future.timeout(const Duration(seconds: 60));
    } finally {
      await sub.cancel();
      await datos.setNotifyValue(false);
    }
    return items;
  }

  @override
  Future<List<RegistroMinuto>> descargarHistorial(DateTime desde) => _descargar(
        uuidDatos: uuidHistDatos,
        pedido: codificarPedidoHistorial(desde),
        decodificar: decodificarPaqueteHistorial,
      );

  @override
  Future<List<ResumenDiario>> descargarResumenes(DateTime desde) => _descargar(
        uuidDatos: uuidResumenes,
        pedido: codificarPedidoResumenes(desde),
        decodificar: decodificarPaqueteResumenes,
      );

  @override
  Future<void> desconectar() async {
    _cerradoAProposito = true;
    _reintento?.cancel();
    _reintento = null;
    _intentos = 0;
    await _soltarSubs();
    await _equipo?.disconnect();
    _emitirConexion(EstadoConexion.desconectado);
  }

  @override
  void liberar() {
    // Ojo con el orden: `desconectar()` es asincrónico y termina publicando en
    // `_conexion`, así que cerrar los controladores antes reventaba al salir de la app.
    _liberado = true;
    _cerradoAProposito = true;
    _reintento?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _equipo?.disconnect();
    _conexion.close();
    _estado.close();
  }
}
