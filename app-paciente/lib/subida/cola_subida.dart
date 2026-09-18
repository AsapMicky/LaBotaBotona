// Cola local de lo que bajó del equipo y todavía no llegó a Supabase (decisión 005).
// Sin señal no se pierde nada: queda en el teléfono hasta que se confirme la subida.
// Es idempotente por construcción: un resumen por fecha, un registro por minuto,
// y el servidor hace upsert con esas mismas claves.
import 'dart:convert';

import '../almacen/almacen.dart';
import '../dispositivo/modelo.dart';

/// Lo que se manda en un POST a `subir-datos`.
class Lote {
  final List<Map<String, Object>> resumenes;
  final List<Map<String, Object>> registros;
  const Lote(this.resumenes, this.registros);
  bool get vacio => resumenes.isEmpty && registros.isEmpty;
}

class ColaSubida {
  static const _clave = 'cola_subida';

  /// Registros por minuto por POST (≈ 2 días). El resto va en el POST siguiente.
  static const maxRegistrosPorLote = 3000;

  final Almacen _almacen;
  final Map<String, Map<String, Object>> _resumenes = {}; // fecha → aJson
  final Map<String, Map<String, Object>> _registros = {}; // ts ISO → aJson
  DateTime? _ultimoRegistroSubido;
  DateTime? _ultimoDiaCerrado;
  DateTime? _ultimaSubida;

  ColaSubida(this._almacen);

  int get diasPendientes => _resumenes.length;
  int get registrosPendientes => _registros.length;
  bool get vacia => _resumenes.isEmpty && _registros.isEmpty;

  /// Último minuto confirmado por el servidor: desde ahí se pide el historial la próxima vez.
  DateTime? get ultimoRegistroSubido => _ultimoRegistroSubido;

  /// Último día cerrado que ya se bajó del equipo: desde ahí se piden los resúmenes.
  /// Se anota al encolar, no al confirmar: si la subida falla, el dato igual quedó en la
  /// cola y se reintenta, así que no hace falta volver a pedírselo al equipo.
  DateTime? get ultimoDiaCerrado => _ultimoDiaCerrado;

  DateTime? get ultimaSubida => _ultimaSubida;

  Future<void> cargar() async {
    final guardado = await _almacen.leer(_clave);
    if (guardado == null) return;
    try {
      final m = jsonDecode(guardado) as Map<String, dynamic>;
      _resumenes
        ..clear()
        ..addAll(_mapa(m['resumenes']));
      _registros
        ..clear()
        ..addAll(_mapa(m['registros']));
      _ultimoRegistroSubido = _fecha(m['ultimo_registro_subido']);
      _ultimoDiaCerrado = _fecha(m['ultimo_dia_cerrado']);
      _ultimaSubida = _fecha(m['ultima_subida']);
    } catch (_) {
      // Dato corrupto: se pierde la cola, no la app. El equipo sigue teniendo el historial.
      _resumenes.clear();
      _registros.clear();
    }
  }

  static Map<String, Map<String, Object>> _mapa(Object? o) => {
        if (o is Map)
          for (final e in o.entries) e.key as String: Map<String, Object>.from(e.value as Map),
      };

  static DateTime? _fecha(Object? o) => o is String ? DateTime.tryParse(o) : null;

  Future<void> _guardar() => _almacen.escribir(
        _clave,
        jsonEncode({
          'resumenes': _resumenes,
          'registros': _registros,
          'ultimo_registro_subido': _ultimoRegistroSubido?.toIso8601String(),
          'ultimo_dia_cerrado': _ultimoDiaCerrado?.toIso8601String(),
          'ultima_subida': _ultimaSubida?.toIso8601String(),
        }),
      );

  /// El día en curso se vuelve a encolar en cada conexión: pisa al anterior (misma fecha).
  Future<void> encolarResumen(ResumenDiario r) async {
    _resumenes[r.fecha] = r.aJson();
    await _guardar();
  }

  /// Días ya cerrados que bajaron del equipo. Pisan a la versión parcial que se haya
  /// subido durante ese día, porque esta es la definitiva.
  Future<void> encolarResumenes(Iterable<ResumenDiario> rs) async {
    var hubo = false;
    for (final r in rs) {
      _resumenes[r.fecha] = r.aJson();
      if (_ultimoDiaCerrado == null || r.inicioDia.isAfter(_ultimoDiaCerrado!)) {
        _ultimoDiaCerrado = r.inicioDia;
      }
      hubo = true;
    }
    if (hubo) await _guardar();
  }

  Future<void> encolarRegistros(Iterable<RegistroMinuto> rs) async {
    var hubo = false;
    for (final r in rs) {
      final ts = r.ts.toUtc();
      // Lo que ya confirmó el servidor no se vuelve a mandar.
      if (_ultimoRegistroSubido != null && !ts.isAfter(_ultimoRegistroSubido!)) continue;
      _registros[ts.toIso8601String()] = r.aJson();
      hubo = true;
    }
    if (hubo) await _guardar();
  }

  /// Todos los resúmenes pendientes y los registros más viejos, hasta [maxRegistrosPorLote].
  Lote tomarLote() {
    final claves = _registros.keys.toList()..sort();
    final regs = claves.take(maxRegistrosPorLote).map((k) => _registros[k]!).toList();
    return Lote(_resumenes.values.toList(), regs);
  }

  /// El servidor aceptó el lote: sale de la cola.
  Future<void> confirmar(Lote lote) async {
    for (final r in lote.resumenes) {
      // Solo se borra si nadie lo pisó mientras se subía.
      if (identical(_resumenes[r['fecha']], r)) _resumenes.remove(r['fecha']);
    }
    for (final r in lote.registros) {
      final ts = r['ts'] as String;
      _registros.remove(ts);
      final t = DateTime.parse(ts);
      if (_ultimoRegistroSubido == null || t.isAfter(_ultimoRegistroSubido!)) _ultimoRegistroSubido = t;
    }
    _ultimaSubida = DateTime.now();
    await _guardar();
  }

  Future<void> vaciar() async {
    _resumenes.clear();
    _registros.clear();
    _ultimoRegistroSubido = null;
    _ultimoDiaCerrado = null;
    _ultimaSubida = null;
    await _almacen.borrar(_clave);
  }
}
