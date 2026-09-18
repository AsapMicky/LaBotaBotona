// Modelo de datos del equipo, independiente del transporte (docs/decisiones/005).
// Estas clases son las mismas viajen como bytes por BLE (ver codec_ble.dart) o como
// JSON hacia Supabase (aJson). No hay una segunda definición del dato en ningún lado.

enum Regimen { sinApoyo, subcarga, ventana, exceso }

/// Lo que el equipo publica a 1 Hz. No incluye la carga instantánea a propósito:
/// el paciente no la ve.
class EstadoVivo {
  final Regimen regimen;
  final int excedenciasHoy;
  final int bateria;
  final bool cargando;
  final bool limitePendiente;
  final bool sinHora;
  final bool sinEpisodio;

  /// null si todavía no apoyó hoy.
  final double? cumplimientoHoy;

  const EstadoVivo({
    required this.regimen,
    required this.excedenciasHoy,
    required this.bateria,
    this.cargando = false,
    this.limitePendiente = false,
    this.sinHora = false,
    this.sinEpisodio = false,
    this.cumplimientoHoy,
  });
}

/// Resumen del día (Anexo A). Los índices se derivan acá, no en el equipo.
class ResumenDiario {
  final DateTime inicioDia;
  final double dosisSobrecarga;
  final double dosisSubcarga;
  final int tCarga;
  final int tExceso;
  final int tSub;
  final double pico;
  final int excedencias;

  const ResumenDiario({
    required this.inicioDia,
    required this.dosisSobrecarga,
    required this.dosisSubcarga,
    required this.tCarga,
    required this.tExceso,
    required this.tSub,
    required this.pico,
    required this.excedencias,
  });

  int get tVentana => tCarga - tExceso - tSub;
  double? get cumplimiento => tCarga > 0 ? (1 - tExceso / tCarga) * 100 : null;
  double? get permanencia => tCarga > 0 ? tVentana / tCarga * 100 : null;

  /// Fecha local del resumen, `AAAA-MM-DD`. Es la clave del upsert en Supabase.
  String get fecha => inicioDia.toLocal().toIso8601String().substring(0, 10);

  /// Mismas columnas que `resumenes_diarios` (backend/supabase/migrations).
  Map<String, Object> aJson() => {
        'fecha': fecha,
        'dosis_sobrecarga': dosisSobrecarga,
        'dosis_subcarga': dosisSubcarga,
        't_carga_s': tCarga,
        't_exceso_s': tExceso,
        't_sub_s': tSub,
        'pico': pico,
        'excedencias': excedencias,
      };
}

/// Registro por minuto del historial.
class RegistroMinuto {
  final DateTime ts;
  final double cargaMedia;
  final double cargaPico;
  final double dosis;
  final int excedencias;
  final int segApoyo;

  const RegistroMinuto(this.ts, this.cargaMedia, this.cargaPico, this.dosis, this.excedencias, this.segApoyo);

  /// Mismas columnas que `registros_minuto` (backend/supabase/migrations).
  Map<String, Object> aJson() => {
        'ts': ts.toIso8601String(),
        'carga_media': cargaMedia,
        'carga_pico': cargaPico,
        'dosis': dosis,
        'excedencias': excedencias,
        'seg_apoyo': segApoyo,
      };
}
