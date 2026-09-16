import 'package:flutter/material.dart';

import 'dispositivo/dispositivo.dart';
import 'dispositivo/dispositivo_ble.dart';
import 'dispositivo/dispositivo_simulado.dart';
import 'pantallas/inicio.dart';
import 'tema.dart';

// flutter run --dart-define=SIMULADO=false  → usa el equipo real por Bluetooth
const bool simulado = bool.fromEnvironment('SIMULADO', defaultValue: true);

void main() => runApp(const AppPaciente());

class AppPaciente extends StatefulWidget {
  const AppPaciente({super.key});

  @override
  State<AppPaciente> createState() => _AppPacienteState();
}

class _AppPacienteState extends State<AppPaciente> {
  late final Dispositivo _dispositivo = simulado ? DispositivoSimulado() : DispositivoBle();

  @override
  void dispose() {
    _dispositivo.liberar();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Mi ortesis',
        debugShowCheckedModeBanner: simulado,
        theme: temaApp(),
        home: PantallaInicio(dispositivo: _dispositivo),
      );
}
