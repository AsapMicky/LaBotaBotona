// Protocolo BLE v1 (docs/protocolo-ble.md), partido en dos según docs/decisiones/005:
//   modelo.dart    — las clases y su aJson(); no saben de bytes.
//   codec_ble.dart — UUIDs, tamaños y la lectura/escritura de bytes.
// Este archivo solo reexporta ambos, así los imports existentes siguen andando.
export 'codec_ble.dart';
export 'modelo.dart';
