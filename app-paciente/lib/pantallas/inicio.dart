import 'package:flutter/material.dart';

import '../dispositivo/dispositivo.dart';
import '../dispositivo/protocolo.dart';
import '../tema.dart';

class PantallaInicio extends StatefulWidget {
  final Dispositivo dispositivo;
  const PantallaInicio({super.key, required this.dispositivo});

  @override
  State<PantallaInicio> createState() => _PantallaInicioState();
}

class _PantallaInicioState extends State<PantallaInicio> {
  EstadoConexion _conexion = EstadoConexion.desconectado;
  EstadoVivo? _estado;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.dispositivo.conexion.listen((c) => setState(() => _conexion = c));
    widget.dispositivo.estado.listen(
      (e) => setState(() => _estado = e),
      onError: (Object e) => setState(() => _error = '$e'),
    );
    _conectar();
  }

  Future<void> _conectar() async {
    setState(() => _error = null);
    try {
      await widget.dispositivo.conectar();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final conectado = _conexion == EstadoConexion.conectado && _estado != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi ortesis'),
        actions: [
          if (conectado) _Bateria(nivel: _estado!.bateria, cargando: _estado!.cargando),
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: conectado ? _vistaConectado(_estado!) : _vistaSinConexion(),
        ),
      ),
    );
  }

  Widget _vistaSinConexion() {
    final buscando = _conexion == EstadoConexion.buscando || _conexion == EstadoConexion.conectando;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (buscando) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(_conexion == EstadoConexion.buscando ? 'Buscando tu ortesis…' : 'Conectando…',
                style: Theme.of(context).textTheme.titleMedium),
          ] else ...[
            Icon(Icons.bluetooth_disabled, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(_error ?? 'La ortesis no está conectada',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Aunque no esté conectada, la ortesis sigue registrando.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: _conectar, icon: const Icon(Icons.bluetooth), label: const Text('Conectar')),
          ],
        ],
      ),
    );
  }

  Widget _vistaConectado(EstadoVivo e) {
    final v = VistaRegimen.de(e.regimen);
    final texto = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (e.limitePendiente)
          const _Aviso(
            icono: Icons.edit_note,
            texto: 'Tu médico cambió la indicación. Mantené apretado el botón de la ortesis 2 segundos para aplicarla.',
          ),
        if (e.sinEpisodio)
          const _Aviso(icono: Icons.info_outline, texto: 'Esta ortesis todavía no fue asignada por tu médico.'),
        const Spacer(),
        Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: 220,
            height: 220,
            decoration: BoxDecoration(shape: BoxShape.circle, color: v.color),
            child: Icon(v.icono, size: 96, color: Colors.white),
          ),
        ),
        const SizedBox(height: 28),
        Text(v.titulo, textAlign: TextAlign.center, style: texto.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(v.detalle, textAlign: TextAlign.center, style: texto.bodyLarge),
        const Spacer(),
        _ResumenHoy(excedencias: e.excedenciasHoy, cumplimiento: e.cumplimientoHoy),
      ],
    );
  }
}

class _ResumenHoy extends StatelessWidget {
  final int excedencias;
  final double? cumplimiento;
  const _ResumenHoy({required this.excedencias, required this.cumplimiento});

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final veces = excedencias == 1 ? 'vez' : 'veces';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hoy', style: texto.titleMedium),
            const SizedBox(height: 8),
            Text(excedencias == 0 ? 'No te pasaste del peso indicado.' : 'Te pasaste del peso indicado $excedencias $veces.',
                style: texto.bodyLarge),
            if (cumplimiento != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: cumplimiento! / 100, minHeight: 10),
              ),
              const SizedBox(height: 6),
              Text('Apoyaste bien el ${cumplimiento!.round()} % del tiempo', style: texto.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final IconData icono;
  final String texto;
  const _Aviso({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: ListTile(leading: Icon(icono), title: Text(texto)),
      );
}

class _Bateria extends StatelessWidget {
  final int nivel;
  final bool cargando;
  const _Bateria({required this.nivel, required this.cargando});

  @override
  Widget build(BuildContext context) {
    final icono = cargando
        ? Icons.battery_charging_full
        : nivel > 60
            ? Icons.battery_full
            : nivel > 20
                ? Icons.battery_4_bar
                : Icons.battery_alert;
    return Row(children: [Icon(icono), const SizedBox(width: 4), Text('$nivel %')]);
  }
}
