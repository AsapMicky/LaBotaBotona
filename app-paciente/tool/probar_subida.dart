// Prueba la subida contra la función `subir-datos` usando el mismo cliente que la app,
// pero desde la PC: sirve para verificar el backend sin compilar para Android.
//
//   cd app-paciente
//   dart run tool/probar_subida.dart <URL_DE_SUPABASE> <TOKEN_DEL_QR>
//
// Sube un resumen de ayer con valores de ejemplo. Es idempotente: correrlo dos veces
// no duplica nada (el servidor hace upsert por episodio y fecha).
import 'dart:io';

import 'package:dosimetro_paciente/dispositivo/modelo.dart';
import 'package:dosimetro_paciente/subida/cliente_subir_datos.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('Uso: dart run tool/probar_subida.dart <URL_DE_SUPABASE> <TOKEN_DEL_QR>');
    exit(64);
  }
  final cliente = ClienteSubirDatos(args[0]);
  final ayer = DateTime.now().toUtc().subtract(const Duration(days: 1));
  final inicioDia = DateTime.utc(ayer.year, ayer.month, ayer.day, 3); // 00:00 de Argentina

  final resumen = ResumenDiario(
    inicioDia: inicioDia,
    dosisSobrecarga: 37.5,
    dosisSubcarga: 4.2,
    tCarga: 6300,
    tExceso: 480,
    tSub: 900,
    pico: 33.4,
    excedencias: 6,
  );
  final registros = [
    for (var i = 0; i < 60; i++)
      RegistroMinuto(inicioDia.add(Duration(hours: 10, minutes: i)), 17.5, 28.0, i.isEven ? 0.4 : 0, i % 10 == 0 ? 1 : 0, 45),
  ];

  stdout.writeln('POST ${cliente.url}');
  final r = await cliente.subir(
    token: args[1],
    resumenes: [resumen.aJson()],
    registros: [for (final x in registros) x.aJson()],
  );
  switch (r) {
    case SubidaOk(:final resumenes, :final registros):
      stdout.writeln('OK: $resumenes resúmenes, $registros registros');
    case EpisodioCerrado():
      stderr.writeln('El episodio no existe o está cerrado.');
      exit(1);
    case SubidaFallida(:final motivo, :final reintentable):
      stderr.writeln('Falló: $motivo (reintentable: $reintentable)');
      exit(1);
  }
  cliente.cerrar();
}
