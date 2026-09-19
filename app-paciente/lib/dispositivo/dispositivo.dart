import 'modelo.dart';

enum EstadoConexion { desconectado, buscando, conectando, conectado }

/// Lo que la app necesita del equipo. Hay una implementación simulada y una BLE real.
abstract class Dispositivo {
  Stream<EstadoConexion> get conexion;
  Stream<EstadoVivo> get estado;
  String? get nombre;

  Future<void> conectar();
  Future<void> desconectar();

  /// Quién es el equipo y a qué tratamiento está asignado. Es lo que permite
  /// verificar que la ortesis que se está leyendo sea la del paciente.
  Future<InfoEquipo> leerInfo();

  /// Los límites y el peso que el equipo tiene cargados.
  Future<ConfigEquipo> leerConfig();

  /// El día **en curso**, que el equipo todavía está acumulando.
  Future<ResumenDiario> leerResumen();

  /// Los días ya **cerrados** con `inicio del día ≥ desde`. El equipo los guarda al
  /// pasar la medianoche, así el médico no pierde los días en que nadie abrió la app.
  Future<List<ResumenDiario>> descargarResumenes(DateTime desde);

  Future<List<RegistroMinuto>> descargarHistorial(DateTime desde);
  void liberar();
}
