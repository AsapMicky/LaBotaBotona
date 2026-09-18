// Persistencia clave-valor del teléfono. La usan la vinculación (token del QR) y la
// cola de subida. Está abstraída para poder testear sin plugins.
import 'package:shared_preferences/shared_preferences.dart';

abstract class Almacen {
  Future<String?> leer(String clave);
  Future<void> escribir(String clave, String valor);
  Future<void> borrar(String clave);
}

/// En memoria: para tests y para el modo simulado si hiciera falta.
class AlmacenMemoria implements Almacen {
  final Map<String, String> _datos = {};

  @override
  Future<String?> leer(String clave) async => _datos[clave];
  @override
  Future<void> escribir(String clave, String valor) async => _datos[clave] = valor;
  @override
  Future<void> borrar(String clave) async => _datos.remove(clave);
}

/// En el teléfono, con shared_preferences.
class AlmacenPreferencias implements Almacen {
  Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  @override
  Future<String?> leer(String clave) async => (await _p).getString(clave);
  @override
  Future<void> escribir(String clave, String valor) async {
    await (await _p).setString(clave, valor);
  }

  @override
  Future<void> borrar(String clave) async {
    await (await _p).remove(clave);
  }
}
