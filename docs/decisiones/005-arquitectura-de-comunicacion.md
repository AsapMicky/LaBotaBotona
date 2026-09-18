# 005 · Cómo se comunican el equipo, la app y la web

**Estado:** propuesta · **Depende de:** [001 conectividad](001-conectividad.md), [002 identificación](002-identificacion.md)

## El camino de los datos

```
                        ┌──────────────► app del paciente ──HTTPS──┐
                        │   BLE (1 Hz + descarga)                  │
   ortesis (flash =     │                                          ▼
   fuente de verdad) ───┤                                       Supabase
                        │                                          ▲
                        └──────────► web del médico ───────────────┘
                            BLE en la consulta        lectura con cuenta
                            (Web Bluetooth)
```

**La app y la web nunca se hablan entre sí.** Se encuentran en la base. Son dos clientes del
mismo dato, con permisos distintos: la app solo escribe lo que bajó del equipo, la web lee todo
lo del médico que la usa.

Hay **dos caminos** hacia la base, los dos previstos en la decisión 001:

| Camino | Cuándo | Para qué |
|---|---|---|
| Equipo → app → Supabase | entre consultas, cuando el celular tiene señal | el médico ve la evolución sin tener el equipo |
| Equipo → web (BLE) → Supabase | en la consulta | de mínima: funciona aunque el paciente nunca haya instalado la app |

El registro nunca depende de la conectividad: si los dos caminos fallan, el dato sigue en la
flash del equipo hasta la próxima descarga.

## Qué ve cada uno, y de dónde

- **El paciente ve lo que le manda el equipo por BLE**, no la nube. Por eso la app funciona sin
  internet, que es la condición real de alguien caminando por la calle. La app **no lee** de
  Supabase: solo escribe.
- **El médico lee de Supabase**, con su cuenta y las policies por médico ya definidas en el esquema.

Consecuencia de diseño: no hace falta ninguna policy de lectura para el paciente. No se agrega
hasta que exista un requisito concreto que la justifique.

## Identidad del paciente: token, no cuenta

La decisión 002 ya estableció que el paciente no tiene cuenta. Este documento define cómo se
sostiene eso técnicamente:

1. El médico abre el episodio. La base genera un `token_sync` (UUID único por episodio).
2. La web muestra ese token como QR.
3. La app lo escanea y lo guarda en el celular. **Ese token es la credencial.**
4. Al subir datos, la app llama a la función `subir-datos` con el token. La función lo valida
   del lado del servidor: busca el episodio, exige que esté abierto (`fin is null`) y recién
   ahí escribe con la service-role key. El cliente nunca escribe directo contra la base.

Qué se gana: cerrar el episodio revoca el acceso sin ningún paso extra, no hay contraseñas que
recuperar, y no se guarda ni un dato personal más de los que el médico ya cargó.

Qué se pierde: si el paciente cambia o pierde el celular, no hay recuperación automática. Se
resuelve con el médico volviendo a mostrar el QR — un botón, no un sistema de recuperación.

**Riesgo asumido:** el token es una credencial de portador (quien lo tiene, escribe). Está
acotado porque es por episodio, solo habilita escritura, y no permite leer nada. El peor caso
es que alguien inyecte datos falsos en su propio episodio. Se acepta para el alcance del TP; en
un producto real iría un emparejamiento con passkey (ver pendientes de `protocolo-ble.md`).

## Independencia del transporte

Hoy el equipo habla BLE. Si en algún momento cambiara, **el modelo de datos no cambia**: estado
en vivo (5 campos), resumen diario (8) y registro por minuto (6) son lo mismo viajen como bytes
empaquetados o como JSON. Lo que cambia es la codificación.

Por eso:

- En la app, `Dispositivo` es una interfaz abstracta con cinco métodos. `DispositivoBle` y
  `DispositivoSimulado` la implementan. Un hipotético `DispositivoWifi` entra sin tocar ni la
  interfaz de usuario ni la subida a Supabase.
- `protocolo.dart` está partido en `modelo.dart` (las clases y su `aJson()`) y `codec_ble.dart`
  (la lectura de bytes). Esa separación es la que hace barato cambiar de transporte.
- El `aJson()` de esas clases es el puente a la nube: el mismo objeto que sale del BLE es el que
  se sube. No hay una segunda definición del dato en ningún lado.

Aclaración sobre el transporte: la decisión 001 ya descartó WiFi **en el equipo** por consumo,
por tener que configurar la red de cada domicilio y por meter credenciales de terceros en un
equipo que rota entre pacientes. Para una ortesis a batería, BLE sigue siendo lo correcto. La
arquitectura tolera el cambio, pero no se diseña *para* ese cambio.

## Cola local en la app

La app **no** sube en el momento en que recibe el dato. Lo guarda y lo sube cuando hay señal.
Sin esto se pierden días de registro en cualquier paciente con mala conexión, que es la
situación normal y no la excepción. La subida es idempotente (`upsert` por episodio y fecha),
así que reintentar no duplica.

## Estado (18/9/2026)

Los dos caminos están implementados y el de la app se probó punta a punta con un teléfono real.

1. ✅ Proyecto en Supabase con el esquema, los datos de prueba y `subir-datos` desplegada.
2. ✅ Web: login real del médico y alta escribiendo en Supabase, con el QR del `token_sync`.
3. ✅ App: escaneo del QR y token guardado en el celular.
4. ✅ App: cola local y subida vía `subir-datos`, con reintentos.
5. ✅ `.apk` de release para repartir sin cables.
6. ✅ Web: descarga de la ortesis en la consulta (Web Bluetooth) y subida por `subir-datos`,
   con el token del episodio. La web tampoco escribe directo contra la base.

Falta la persistencia real en el equipo: hoy los resúmenes de días cerrados y los registros por
minuto viven en RAM. Es la tarea de LittleFS del Avance 4.

## Los dos caminos escriben por la misma puerta

Ni la app ni la web escriben en `resumenes_diarios` ni en `registros_minuto`: las policies no lo
permiten. Las dos llaman a `subir-datos` con el `token_sync` del episodio, y la función valida y
escribe con la service-role key. Una sola puerta, una sola validación, un solo lugar donde mirar
si algo no entra.

## Para discutir con el grupo y la cátedra

- ¿Se confirma que el paciente no tiene cuenta? (Este documento asume que sí, siguiendo la 002.)
- ¿La app debería poder leer de la nube, o alcanza con que lea del equipo?
- ¿El riesgo del token de portador es aceptable para el alcance del TP?
