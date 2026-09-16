import 'protocolo.dart';

enum EstadoConexion { desconectado, buscando, conectando, conectado }

/// Lo que la app necesita del equipo. Hay una implementación simulada y una BLE real.
abstract class Dispositivo {
  Stream<EstadoConexion> get conexion;
  Stream<EstadoVivo> get estado;
  String? get nombre;

  Future<void> conectar();
  Future<void> desconectar();
  Future<ResumenDiario> leerResumen();
  Future<List<RegistroMinuto>> descargarHistorial(DateTime desde);
  void liberar();
}
