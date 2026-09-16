// Decodificación de paquetes BLE. Fuente de verdad: docs/protocolo-ble.md
import 'dart:typed_data';

const String uuidServicio = '6f1a0000-8b3c-4d5e-9a10-2c7e5b3d9f00';
String uuidCaracteristica(int n) =>
    '6f1a${n.toRadixString(16).padLeft(4, '0')}-8b3c-4d5e-9a10-2c7e5b3d9f00';

final String uuidEstado = uuidCaracteristica(1);
final String uuidResumen = uuidCaracteristica(2);
final String uuidHistCtrl = uuidCaracteristica(3);
final String uuidHistDatos = uuidCaracteristica(4);
final String uuidConfig = uuidCaracteristica(5);
final String uuidHora = uuidCaracteristica(6);
final String uuidInfo = uuidCaracteristica(7);

const int versionProtocolo = 1;
const int seqFin = 0xFFFF;

enum Regimen { sinApoyo, subcarga, ventana, exceso }

ByteData _bd(List<int> b) => Uint8List.fromList(b).buffer.asByteData();

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

  factory EstadoVivo.desdeBytes(List<int> b) {
    if (b.length < 8) throw FormatException('Estado: se esperaban 8 bytes, llegaron ${b.length}');
    if (b[0] != versionProtocolo) throw FormatException('Versión de protocolo ${b[0]} no soportada');
    final d = _bd(b);
    final flags = b[5];
    final cumpl = d.getUint16(6, Endian.little);
    return EstadoVivo(
      regimen: Regimen.values[b[1].clamp(0, 3)],
      excedenciasHoy: d.getUint16(2, Endian.little),
      bateria: b[4],
      cargando: flags & 0x01 != 0,
      limitePendiente: flags & 0x02 != 0,
      sinHora: flags & 0x04 != 0,
      sinEpisodio: flags & 0x08 != 0,
      cumplimientoHoy: cumpl == 0xFFFF ? null : cumpl / 10.0,
    );
  }
}

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

  factory ResumenDiario.desdeBytes(List<int> b) {
    if (b.length < 28) throw FormatException('Resumen: se esperaban 28 bytes');
    final d = _bd(b);
    return ResumenDiario(
      inicioDia: DateTime.fromMillisecondsSinceEpoch(d.getUint32(0, Endian.little) * 1000, isUtc: true),
      dosisSobrecarga: d.getFloat32(4, Endian.little),
      dosisSubcarga: d.getFloat32(8, Endian.little),
      tCarga: d.getUint32(12, Endian.little),
      tExceso: d.getUint32(16, Endian.little),
      tSub: d.getUint32(20, Endian.little),
      pico: d.getUint16(24, Endian.little) / 10.0,
      excedencias: d.getUint16(26, Endian.little),
    );
  }

  Map<String, Object> aJson() => {
        'fecha': inicioDia.toLocal().toIso8601String().substring(0, 10),
        'dosis_sobrecarga': dosisSobrecarga,
        'dosis_subcarga': dosisSubcarga,
        't_carga_s': tCarga,
        't_exceso_s': tExceso,
        't_sub_s': tSub,
        'pico': pico,
        'excedencias': excedencias,
      };
}

class RegistroMinuto {
  final DateTime ts;
  final double cargaMedia;
  final double cargaPico;
  final double dosis;
  final int excedencias;
  final int segApoyo;

  const RegistroMinuto(this.ts, this.cargaMedia, this.cargaPico, this.dosis, this.excedencias, this.segApoyo);

  static const tamanio = 12;

  factory RegistroMinuto.desdeBytes(ByteData d, int o) => RegistroMinuto(
        DateTime.fromMillisecondsSinceEpoch(d.getUint32(o, Endian.little) * 1000, isUtc: true),
        d.getUint16(o + 4, Endian.little) / 10.0,
        d.getUint16(o + 6, Endian.little) / 10.0,
        d.getUint16(o + 8, Endian.little) / 100.0,
        d.getUint8(o + 10),
        d.getUint8(o + 11) * 4,
      );

  Map<String, Object> aJson() => {
        'ts': ts.toIso8601String(),
        'carga_media': cargaMedia,
        'carga_pico': cargaPico,
        'dosis': dosis,
        'excedencias': excedencias,
        'seg_apoyo': segApoyo,
      };
}

/// Paquete de historial: (secuencia, registros). secuencia == seqFin marca el final.
(int, List<RegistroMinuto>) decodificarPaqueteHistorial(List<int> b) {
  final d = _bd(b);
  final seq = d.getUint16(0, Endian.little);
  final n = (b.length - 2) ~/ RegistroMinuto.tamanio;
  return (seq, [for (var i = 0; i < n; i++) RegistroMinuto.desdeBytes(d, 2 + i * RegistroMinuto.tamanio)]);
}

List<int> codificarPedidoHistorial(DateTime desde) {
  final d = ByteData(5)
    ..setUint8(0, 1)
    ..setUint32(1, desde.millisecondsSinceEpoch ~/ 1000, Endian.little);
  return d.buffer.asUint8List();
}

List<int> codificarHora(DateTime ahora) {
  final d = ByteData(6)
    ..setUint32(0, ahora.toUtc().millisecondsSinceEpoch ~/ 1000, Endian.little)
    ..setInt16(4, ahora.timeZoneOffset.inMinutes, Endian.little);
  return d.buffer.asUint8List();
}
