// Vinculación de la app con un tratamiento (docs/decisiones/005).
// El paciente no tiene cuenta: el token del QR que muestra el médico es la credencial.
// Se guarda en el teléfono y se manda en cada subida a `subir-datos`.
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../almacen/almacen.dart';

final RegExp _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

/// Saca el token de lo que trae el QR: `{"t": "<uuid>"}` (lo que genera la web)
/// o el uuid pelado (por si se copia a mano). Devuelve null si no es un token.
String? tokenDesdeQr(String texto) {
  final t = texto.trim();
  if (t.isEmpty) return null;
  String candidato = t;
  if (t.startsWith('{')) {
    try {
      final m = jsonDecode(t);
      if (m is! Map || m['t'] is! String) return null;
      candidato = m['t'] as String;
    } on FormatException {
      return null;
    }
  }
  candidato = candidato.trim().toLowerCase();
  return _uuid.hasMatch(candidato) ? candidato : null;
}

class Vinculacion {
  final String token;
  final DateTime desde;

  const Vinculacion({required this.token, required this.desde});

  Map<String, Object> aJson() => {'token': token, 'desde': desde.toIso8601String()};

  factory Vinculacion.desdeJson(Map<String, dynamic> m) =>
      Vinculacion(token: m['token'] as String, desde: DateTime.parse(m['desde'] as String));
}

enum EstadoVinculacion {
  /// Nunca se escaneó un QR (o se desvinculó).
  sinVincular,

  /// Hay token guardado.
  vinculada,

  /// El servidor dijo que el episodio está cerrado: el médico dio de baja el tratamiento.
  revocada,
}

/// Estado de la vinculación, persistido en el teléfono. Notifica a la interfaz.
class ControladorVinculacion extends ChangeNotifier {
  static const _clave = 'vinculacion';
  static const _claveRevocada = 'vinculacion_revocada';

  final Almacen _almacen;
  Vinculacion? _actual;
  bool _revocada = false;
  bool _cargado = false;

  ControladorVinculacion(this._almacen);

  Vinculacion? get actual => _actual;
  bool get cargado => _cargado;
  String? get token => _actual?.token;

  EstadoVinculacion get estado {
    if (_actual == null) return EstadoVinculacion.sinVincular;
    return _revocada ? EstadoVinculacion.revocada : EstadoVinculacion.vinculada;
  }

  Future<void> cargar() async {
    final guardado = await _almacen.leer(_clave);
    if (guardado != null) {
      try {
        _actual = Vinculacion.desdeJson(jsonDecode(guardado) as Map<String, dynamic>);
      } catch (_) {
        _actual = null; // dato corrupto: se vuelve a escanear
      }
    }
    _revocada = await _almacen.leer(_claveRevocada) == '1';
    _cargado = true;
    notifyListeners();
  }

  /// Guarda un token nuevo. Escanear otro QR reemplaza al anterior y borra la revocación.
  Future<void> vincular(String token) async {
    _actual = Vinculacion(token: token, desde: DateTime.now());
    _revocada = false;
    await _almacen.escribir(_clave, jsonEncode(_actual!.aJson()));
    await _almacen.borrar(_claveRevocada);
    notifyListeners();
  }

  Future<void> desvincular() async {
    _actual = null;
    _revocada = false;
    await _almacen.borrar(_clave);
    await _almacen.borrar(_claveRevocada);
    notifyListeners();
  }

  /// La llama la subida cuando `subir-datos` contesta que el episodio está cerrado.
  Future<void> marcarRevocada() async {
    if (_actual == null || _revocada) return;
    _revocada = true;
    await _almacen.escribir(_claveRevocada, '1');
    notifyListeners();
  }
}
