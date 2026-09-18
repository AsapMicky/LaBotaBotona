import 'package:flutter/material.dart';

import '../vinculacion/vinculacion.dart';
import 'escanear_qr.dart';

/// Estado de la vinculación con el médico.
/// No muestra ningún valor de carga: solo fechas y el estado.
class PantallaVinculacion extends StatelessWidget {
  final ControladorVinculacion vinculacion;

  const PantallaVinculacion({super.key, required this.vinculacion});

  Future<void> _escanear(BuildContext context) async {
    final token = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const PantallaEscanearQr()),
    );
    if (token != null) await vinculacion.vincular(token);
  }

  Future<void> _desvincular(BuildContext context) async {
    final seguro = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Desvincular la app?'),
        content: const Text('Tu médico va a dejar de recibir los datos hasta que vuelvas a escanear el código. '
            'La ortesis sigue registrando igual.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Desvincular')),
        ],
      ),
    );
    if (seguro ?? false) await vinculacion.desvincular();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi médico')),
      body: ListenableBuilder(
        listenable: vinculacion,
        builder: (context, _) {
          final texto = Theme.of(context).textTheme;
          final v = vinculacion.actual;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              switch (vinculacion.estado) {
                EstadoVinculacion.sinVincular => const _Tarjeta(
                    icono: Icons.qr_code_scanner,
                    titulo: 'Todavía no está vinculada',
                    detalle: 'Escaneá el código QR que te muestra tu médico para que reciba lo que registra la ortesis. '
                        'No hace falta crear una cuenta.',
                  ),
                EstadoVinculacion.vinculada => _Tarjeta(
                    icono: Icons.verified_outlined,
                    titulo: 'Vinculada con tu médico',
                    detalle: 'Desde el ${fechaCorta(v!.desde)}. Lo que registra la ortesis se le envía cuando el celular tiene conexión.',
                  ),
                EstadoVinculacion.revocada => const _Tarjeta(
                    icono: Icons.link_off,
                    titulo: 'El tratamiento fue cerrado',
                    detalle: 'Tu médico dio por terminado este tratamiento. Si empezás uno nuevo, escaneá el código nuevo.',
                    destacada: true,
                  ),
              },
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _escanear(context),
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(v == null ? 'Escanear el código' : 'Escanear otro código'),
              ),
              if (v != null) ...[
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () => _desvincular(context), child: const Text('Desvincular')),
              ],
              const SizedBox(height: 24),
              Text(
                'Esta app no guarda tu nombre ni tu documento: solo un código del tratamiento.',
                style: texto.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// "18 de septiembre", en hora local.
String fechaCorta(DateTime d) {
  const meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
  final l = d.toLocal();
  return '${l.day} de ${meses[l.month - 1]}';
}

class _Tarjeta extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String detalle;
  final bool destacada;
  const _Tarjeta({required this.icono, required this.titulo, required this.detalle, this.destacada = false});

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Card(
      color: destacada ? esquema.secondaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icono, size: 28),
              const SizedBox(width: 12),
              Expanded(child: Text(titulo, style: Theme.of(context).textTheme.titleMedium)),
            ]),
            const SizedBox(height: 8),
            Text(detalle),
          ],
        ),
      ),
    );
  }
}
