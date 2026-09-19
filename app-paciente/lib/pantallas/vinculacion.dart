import 'package:flutter/material.dart';

import '../subida/sincronizador.dart';
import '../vinculacion/vinculacion.dart';
import 'escanear_qr.dart';

/// Estado de la vinculación con el médico y del envío de datos.
/// No muestra ningún valor de carga: solo fechas, cantidades y el estado.
class PantallaVinculacion extends StatelessWidget {
  final ControladorVinculacion vinculacion;
  final Sincronizador? sincronizador;

  const PantallaVinculacion({super.key, required this.vinculacion, this.sincronizador});

  Future<void> _escanear(BuildContext context) async {
    final datos = await Navigator.of(context).push<DatosQr>(
      MaterialPageRoute(builder: (_) => const PantallaEscanearQr()),
    );
    if (datos != null) await vinculacion.vincular(datos);
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
    final s = sincronizador;
    return Scaffold(
      appBar: AppBar(title: const Text('Mi médico')),
      body: ListenableBuilder(
        listenable: s == null ? vinculacion : Listenable.merge([vinculacion, s]),
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
              if (s != null && s.equipoAjeno) ...[
                const SizedBox(height: 16),
                const _Tarjeta(
                  icono: Icons.error_outline,
                  titulo: 'Esta no es tu ortesis',
                  detalle: 'La ortesis que está cerca pertenece a otro tratamiento, así que no se envía '
                      'nada de lo que tiene adentro. Alejate de otras ortesis y volvé a intentar.',
                  destacada: true,
                ),
              ],
              if (s != null && v != null) ...[
                const SizedBox(height: 16),
                _EstadoEnvio(s: s),
              ],
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

class _EstadoEnvio extends StatelessWidget {
  final Sincronizador s;
  const _EstadoEnvio({required this.s});

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final dias = s.diasPendientes;
    final String estado;
    if (!s.servidorConfigurado) {
      estado = 'Versión de prueba sin servidor: los datos quedan guardados en el celular.';
    } else if (s.subiendo) {
      estado = 'Enviando…';
    } else if (s.ultimoError != null) {
      estado = 'No se pudo enviar (${s.ultimoError}). Se vuelve a intentar solo.';
    } else if (dias == 0) {
      estado = 'Todo enviado.';
    } else {
      estado = 'Se envía cuando haya conexión.';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Envío a tu médico', style: texto.titleMedium),
            const SizedBox(height: 8),
            _Fila('Días pendientes de enviar', '$dias'),
            _Fila('Último envío', s.ultimaSubida == null ? 'todavía ninguno' : fechaCorta(s.ultimaSubida!)),
            const SizedBox(height: 8),
            Row(children: [
              if (s.subiendo) ...[
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(estado, style: texto.bodySmall)),
            ]),
            if (s.servidorConfigurado)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: s.subiendo ? null : s.subirAhora, child: const Text('Enviar ahora')),
              ),
          ],
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  final String clave;
  final String valor;
  const _Fila(this.clave, this.valor);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [Expanded(child: Text(clave)), Text(valor, style: Theme.of(context).textTheme.bodyLarge)]),
      );
}
