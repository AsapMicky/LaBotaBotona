// Codificación BLE del modelo. Fuente de verdad: docs/protocolo-ble.md
// Todo lo que sabe de bytes, offsets y UUIDs vive acá; el modelo (modelo.dart) no.
import 'dart:typed_data';

import 'modelo.dart';

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
final String uuidResumenes = uuidCaracteristica(8);

const int versionProtocolo = 1;
const int seqFin = 0xFFFF;

const int tamEstado = 8;
const int tamResumen = 28;
const int tamRegistro = 12;

/// Operaciones de la característica de control (0003).
const int opHistorial = 1;
const int opCancelar = 2;
const int opResumenes = 3;

ByteData _bd(List<int> b) => Uint8List.fromList(b).buffer.asByteData();

/// 0001 · Estado en vivo (8 B).
EstadoVivo decodificarEstado(List<int> b) {
  if (b.length < tamEstado) {
    throw FormatException('Estado: se esperaban $tamEstado bytes, llegaron ${b.length}');
  }
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

/// 0002 · Resumen del día (28 B).
ResumenDiario decodificarResumen(List<int> b) {
  if (b.length < tamResumen) throw const FormatException('Resumen: se esperaban 28 bytes');
  return decodificarResumenEn(_bd(b), 0);
}

/// Un resumen de 28 B a partir del offset [o]. Lo usan 0002 y los paquetes de 0008.
ResumenDiario decodificarResumenEn(ByteData d, int o) => ResumenDiario(
      inicioDia: DateTime.fromMillisecondsSinceEpoch(d.getUint32(o, Endian.little) * 1000, isUtc: true),
      dosisSobrecarga: d.getFloat32(o + 4, Endian.little),
      dosisSubcarga: d.getFloat32(o + 8, Endian.little),
      tCarga: d.getUint32(o + 12, Endian.little),
      tExceso: d.getUint32(o + 16, Endian.little),
      tSub: d.getUint32(o + 20, Endian.little),
      pico: d.getUint16(o + 24, Endian.little) / 10.0,
      excedencias: d.getUint16(o + 26, Endian.little),
    );

/// Registro por minuto (12 B) a partir del offset [o].
RegistroMinuto decodificarRegistro(ByteData d, int o) => RegistroMinuto(
      DateTime.fromMillisecondsSinceEpoch(d.getUint32(o, Endian.little) * 1000, isUtc: true),
      d.getUint16(o + 4, Endian.little) / 10.0,
      d.getUint16(o + 6, Endian.little) / 10.0,
      d.getUint16(o + 8, Endian.little) / 100.0,
      d.getUint8(o + 10),
      d.getUint8(o + 11) * 4,
    );

/// 0004 · Paquete de historial: (secuencia, registros). secuencia == seqFin marca el final.
(int, List<RegistroMinuto>) decodificarPaqueteHistorial(List<int> b) {
  if (b.length < 2) throw const FormatException('Historial: paquete vacío');
  final d = _bd(b);
  final seq = d.getUint16(0, Endian.little);
  final n = (b.length - 2) ~/ tamRegistro;
  return (seq, [for (var i = 0; i < n; i++) decodificarRegistro(d, 2 + i * tamRegistro)]);
}

/// 0008 · Paquete de resúmenes de días cerrados: (secuencia, resúmenes).
/// Mismo armado que 0004, con registros de 28 B. secuencia == seqFin marca el final.
(int, List<ResumenDiario>) decodificarPaqueteResumenes(List<int> b) {
  if (b.length < 2) throw const FormatException('Resúmenes: paquete vacío');
  final d = _bd(b);
  final seq = d.getUint16(0, Endian.little);
  final n = (b.length - 2) ~/ tamResumen;
  return (seq, [for (var i = 0; i < n; i++) decodificarResumenEn(d, 2 + i * tamResumen)]);
}

/// 0003 · Pedido de descarga (5 B): `u8 op` + `u32 desde`.
List<int> _codificarPedido(int op, DateTime desde) {
  final d = ByteData(5)
    ..setUint8(0, op)
    ..setUint32(1, desde.toUtc().millisecondsSinceEpoch ~/ 1000, Endian.little);
  return d.buffer.asUint8List();
}

/// Registros por minuto con `ts ≥ desde`.
List<int> codificarPedidoHistorial(DateTime desde) => _codificarPedido(opHistorial, desde);

/// Resúmenes de días ya cerrados con `inicio del día ≥ desde`.
List<int> codificarPedidoResumenes(DateTime desde) => _codificarPedido(opResumenes, desde);

/// 0006 · Hora (6 B): epoch UTC + offset local en minutos.
List<int> codificarHora(DateTime ahora) {
  final d = ByteData(6)
    ..setUint32(0, ahora.toUtc().millisecondsSinceEpoch ~/ 1000, Endian.little)
    ..setInt16(4, ahora.timeZoneOffset.inMinutes, Endian.little);
  return d.buffer.asUint8List();
}
