// Vectores de referencia compartidos con el firmware (docs/protocolo-vectores.json).
// La app DECODIFICA: toma los bytes del archivo y compara con los valores esperados.
// El firmware hace lo inverso en firmware/test/test_protocolo. Un byte corrido
// rompe los dos lados.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dosimetro_paciente/dispositivo/codec_ble.dart';
import 'package:dosimetro_paciente/dispositivo/modelo.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _cargarVectores() {
  // flutter test corre con el cwd en app-paciente/; el archivo está un nivel arriba.
  for (final ruta in ['../docs/protocolo-vectores.json', 'docs/protocolo-vectores.json']) {
    final f = File(ruta);
    if (f.existsSync()) return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  }
  throw StateError('no encontré docs/protocolo-vectores.json');
}

List<int> _desdeHexa(String h) =>
    h.trim().split(RegExp(r'\s+')).map((x) => int.parse(x, radix: 16)).toList();

/// Compara con la tolerancia que corresponde a un float32 del equipo.
Matcher _cerca(num v) => closeTo(v, v.abs() * 1e-6 + 1e-6);

void main() {
  final vec = _cargarVectores();

  test('versión del protocolo', () {
    expect(vec['version_protocolo'], versionProtocolo);
  });

  group('estado en vivo', () {
    for (final v in vec['estado'] as List) {
      test(v['nombre'], () {
        final esp = v['esperado'] as Map<String, dynamic>;
        final e = decodificarEstado(_desdeHexa(v['bytes']));
        expect(e.regimen, Regimen.values[esp['regimen'] as int]);
        expect(e.excedenciasHoy, esp['excedencias_hoy']);
        expect(e.bateria, esp['bateria']);
        expect(e.cargando, esp['cargando']);
        expect(e.limitePendiente, esp['limite_pendiente']);
        expect(e.sinHora, esp['sin_hora']);
        expect(e.sinEpisodio, esp['sin_episodio']);
        final c = esp['cumplimiento_hoy'];
        expect(e.cumplimientoHoy, c == null ? isNull : _cerca(c as num));
      });
    }
  });

  void compararResumen(ResumenDiario r, Map<String, dynamic> esp) {
    expect(r.inicioDia.millisecondsSinceEpoch ~/ 1000, esp['inicio_dia']);
    expect(r.inicioDia.isUtc, isTrue);
    expect(r.dosisSobrecarga, _cerca(esp['dosis_sobrecarga'] as num));
    expect(r.dosisSubcarga, _cerca(esp['dosis_subcarga'] as num));
    expect(r.tCarga, esp['t_carga_s']);
    expect(r.tExceso, esp['t_exceso_s']);
    expect(r.tSub, esp['t_sub_s']);
    expect(r.pico, _cerca(esp['pico'] as num));
    expect(r.excedencias, esp['excedencias']);
    expect(r.tVentana, esp['t_ventana_s']);
    final c = esp['cumplimiento'];
    expect(r.cumplimiento, c == null ? isNull : _cerca(c as num));
    final p = esp['permanencia'];
    expect(r.permanencia, p == null ? isNull : _cerca(p as num));
  }

  group('resumen del día', () {
    for (final v in vec['resumen'] as List) {
      test(v['nombre'], () {
        final b = _desdeHexa(v['bytes']);
        expect(b, hasLength(tamResumen));
        compararResumen(decodificarResumen(b), v['esperado'] as Map<String, dynamic>);
      });
    }
  });

  group('paquete de resúmenes de días cerrados', () {
    final porNombre = {for (final r in vec['resumen'] as List) r['nombre'] as String: r['esperado']};
    for (final v in vec['paquete_resumenes'] as List) {
      test(v['nombre'], () {
        final esp = v['esperado'] as Map<String, dynamic>;
        final (seq, resumenes) = decodificarPaqueteResumenes(_desdeHexa(v['bytes']));
        expect(seq, esp['secuencia']);
        expect(resumenes, hasLength(esp['cantidad'] as int));
        if (seq == seqFin) expect(resumenes, isEmpty);
        for (var i = 0; i < resumenes.length; i++) {
          compararResumen(resumenes[i], porNombre[esp['resumenes'][i]] as Map<String, dynamic>);
        }
      });
    }
  });

  group('pedido de resúmenes (la app codifica)', () {
    for (final v in vec['pedido_resumenes'] as List) {
      test(v['nombre'], () {
        final desde = DateTime.fromMillisecondsSinceEpoch((v['desde'] as int) * 1000, isUtc: true);
        expect(codificarPedidoResumenes(desde), _desdeHexa(v['bytes']));
      });
    }
  });

  void compararRegistro(RegistroMinuto r, Map<String, dynamic> esp) {
    expect(r.ts.millisecondsSinceEpoch ~/ 1000, esp['ts']);
    expect(r.cargaMedia, _cerca(esp['carga_media'] as num));
    expect(r.cargaPico, _cerca(esp['carga_pico'] as num));
    expect(r.dosis, _cerca(esp['dosis'] as num));
    expect(r.excedencias, esp['excedencias']);
    expect(r.segApoyo, esp['seg_apoyo']);
  }

  group('registro por minuto', () {
    for (final v in vec['registro'] as List) {
      test(v['nombre'], () {
        final b = _desdeHexa(v['bytes']);
        expect(b, hasLength(tamRegistro));
        final d = ByteData.sublistView(Uint8List.fromList(b));
        compararRegistro(decodificarRegistro(d, 0), v['esperado'] as Map<String, dynamic>);
      });
    }
  });

  group('paquete de historial', () {
    final registros = {for (final r in vec['registro'] as List) r['nombre'] as String: r['esperado']};
    for (final v in vec['paquete_historial'] as List) {
      test(v['nombre'], () {
        final esp = v['esperado'] as Map<String, dynamic>;
        final (seq, regs) = decodificarPaqueteHistorial(_desdeHexa(v['bytes']));
        expect(seq, esp['secuencia']);
        expect(regs, hasLength(esp['cantidad'] as int));
        if (seq == seqFin) expect(regs, isEmpty);
        for (var i = 0; i < regs.length; i++) {
          compararRegistro(regs[i], registros[esp['registros'][i]] as Map<String, dynamic>);
        }
      });
    }
  });

  group('pedido de historial (la app codifica)', () {
    for (final v in vec['pedido_historial'] as List) {
      test(v['nombre'], () {
        final desde = DateTime.fromMillisecondsSinceEpoch((v['desde'] as int) * 1000, isUtc: true);
        expect(codificarPedidoHistorial(desde), _desdeHexa(v['bytes']));
      });
    }
  });

  group('hora (la app codifica)', () {
    for (final v in vec['hora'] as List) {
      test(v['nombre'], () {
        // codificarHora usa el huso del teléfono; acá se codifica a mano con el offset del vector
        // para que el test no dependa de la zona horaria de la máquina.
        final epoch = v['epoch'] as int;
        final d = ByteData(6)
          ..setUint32(0, epoch, Endian.little)
          ..setInt16(4, v['offset_min'] as int, Endian.little);
        expect(d.buffer.asUint8List(), _desdeHexa(v['bytes']));
        // Y lo que sí es independiente del huso: el epoch que escribe codificarHora.
        final b = codificarHora(DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true));
        expect(ByteData.sublistView(Uint8List.fromList(b)).getUint32(0, Endian.little), epoch);
      });
    }
  });
}
