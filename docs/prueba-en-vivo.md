# Prueba en vivo: web del médico ↔ app del paciente

Guion para mostrar el circuito completo funcionando, sin plantilla y sin ESP32. La app usa el
**equipo simulado**, que inventa una jornada de apoyo verosímil; todo lo demás (Supabase, el token del
QR, la subida, el reporte) es real.

Dura unos cinco minutos.

## Qué se demuestra

```
  web del médico                Supabase                     app del paciente
 ─────────────────            ────────────                 ──────────────────
  alta del paciente  ──────►  episodio + token_sync
  muestra el QR      ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─►  la cámara lo escanea
                                                            (equipo → cola local)
                              subir-datos  ◄──────────────  POST con el token
  el reporte lo muestra ◄───  resumenes_diarios
```

El paciente **nunca** crea una cuenta y la app **nunca** lee de la nube: solo escribe (decisión 005).
El equipo es autónomo: mide y guarda sin depender de que haya un celular cerca.

## Antes de empezar

- **En la computadora**: la web corriendo.
  ```bash
  cd C:\dev\dosimetro-carga-plantar\web-medico
  npm run dev
  ```
  Abrir http://localhost:5173. Tiene que pedir email y contraseña *sin* el cartel de "modo
  demostración": eso significa que está contra Supabase de verdad. Si aparece el cartel, falta
  `web-medico/.env.local` (ver `backend/README.md`).
- **En el teléfono**: Android con internet (wifi o datos) y la app instalada (ver abajo).
  El Bluetooth no hace falta: el equipo está simulado.

## Instalar la app en el teléfono

El archivo es `app-paciente/build/app/outputs/flutter-apk/app-release.apk`. Ya trae adentro la
dirección del proyecto de Supabase, así que no hay nada que configurar.

1. Pasar el `.apk` al teléfono (cable, Drive, WhatsApp a uno mismo, lo que sea).
2. Abrirlo desde el teléfono. Android va a avisar que la app viene de un origen desconocido:
   *Configuración → Permitir de esta fuente* y volver a abrirlo.
3. Si ya había una versión vieja instalada, desinstalarla primero: están firmadas distinto y la
   actualización falla.

Para regenerarlo:
```bash
cd C:\dev\dosimetro-carga-plantar\app-paciente
flutter build apk --release --dart-define=SUPABASE_URL=https://<tu-proyecto>.supabase.co
```

## El guion

1. **Entrar a la web** con el usuario médico (`medica@hospital.org`). Se ve la lista de pacientes
   con el cumplimiento de cada uno y la flecha de tendencia.
2. **Mostrar un reporte**: Laura Benítez tiene 21 días de historial, el gráfico de dosis contra
   cumplimiento y la barra de cómo repartió el apoyo cada día.
3. **Dar de alta un paciente nuevo**: nombre, lesión, miembro, límites (por ejemplo entre 10 y 25 %PC),
   peso y una ortesis libre. Al guardar aparece **el QR**.
4. **En el teléfono**, abrir la app. Muestra el semáforo del equipo simulado y arriba el aviso
   *"Todavía no vinculaste la app con tu médico"*.
5. Tocar ese aviso (o el ícono del maletín) → **Escanear el código** → apuntar la cámara al QR de la
   pantalla de la computadora. La primera vez pide permiso de cámara.
6. La pantalla pasa a **"Vinculada con tu médico"**. Abajo, *Envío a tu médico* muestra los días
   pendientes bajando a cero y la fecha del último envío. Si tarda, *Enviar ahora*.
7. **Volver a la web**, entrar al paciente nuevo y **recargar**. Aparecen **quince días**: los catorce
   que el equipo tenía guardados de antes de la vinculación, más el día en curso. Cumplimiento,
   excedencias, horas de apoyo y la curva de evolución completa.

Ese último punto es el que conviene remarcar: el equipo venía registrando **antes** de que existiera la
vinculación, y guarda cada día al pasar la medianoche. La app no es la que mide, es la que transporta.
Si el paciente pasa una semana sin abrirla, no se pierde nada: cuando la abre, viajan los siete días.

## El otro camino: descargar la ortesis en la consulta

Este no necesita que el paciente tenga la app, ni siquiera un celular. Es el camino "de mínima"
de la decisión 001, y sirve para mostrar que el sistema funciona con un paciente que nunca
instaló nada.

Necesita **Chrome o Edge** en una computadora con Bluetooth, y el equipo encendido al lado.
Firefox y Safari no tienen Web Bluetooth.

1. En el reporte del paciente, abajo de todo, **En la consulta → Conectar la ortesis**. El navegador
   muestra la lista de equipos: elegir el `DOSI-xxxx` que corresponda.
2. Aparece a qué tratamiento está asignada y el resumen del día. Si está sin asignar,
   **Asignar a este tratamiento** primero.
3. **Descargar lo guardado.** Trae los días cerrados, el día en curso y el detalle minuto a minuto,
   y lo manda al servidor. El reporte se rearma solo cuando termina.
4. **Enviar la indicación actual** escribe los límites en el equipo. Ojo: quedan *pendientes* hasta
   que alguien mantenga apretado el botón de la ortesis dos segundos. Eso es a propósito: ningún
   cambio remoto mueve el umbral sin una validación presencial.

La descarga usa exactamente la misma puerta que la app, la función `subir-datos` con el token del
episodio. Ni la web ni la app escriben directo contra la base.

### Para mostrar el cierre del tratamiento

En el reporte del paciente, cerrar el episodio. La próxima vez que la app intente enviar, el servidor
contesta que el episodio está cerrado y la app pasa a **"El tratamiento fue cerrado"** sola, sin
que nadie toque el teléfono. Es la revocación de la que habla la decisión 005.

### Para mostrar que funciona sin internet

Poner el teléfono en modo avión y tocar *Enviar ahora*: dice que no se pudo enviar y que se
reintenta solo. Sacar el modo avión y esperar: sube lo acumulado y vuelve a cero. Nada se pierde,
que es el punto de la cola local.

## Si algo no sale

- **La app dice "Todo enviado" pero en la web no aparece nada** → el reporte no se recargó, o el
  paciente que estás mirando no es el del QR que escaneaste.
- **"No se pudo enviar"** → el teléfono no tiene internet, o el `.apk` se compiló sin
  `--dart-define=SUPABASE_URL`.
- **La cámara no lee el QR** → subir el brillo de la pantalla, alejar el teléfono unos 20 cm. Como
  último recurso, el campo de abajo acepta el código pegado a mano; el `token_sync` se puede sacar del
  panel de Supabase, tabla `episodios`.
- **La web muestra el cartel de "modo demostración"** → falta `web-medico/.env.local`, y hay que
  reiniciar `npm run dev` después de crearlo.
- **Android no deja instalar** → desinstalar la versión anterior primero.
