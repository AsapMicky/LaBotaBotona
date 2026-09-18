// Cliente HTTP de la función `subir-datos` (backend/supabase/functions/subir-datos).
// El token del QR viaja en el cuerpo; la función lo valida y escribe con service-role.
// La app nunca habla con la base directamente.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

sealed class RespuestaSubida {
  const RespuestaSubida();
}

class SubidaOk extends RespuestaSubida {
  final int resumenes;
  final int registros;
  const SubidaOk({required this.resumenes, required this.registros});
}

/// El servidor no reconoce el token o el médico cerró el episodio.
class EpisodioCerrado extends RespuestaSubida {
  const EpisodioCerrado();
}

class SubidaFallida extends RespuestaSubida {
  final String motivo;

  /// true: vale la pena volver a intentar más tarde (sin red, servidor caído).
  final bool reintentable;
  const SubidaFallida(this.motivo, {required this.reintentable});
}

class ClienteSubirDatos {
  final Uri url;
  final http.Client _http;
  final String? _anonKey;

  /// [urlBase] es la URL del proyecto (`https://xxxx.supabase.co`) o de un servidor
  /// local para pruebas. [anonKey] solo hace falta si la función se desplegó con
  /// verificación de JWT; el backend la despliega con `--no-verify-jwt`.
  ClienteSubirDatos(String urlBase, {http.Client? cliente, String? anonKey})
      : url = Uri.parse('${urlBase.replaceAll(RegExp(r'/+$'), '')}/functions/v1/subir-datos'),
        _http = cliente ?? http.Client(),
        _anonKey = anonKey;

  Future<RespuestaSubida> subir({
    required String token,
    List<Map<String, Object>> resumenes = const [],
    List<Map<String, Object>> registros = const [],
  }) async {
    final http.Response r;
    try {
      r = await _http
          .post(
            url,
            headers: {
              'content-type': 'application/json',
              if (_anonKey != null) 'apikey': _anonKey,
              if (_anonKey != null) 'authorization': 'Bearer $_anonKey',
            },
            body: jsonEncode({'token': token, 'resumenes': resumenes, 'registros': registros}),
          )
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      return const SubidaFallida('el servidor no respondió', reintentable: true);
    } on SocketException {
      return const SubidaFallida('sin conexión', reintentable: true);
    } on http.ClientException catch (e) {
      return SubidaFallida(e.message, reintentable: true);
    }

    if (r.statusCode == 200) {
      try {
        final m = jsonDecode(r.body) as Map<String, dynamic>;
        return SubidaOk(resumenes: (m['resumenes'] ?? 0) as int, registros: (m['registros'] ?? 0) as int);
      } catch (_) {
        return const SubidaOk(resumenes: 0, registros: 0);
      }
    }
    // La función contesta 404 "Episodio inexistente o cerrado". Otro 404 es una URL mal puesta.
    if (r.statusCode == 404 && r.body.toLowerCase().contains('episodio')) return const EpisodioCerrado();
    if (r.statusCode >= 500) return SubidaFallida('error del servidor (${r.statusCode})', reintentable: true);
    return SubidaFallida('HTTP ${r.statusCode}: ${r.body.length > 120 ? r.body.substring(0, 120) : r.body}',
        reintentable: false);
  }

  void cerrar() => _http.close();
}
