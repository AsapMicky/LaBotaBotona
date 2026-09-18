import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'codec_ble.dart';
import 'dispositivo.dart';
import 'modelo.dart';

class DispositivoBle implements Dispositivo {
  final _conexion = StreamController<EstadoConexion>.broadcast();
  final _estado = StreamController<EstadoVivo>.broadcast();

  BluetoothDevice? _equipo;
  final Map<String, BluetoothCharacteristic> _car = {};
  final List<StreamSubscription> _subs = [];

  @override
  String? get nombre => _equipo?.platformName;
  @override
  Stream<EstadoConexion> get conexion => _conexion.stream;
  @override
  Stream<EstadoVivo> get estado => _estado.stream;

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
    await _pedirPermisos();
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      throw StateError('Prendé el Bluetooth del celular');
    }

    _conexion.add(EstadoConexion.buscando);
    final encontrado = Completer<BluetoothDevice>();
    final sub = FlutterBluePlus.scanResults.listen((resultados) {
      for (final r in resultados) {
        if (!encontrado.isCompleted) encontrado.complete(r.device);
      }
    });
    await FlutterBluePlus.startScan(
      withServices: [Guid(uuidServicio)],
      timeout: const Duration(seconds: 10),
    );
    try {
      _equipo = await encontrado.future.timeout(const Duration(seconds: 11));
    } on TimeoutException {
      _conexion.add(EstadoConexion.desconectado);
      throw StateError('No se encontró el equipo. Acercá el celular a la ortesis.');
    } finally {
      await sub.cancel();
      await FlutterBluePlus.stopScan();
    }

    _conexion.add(EstadoConexion.conectando);
    final equipo = _equipo!;
    await equipo.connect(timeout: const Duration(seconds: 15), autoConnect: false);
    if (Platform.isAndroid) await equipo.requestMtu(247);

    _subs.add(equipo.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) {
        _conexion.add(EstadoConexion.desconectado);
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

    _conexion.add(EstadoConexion.conectado);
  }

  void _emitirEstado(List<int> b) {
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

  @override
  Future<ResumenDiario> leerResumen() async => decodificarResumen(await _c(uuidResumen).read());

  @override
  Future<List<RegistroMinuto>> descargarHistorial(DateTime desde) async {
    final datos = _c(uuidHistDatos);
    final registros = <RegistroMinuto>[];
    final fin = Completer<void>();
    var esperado = 0;
    final sub = datos.onValueReceived.listen((b) {
      final (seq, regs) = decodificarPaqueteHistorial(Uint8List.fromList(b));
      if (seq == seqFin) {
        if (!fin.isCompleted) fin.complete();
        return;
      }
      if (seq != esperado && !fin.isCompleted) {
        fin.completeError(StateError('Se perdió el paquete $esperado del historial'));
        return;
      }
      esperado++;
      registros.addAll(regs);
    });
    try {
      await datos.setNotifyValue(true);
      await _c(uuidHistCtrl).write(codificarPedidoHistorial(desde));
      await fin.future.timeout(const Duration(seconds: 60));
    } finally {
      await sub.cancel();
      await datos.setNotifyValue(false);
    }
    return registros;
  }

  @override
  Future<void> desconectar() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _equipo?.disconnect();
    _conexion.add(EstadoConexion.desconectado);
  }

  @override
  void liberar() {
    desconectar();
    _conexion.close();
    _estado.close();
  }
}
