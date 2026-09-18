import 'package:flutter/material.dart';

import 'almacen/almacen.dart';
import 'dispositivo/dispositivo.dart';
import 'dispositivo/dispositivo_ble.dart';
import 'dispositivo/dispositivo_simulado.dart';
import 'pantallas/inicio.dart';
import 'subida/cliente_subir_datos.dart';
import 'subida/cola_subida.dart';
import 'subida/sincronizador.dart';
import 'tema.dart';
import 'vinculacion/vinculacion.dart';

// flutter run --dart-define=SIMULADO=false  → usa el equipo real por Bluetooth
const bool simulado = bool.fromEnvironment('SIMULADO', defaultValue: true);

// flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co  → sube a subir-datos.
// Sin URL, la app guarda todo en el celular y no sube nada (útil para diseñar).
// Para probar contra el servidor falso: --dart-define=SUPABASE_URL=http://10.0.2.2:8787
const String urlSupabase = String.fromEnvironment('SUPABASE_URL');
const String claveAnonSupabase = String.fromEnvironment('SUPABASE_ANON_KEY');

void main() => runApp(const AppPaciente());

class AppPaciente extends StatefulWidget {
  const AppPaciente({super.key});

  @override
  State<AppPaciente> createState() => _AppPacienteState();
}

class _AppPacienteState extends State<AppPaciente> {
  final _almacen = AlmacenPreferencias();
  late final Dispositivo _dispositivo = simulado ? DispositivoSimulado() : DispositivoBle();
  late final ControladorVinculacion _vinculacion = ControladorVinculacion(_almacen);
  late final Sincronizador _sincronizador = Sincronizador(
    dispositivo: _dispositivo,
    cola: ColaSubida(_almacen),
    vinculacion: _vinculacion,
    cliente: urlSupabase.isEmpty
        ? null
        : ClienteSubirDatos(urlSupabase, anonKey: claveAnonSupabase.isEmpty ? null : claveAnonSupabase),
  );

  @override
  void initState() {
    super.initState();
    // El sincronizador primero: deja puestas las suscripciones antes de que el equipo
    // se conecte o termine de leerse la vinculación, así no se pierde ningún evento.
    _sincronizador.iniciar();
    _vinculacion.cargar();
  }

  @override
  void dispose() {
    _sincronizador.dispose();
    _dispositivo.liberar();
    _vinculacion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mi ortesis',
        debugShowCheckedModeBanner: simulado,
        theme: temaApp(),
        home: PantallaInicio(dispositivo: _dispositivo, vinculacion: _vinculacion, sincronizador: _sincronizador),
      );
}
