import 'package:flutter/material.dart';

import 'dispositivo/protocolo.dart';

// Paleta del grupo (presentación del anteproyecto)
const petroleo = Color(0xFF0B3B47);
const menta = Color(0xFF36C9B0);
// El exceso va en ámbar, no en rojo: la cátedra pidió un color menos alarmante.
const ambar = Color(0xFFE39B3B);
const celeste = Color(0xFF6E9FC4);
const gris = Color(0xFF9AA7AB);

ThemeData temaApp() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: petroleo, secondary: menta),
    );

class VistaRegimen {
  final Color color;
  final IconData icono;
  final String titulo;
  final String detalle;
  const VistaRegimen(this.color, this.icono, this.titulo, this.detalle);

  static VistaRegimen de(Regimen r) => switch (r) {
        Regimen.ventana => const VistaRegimen(menta, Icons.check, 'Vas bien', 'Estás apoyando como te indicaron.'),
        Regimen.exceso => const VistaRegimen(
            ambar, Icons.south, 'Apoyá con menos peso', 'Pasá más peso a las muletas o a la otra pierna.'),
        Regimen.subcarga => const VistaRegimen(
            celeste, Icons.north, 'Podés apoyar un poco más', 'Tu médico indicó que cargues algo más de peso.'),
        Regimen.sinApoyo => const VistaRegimen(gris, Icons.pause, 'Sin apoyo', 'La ortesis sigue registrando.'),
      };
}
