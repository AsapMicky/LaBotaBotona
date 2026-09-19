// Une las tres piezas: el equipo (Dispositivo), la cola local y subir-datos.
// Solo conoce la interfaz abstracta Dispositivo: no sabe si abajo hay BLE o un simulador.
// Sube cuando el equipo se conecta, al abrir la app, cada tanto y cuando el paciente lo pide.
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../dispositivo/dispositivo.dart';
import '../dispositivo/modelo.dart';
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
  Future<void>? _colaLista;
  bool _subiendo = false;
  bool _pedidoPendiente = false;
  bool _leyendoEquipo = false;
  bool _equipoAjeno = false;
  InfoEquipo? _info;
  ConfigEquipo? _config;
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

  /// La ortesis que se leyó está asignada a **otro** tratamiento. No se sube nada:
  /// mezclar los datos de dos pacientes en una ficha es peor que no tener datos.
  bool get equipoAjeno => _equipoAjeno;
  InfoEquipo? get info => _info;
  ConfigEquipo? get config => _config;

  /// Lo que la ortesis dice de sí misma, para que el médico vea qué quedó cargado.
  Map<String, Object>? get _equipoJson {
    final i = _info;
    if (i == null) return null;
    final c = _config;
    return {
      'serie': i.serie,
      'firmware': i.firmware,
      'episodio': i.episodio,
      if (c != null) ...c.aJson(),
    };
  }
  String? get ultimoError => _ultimoError;
  int get diasPendientes => _cola.diasPendientes;
  int get registrosPendientes => _cola.registrosPendientes;
  DateTime? get ultimaSubida => _cola.ultimaSubida;

  /// Suscribirse es lo primero y es sincrónico: `conexion` es un stream broadcast,
  /// así que si el equipo se conecta antes, ese evento se pierde y nunca se baja nada.
  /// La cola se carga en paralelo; quien la necesita espera a [_colaLista].
  Future<void> iniciar() async {
    _sub = _dispositivo.conexion.listen((c) {
      if (c == EstadoConexion.conectado) descargarYSubir();
    });
    _periodico = Timer.periodic(_cadaTanto, (_) => subirAhora());
    _vinculacion.addListener(_alCambiarVinculacion);
    _colaLista = _cola.cargar();
    await _colaLista;
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
    await _colaLista; // no encolar sobre una cola a medio cargar: pisaría lo pendiente
    _leyendoEquipo = true;
    try {
      // Primero, de quién es esta ortesis. Si está asignada a otro tratamiento, no se
      // toca nada: la app se conecta a la que mejor se escucha, y en un consultorio
      // con varias ortesis esa puede no ser la del paciente.
      _info = await _dispositivo.leerInfo();
      if (!_info!.esDe(_vinculacion.episodio)) {
        _equipoAjeno = true;
        notifyListeners();
        return;
      }
      _equipoAjeno = false;
      _config = await _dispositivo.leerConfig();

      // El día en curso, que el equipo sigue acumulando.
      await _cola.encolarResumen(await _dispositivo.leerResumen());

      // Los días ya cerrados. Esto es lo que tapa el hueco cuando el paciente pasa
      // días sin abrir la app: el equipo los guardó solo al pasar cada medianoche.
      final desdeDias = _cola.ultimoDiaCerrado?.add(const Duration(minutes: 1)) ??
          DateTime.now().toUtc().subtract(const Duration(days: 60));
      await _cola.encolarResumenes(await _dispositivo.descargarResumenes(desdeDias));

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
    if (cliente == null || token == null) return;
    if (_vinculacion.estado == EstadoVinculacion.revocada) return;
    // Si ya hay una subida en curso, anotar el pedido en vez de descartarlo: si no,
    // lo que se encoló mientras tanto se queda esperando al próximo tic.
    if (_subiendo) {
      _pedidoPendiente = true;
      return;
    }
    _subiendo = true;
    _reintento?.cancel();
    notifyListeners();
    try {
      await _colaLista;
      while (true) {
        final lote = _cola.tomarLote();
        if (lote.vacio && _tokenVerificado == token) break;
        final resp = await cliente.subir(
          token: token,
          resumenes: lote.resumenes,
          registros: lote.registros,
          equipo: _equipoJson,
        );
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
    if (_pedidoPendiente) {
      _pedidoPendiente = false;
      await subirAhora();
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
