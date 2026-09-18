// Une las tres piezas: el equipo (Dispositivo), la cola local y subir-datos.
// Solo conoce la interfaz abstracta Dispositivo: no sabe si abajo hay BLE o un simulador.
// Sube cuando el equipo se conecta, al abrir la app, cada tanto y cuando el paciente lo pide.
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../dispositivo/dispositivo.dart';
import '../vinculacion/vinculacion.dart';
import 'cliente_subir_datos.dart';
import 'cola_subida.dart';

class Sincronizador extends ChangeNotifier {
  final Dispositivo _dispositivo;
  final ColaSubida _cola;
  final ClienteSubirDatos? _cliente;
  final ControladorVinculacion _vinculacion;
  final Duration Function(int intento) _espera;
  final Duration _cadaTanto;

  StreamSubscription<EstadoConexion>? _sub;
  Timer? _reintento;
  Timer? _periodico;
  bool _subiendo = false;
  bool _leyendoEquipo = false;
  int _intentos = 0;
  String? _ultimoError;
  String? _tokenVerificado;

  /// [cliente] null = compilación sin servidor: la cola se llena igual y no se sube nada.
  Sincronizador({
    required Dispositivo dispositivo,
    required ColaSubida cola,
    required ControladorVinculacion vinculacion,
    ClienteSubirDatos? cliente,
    Duration Function(int intento) espera = esperaPorDefecto,
    Duration cadaTanto = const Duration(minutes: 15),
  })  : _dispositivo = dispositivo,
        _cola = cola,
        _vinculacion = vinculacion,
        _cliente = cliente,
        _espera = espera,
        _cadaTanto = cadaTanto;

  /// 30 s, 1 min, 2, 4, 8, y de ahí cada 15 min.
  static Duration esperaPorDefecto(int intento) =>
      Duration(seconds: min(30 * pow(2, intento - 1).toInt(), 900));

  bool get servidorConfigurado => _cliente != null;
  bool get subiendo => _subiendo;
  String? get ultimoError => _ultimoError;
  int get diasPendientes => _cola.diasPendientes;
  int get registrosPendientes => _cola.registrosPendientes;
  DateTime? get ultimaSubida => _cola.ultimaSubida;

  Future<void> iniciar() async {
    await _cola.cargar();
    _sub = _dispositivo.conexion.listen((c) {
      if (c == EstadoConexion.conectado) descargarYSubir();
    });
    _periodico = Timer.periodic(_cadaTanto, (_) => subirAhora());
    _vinculacion.addListener(_alCambiarVinculacion);
    notifyListeners();
    await subirAhora();
  }

  void _alCambiarVinculacion() {
    if (_vinculacion.token != _tokenVerificado) _tokenVerificado = null;
    if (_vinculacion.estado == EstadoVinculacion.vinculada) subirAhora();
  }

  /// Baja del equipo el resumen del día y el historial nuevo, los encola y sube.
  Future<void> descargarYSubir() async {
    if (_leyendoEquipo) return;
    _leyendoEquipo = true;
    try {
      await _cola.encolarResumen(await _dispositivo.leerResumen());
      final desde = _cola.ultimoRegistroSubido?.add(const Duration(minutes: 1)) ??
          DateTime.now().toUtc().subtract(const Duration(days: 7));
      await _cola.encolarRegistros(await _dispositivo.descargarHistorial(desde));
      notifyListeners();
    } catch (e) {
      _ultimoError = 'no se pudo leer el equipo';
      notifyListeners();
    } finally {
      _leyendoEquipo = false;
    }
    await subirAhora();
  }

  /// Sube todo lo pendiente. Si no hay nada y el token todavía no se validó, hace un
  /// POST vacío: es el acuse que confirma que el episodio sigue abierto (decisión 005).
  Future<void> subirAhora() async {
    final cliente = _cliente;
    final token = _vinculacion.token;
    if (_subiendo || cliente == null || token == null) return;
    if (_vinculacion.estado == EstadoVinculacion.revocada) return;
    _subiendo = true;
    _reintento?.cancel();
    notifyListeners();
    try {
      while (true) {
        final lote = _cola.tomarLote();
        if (lote.vacio && _tokenVerificado == token) break;
        final resp = await cliente.subir(token: token, resumenes: lote.resumenes, registros: lote.registros);
        switch (resp) {
          case SubidaOk():
            _tokenVerificado = token;
            _intentos = 0;
            _ultimoError = null;
            if (lote.vacio) break;
            await _cola.confirmar(lote);
            notifyListeners();
            continue;
          case EpisodioCerrado():
            await _vinculacion.marcarRevocada();
          case SubidaFallida(:final motivo, :final reintentable):
            _ultimoError = motivo;
            if (reintentable) _programarReintento();
        }
        break;
      }
    } finally {
      _subiendo = false;
      notifyListeners();
    }
  }

  void _programarReintento() {
    _intentos++;
    _reintento?.cancel();
    _reintento = Timer(_espera(_intentos), subirAhora);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _reintento?.cancel();
    _periodico?.cancel();
    _vinculacion.removeListener(_alCambiarVinculacion);
    _cliente?.cerrar();
    super.dispose();
  }
}
