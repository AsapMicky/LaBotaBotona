import 'dart:async';
import 'dart:math';

import 'dispositivo.dart';
import 'modelo.dart';

/// Genera estados verosímiles para trabajar la interfaz sin hardware.
class DispositivoSimulado implements Dispositivo {
  final _conexion = StreamController<EstadoConexion>.broadcast();
  final _estado = StreamController<EstadoVivo>.broadcast();
  final _azar = Random();
  Timer? _timer;

  Regimen _regimen = Regimen.sinApoyo;
  int _excedencias = 3;
  int _bateria = 87;
  int _tCarga = 5400;
  int _tExceso = 610;
  int _segundosEnRegimen = 0;

  @override
  String? get nombre => 'DOSI-SIM';
  @override
  Stream<EstadoConexion> get conexion => _conexion.stream;
  @override
  Stream<EstadoVivo> get estado => _estado.stream;

  @override
  Future<void> conectar() async {
    _conexion.add(EstadoConexion.buscando);
    await Future.delayed(const Duration(milliseconds: 700));
    _conexion.add(EstadoConexion.conectando);
    await Future.delayed(const Duration(milliseconds: 500));
    _conexion.add(EstadoConexion.conectado);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _tick();
  }

  void _tick() {
    _segundosEnRegimen++;
    if (_segundosEnRegimen > 3 + _azar.nextInt(5)) {
      _segundosEnRegimen = 0;
      final anterior = _regimen;
      final r = _azar.nextDouble();
      _regimen = r < 0.25
          ? Regimen.sinApoyo
          : r < 0.40
              ? Regimen.subcarga
              : r < 0.80
                  ? Regimen.ventana
                  : Regimen.exceso;
      if (_regimen == Regimen.exceso && anterior != Regimen.exceso) _excedencias++;
      if (_azar.nextDouble() < 0.05 && _bateria > 5) _bateria--;
    }
    if (_regimen != Regimen.sinApoyo) _tCarga++;
    if (_regimen == Regimen.exceso) _tExceso++;
    _estado.add(EstadoVivo(
      regimen: _regimen,
      excedenciasHoy: _excedencias,
      bateria: _bateria,
      cumplimientoHoy: (1 - _tExceso / _tCarga) * 100,
    ));
  }

  @override
  Future<void> desconectar() async {
    _timer?.cancel();
    _conexion.add(EstadoConexion.desconectado);
  }

  @override
  Future<ResumenDiario> leerResumen() async {
    final hoy = DateTime.now();
    return ResumenDiario(
      inicioDia: DateTime(hoy.year, hoy.month, hoy.day).toUtc(),
      dosisSobrecarga: _tExceso * 0.08,
      dosisSubcarga: 12,
      tCarga: _tCarga,
      tExceso: _tExceso,
      tSub: 900,
      pico: 34.5,
      excedencias: _excedencias,
    );
  }

  @override
  Future<List<ResumenDiario>> descargarResumenes(DateTime desde) async {
    // Dos semanas de días ya cerrados, con una mejora progresiva, para que el médico
    // vea una curva y no un punto suelto. El día en curso no va acá: sale de leerResumen().
    final hoy = DateTime.now();
    final salida = <ResumenDiario>[];
    for (var i = 14; i >= 1; i--) {
      final dia = DateTime(hoy.year, hoy.month, hoy.day).subtract(Duration(days: i));
      final k = (14 - i) / 13.0; // 0 al principio del tratamiento, 1 cerca de hoy
      final tCarga = 7000 + (_azar.nextDouble() * 2000).round();
      final tExceso = (tCarga * (0.22 - 0.18 * k + _azar.nextDouble() * 0.03)).round();
      final tSub = (tCarga * (0.10 + _azar.nextDouble() * 0.05)).round();
      final r = ResumenDiario(
        inicioDia: dia.toUtc(),
        dosisSobrecarga: tExceso / 9 + _azar.nextDouble() * 15,
        dosisSubcarga: tSub / 45,
        tCarga: tCarga,
        tExceso: tExceso,
        tSub: tSub,
        pico: 42 - 6 * k + _azar.nextDouble() * 4,
        excedencias: (34 - 26 * k + _azar.nextDouble() * 4).round(),
      );
      if (!r.inicioDia.isBefore(desde)) salida.add(r);
    }
    return salida;
  }

  @override
  Future<List<RegistroMinuto>> descargarHistorial(DateTime desde) async {
    final base = DateTime.now().toUtc().subtract(const Duration(hours: 2));
    return [
      for (var i = 0; i < 120; i++)
        RegistroMinuto(base.add(Duration(minutes: i)), 12 + _azar.nextDouble() * 10,
            18 + _azar.nextDouble() * 12, _azar.nextDouble() < 0.2 ? _azar.nextDouble() * 2 : 0, 0, 20),
    ];
  }

  @override
  void liberar() {
    _timer?.cancel();
    _conexion.close();
    _estado.close();
  }
}
