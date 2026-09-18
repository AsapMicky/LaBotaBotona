import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../vinculacion/vinculacion.dart';

/// Lee el QR que muestra la web del médico y devuelve el token con `Navigator.pop`.
/// Abajo hay un campo para pegar el código a mano: sirve en el emulador, que no
/// puede leer un QR de la pantalla, y si la cámara del celular no anda.
class PantallaEscanearQr extends StatefulWidget {
  const PantallaEscanearQr({super.key});

  @override
  State<PantallaEscanearQr> createState() => _PantallaEscanearQrState();
}

class _PantallaEscanearQrState extends State<PantallaEscanearQr> {
  final _controlador = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  final _manual = TextEditingController();
  bool _listo = false;
  String? _error;

  @override
  void dispose() {
    _controlador.dispose();
    _manual.dispose();
    super.dispose();
  }

  void _entregar(String? texto) {
    if (_listo || texto == null) return;
    final token = tokenDesdeQr(texto);
    if (token == null) {
      setState(() => _error = 'Ese código no es de esta app. Pedile a tu médico que te muestre el QR del tratamiento.');
      return;
    }
    _listo = true;
    Navigator.of(context).pop(token);
  }

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Vincular con tu médico')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controlador,
                  onDetect: (captura) {
                    for (final b in captura.barcodes) {
                      if (b.rawValue != null) {
                        _entregar(b.rawValue);
                        return;
                      }
                    }
                  },
                  errorBuilder: (context, error) => _SinCamara(error: error),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 24,
                  child: Text(
                    'Apuntá la cámara al código QR que te muestra tu médico.',
                    textAlign: TextAlign.center,
                    style: texto.titleMedium?.copyWith(color: Colors.white, shadows: const [Shadow(blurRadius: 8)]),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Text(_error!, style: texto.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 8),
                ],
                Text('¿No podés escanear? Pegá el código acá:', style: texto.bodyMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manual,
                        decoration: const InputDecoration(hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx', isDense: true),
                        autocorrect: false,
                        onSubmitted: _entregar,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: () => _entregar(_manual.text), child: const Text('Usar')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SinCamara extends StatelessWidget {
  final MobileScannerException error;
  const _SinCamara({required this.error});

  @override
  Widget build(BuildContext context) {
    final permiso = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Container(
      color: Colors.black87,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 48),
          const SizedBox(height: 12),
          Text(
            permiso
                ? 'Sin permiso para usar la cámara. Podés habilitarlo en Ajustes o pegar el código abajo.'
                : 'No se pudo abrir la cámara. Podés pegar el código abajo.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }
}
