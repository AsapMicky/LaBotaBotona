# Puesta en marcha en Windows

Guía paso a paso para dejar el proyecto corriendo en una PC con Windows, pensada para alguien que
**nunca usó Android Studio**. Está escrita sobre la máquina de Migue (septiembre 2026), pero sirve
para cualquier integrante del grupo.

Índice:
1. [Antes de empezar](#1-antes-de-empezar)
2. [Modo Desarrollador de Windows](#2-modo-desarrollador-de-windows)
3. [Instalar Flutter](#3-instalar-flutter)
4. [`flutter doctor` y cómo resolver lo que marca](#4-flutter-doctor-y-cómo-resolver-lo-que-marca)
5. [Plugins Flutter y Dart en Android Studio](#5-plugins-flutter-y-dart-en-android-studio)
6. [Abrir `app-paciente` como proyecto](#6-abrir-app-paciente-como-proyecto)
7. [Primera vez: generar la parte Android y correr los tests](#7-primera-vez-generar-la-parte-android-y-correr-los-tests)
8. [Correr la app en el emulador (modo simulado)](#8-correr-la-app-en-el-emulador-modo-simulado)
9. [Correr la app en un celular con Bluetooth real](#9-correr-la-app-en-un-celular-con-bluetooth-real)
10. [Web del médico](#10-web-del-médico)
11. [Tests y build del firmware](#11-tests-y-build-del-firmware)
12. [Subir el repo a GitHub](#12-subir-el-repo-a-github)
13. [Problemas frecuentes](#13-problemas-frecuentes)

---

## 1. Antes de empezar

**Dónde vive el repo.** En `C:\dev\dosimetro-carga-plantar`. No lo pongas dentro de OneDrive, Google Drive
ni Dropbox: los sincronizadores rompen `.git`, `node_modules` y `.dart_tool`. Tampoco en rutas con
espacios o acentos (`C:\Users\Juan Pérez\...` trae problemas con Gradle).

**Qué hace falta y qué ya hay** (estado de la máquina de Migue al 16/9/2026):

| Herramienta | ¿Para qué? | Estado | Cómo conseguirla |
|---|---|---|---|
| Git | todo | ✅ 2.46 | https://git-scm.com/download/win |
| GitHub CLI (`gh`) | issues, PRs desde la terminal | ✅ 2.93 (falta `gh auth login`) | `winget install GitHub.cli` |
| Node.js LTS | web del médico | ✅ 24 LTS | `winget install OpenJS.NodeJS.LTS` |
| Python 3.11+ | PlatformIO (firmware) | ✅ 3.11 | `winget install Python.Python.3.12` |
| GCC (WinLibs) | tests del firmware en la PC | ✅ | `winget install BrechtSanders.WinLibs.POSIX.UCRT` |
| PlatformIO | firmware | ✅ en `firmware\.venv` | ver [§11](#11-tests-y-build-del-firmware) |
| Android Studio | emulador, SDK, editor de la app | ✅ | https://developer.android.com/studio |
| Android SDK | compilar la app | ⚠️ falta *cmdline-tools* | ver [§4](#4-flutter-doctor-y-cómo-resolver-lo-que-marca) |
| Java (JDK) | Gradle (lo usa Flutter por abajo) | ✅ viene con Android Studio | nada que hacer |
| **Flutter + Dart** | app del paciente | ❌ | [§3](#3-instalar-flutter) |
| Modo Desarrollador de Windows | plugins de Flutter (symlinks) | ⚠️ | [§2](#2-modo-desarrollador-de-windows) |

**Terminal.** Los comandos de esta guía son para **PowerShell** (clic derecho en el botón Inicio →
*Terminal*). Después de instalar algo o de cambiar el PATH, **cerrá y abrí la terminal de nuevo**: la
terminal vieja no se entera.

---

## 2. Modo Desarrollador de Windows

Flutter necesita crear enlaces simbólicos para los plugins (`flutter_blue_plus`, `permission_handler`).
Sin esto, `flutter pub get` o `flutter run` fallan con *"Building with plugins requires symlink support"*.

1. Abrí **Configuración → Sistema → Para programadores** (o ejecutá `start ms-settings:developers`).
2. Activá **Modo de desarrollador**. Aceptá el aviso.

No hace falta reiniciar.

---

## 3. Instalar Flutter

Flutter es un SDK que se descomprime en una carpeta, no un instalador. Dart viene adentro.

1. Bajá el zip del canal **stable** para Windows desde https://docs.flutter.dev/get-started/install/windows/mobile
   (botón *Download and install* → *flutter_windows_x.y.z-stable.zip*).
2. Descomprimilo en **`C:\dev\flutter`** (tiene que quedar `C:\dev\flutter\bin\flutter.bat`).
   No lo pongas en `C:\Program Files` (permisos) ni en OneDrive.
3. Agregá `C:\dev\flutter\bin` al PATH del usuario:
   - Inicio → escribí *"variables de entorno"* → **Editar las variables de entorno de la cuenta** (no las del sistema).
   - En **Variables de usuario**, seleccioná `Path` → **Editar** → **Nuevo** → pegá `C:\dev\flutter\bin` → Aceptar en todo.
   - O desde PowerShell, de una:
     ```powershell
     [Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path","User") + ";C:\dev\flutter\bin", "User")
     ```
4. Cerrá la terminal, abrí una nueva y probá:
   ```powershell
   flutter --version
   ```
   La primera vez tarda un rato: baja el motor de Dart.

---

## 4. `flutter doctor` y cómo resolver lo que marca

```powershell
flutter doctor
```

Solo necesitamos que **Flutter** y **Android toolchain** queden en verde. Lo demás se ignora.
En esta máquina va a marcar, en orden:

**`[!] Android toolchain — cmdline-tools component is missing`**
1. Abrí Android Studio. En la pantalla de bienvenida: **More Actions → SDK Manager**
   (si ya tenés un proyecto abierto: **File → Settings → Languages & Frameworks → Android SDK**).
2. Pestaña **SDK Tools** → tildá **Android SDK Command-line Tools (latest)** → **Apply** → OK.
3. Volvé a correr `flutter doctor`.

**`[!] Some Android licenses not accepted`**
```powershell
flutter doctor --android-licenses
```
Respondé `y` a todo.

**`[!] Android Studio ... Flutter plugin not installed`** → es el §5, seguí.

**Java / Gradle.** Flutter usa el JDK que viene con Android Studio (`C:\Program Files\Android\Android Studio\jbr`).
No hay que instalar nada. Si en el futuro un `flutter run` falla con algo tipo *"Unsupported class file
major version"* o *"Gradle requires JDK 17-21"*, es porque el JDK de Android Studio es más nuevo que lo que
soporta el Gradle del proyecto. Solución: instalar un JDK 17 (`winget install EclipseAdoptium.Temurin.17.JDK`)
y decirle a Flutter que use ese:
```powershell
flutter config --jdk-dir "C:\Program Files\Eclipse Adoptium\jdk-17.0.x-hotspot"
```

**`[✗] Visual Studio`, `[!] Chrome`, `[✗] Xcode`, `[!] Network resources`** → ignorar. No compilamos para
Windows escritorio, web ni iOS.

Cuando `flutter doctor` muestre `[√] Flutter` y `[√] Android toolchain`, listo.

---

## 5. Plugins Flutter y Dart en Android Studio

1. Android Studio → pantalla de bienvenida → **Plugins** (o **File → Settings → Plugins**).
2. Pestaña **Marketplace** → buscá **Flutter** → **Install**. Te pregunta si instalar también **Dart**: sí.
3. **Restart IDE**.

Al reiniciar, si te pide la ruta del SDK de Flutter: `C:\dev\flutter`.

---

## 6. Abrir `app-paciente` como proyecto

Importante: **no** se copia y pega código a un proyecto nuevo. Se abre la carpeta que ya está en el repo.

1. Android Studio → **File → Open** (o **Open** en la pantalla de bienvenida).
2. Navegá a `C:\dev\dosimetro-carga-plantar\app-paciente` y elegí **esa carpeta** (no la raíz del monorepo).
3. Si pregunta *"Trust and Open Project?"* → **Trust Project**.
4. Esperá a que termine de indexar (barra de progreso abajo a la derecha). Puede tardar unos minutos la primera vez.

Si abajo aparece *"Pub get has not been run"* o *"Flutter SDK not found"*: **File → Settings → Languages &
Frameworks → Flutter → Flutter SDK path** = `C:\dev\flutter`, y después el botón **Pub get** que aparece
arriba del editor.

---

## 7. Primera vez: generar la parte Android y correr los tests

El repo trae solo el código Dart (`lib/`, `test/`, `pubspec.yaml`). La carpeta `android/` con el proyecto
Gradle **no está versionada todavía**: la genera Flutter. Esto se hace **una sola vez** y se commitea.

Abrí la terminal integrada de Android Studio (pestaña **Terminal** abajo) o PowerShell en `app-paciente`:

```powershell
cd C:\dev\dosimetro-carga-plantar\app-paciente
flutter create . --project-name dosimetro_paciente --platforms android
```

Esto crea `android/`, `.metadata`, `.gitignore` propio de Flutter y **un archivo de test de ejemplo que
hay que borrar**, porque busca una clase `MyApp` que no existe y rompe `flutter test`:

```powershell
Remove-Item test\widget_test.dart
```

Después, los permisos de Bluetooth. Abrí `android\app\src\main\AndroidManifest.xml` y pegá este bloque
**adentro de `<manifest ...>` y antes de `<application`**:

```xml
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
```

Ahora sí:

```powershell
flutter pub get
flutter analyze
flutter test
```

`flutter analyze` tiene que terminar en *No issues found!* y `flutter test` en *All tests passed!*
(son los tests de `test/protocolo_test.dart`, que verifican la decodificación del protocolo BLE contra
los mismos bytes que genera el firmware).

**Qué commitear después de esto:** `android/` (menos lo que el `.gitignore` ya excluye), `.metadata`,
`pubspec.lock` y el `.gitignore` nuevo de `app-paciente`. Mensaje sugerido:
`app: proyecto Android generado con flutter create + permisos BLE`.

---

## 8. Correr la app en el emulador (modo simulado)

La app arranca por defecto en **modo simulado** (`SIMULADO=true` en `lib/main.dart`): inventa estados del
equipo para poder diseñar la pantalla sin hardware. El emulador sirve perfecto para esto.

**Crear un emulador (una sola vez):**
1. Android Studio → barra lateral derecha → **Device Manager** (ícono de celular) → **+** / **Create Virtual Device**.
2. Elegí **Pixel 7** (o cualquier teléfono) → **Next**.
3. Imagen del sistema: una con **Google APIs**, API 34 o 35 (si dice *Download* al lado, bajala primero) → **Next** → **Finish**.

**Correr:**
1. En el Device Manager, botón ▶ del emulador. Esperá que termine de bootear (1-2 min la primera vez).
2. Arriba en Android Studio, en el selector de dispositivo, tiene que aparecer el emulador. Botón **Run ▶** (o Shift+F10).

O desde la terminal:
```powershell
flutter emulators                 # lista los emuladores creados
flutter emulators --launch <id>   # lo arranca
flutter run                       # compila y corre (la primera vez tarda varios minutos: Gradle baja dependencias)
```

Vas a ver el semáforo cambiando solo cada pocos segundos y la batería bajando. Es la simulación.

> El emulador de Android **no tiene Bluetooth**. Para probar contra el ESP32 real hace falta un celular físico (§9).

---

## 9. Correr la app en un celular con Bluetooth real

**En el celular (Android 8 o más nuevo):**
1. **Ajustes → Acerca del teléfono → Información de software** (varía según marca) → tocá **7 veces** en
   *Número de compilación*. Aparece *"Ya sos desarrollador"*.
2. **Ajustes → Sistema → Opciones de desarrollador** → activá **Depuración por USB**.
3. Conectalo a la PC por USB. Si el celular pregunta el modo de conexión, elegí **Transferencia de archivos (MTP)**.
4. Va a aparecer un cartel *"¿Permitir depuración USB desde esta computadora?"* → tildá *"Permitir siempre"* → **Permitir**.

**En la PC:**
```powershell
flutter devices
```
Tiene que listar el celular. Si no aparece: probá otro cable (muchos son solo de carga), otro puerto USB, o
instalá el driver USB del fabricante (Samsung, Xiaomi, Motorola tienen el suyo; Google: *Google USB Driver*
desde SDK Manager → SDK Tools).

**Correr con el equipo real:**
```powershell
flutter run --dart-define=SIMULADO=false
```
Con `SIMULADO=false` la app busca por Bluetooth un equipo que anuncie el servicio del dosímetro
(`DOSI-xxxx`, ver `docs/protocolo-ble.md`). Necesita el ESP32 encendido con el firmware cargado (§11).
La primera vez el celular pide permiso de *Dispositivos cercanos* / Bluetooth: aceptalo.

Desde Android Studio se puede hacer lo mismo: **Run → Edit Configurations → Additional run args** =
`--dart-define=SIMULADO=false`.

---

## 10. Web del médico

Necesita solo Node.js. Sin configurar nada usa **datos simulados** (`src/datos/mock.js`).

```powershell
cd C:\dev\dosimetro-carga-plantar\web-medico
npm install        # solo la primera vez o cuando cambia package.json
npm run dev
```

Abrí http://localhost:5173 en el navegador. Cualquier email y contraseña sirven en modo simulado.
Para parar el servidor: `Ctrl+C` en la terminal.

Para verificar que compila igual que en la CI: `npm run build` (deja el resultado en `dist/`, que está ignorado).

**Con Supabase de verdad:** copiá `.env.example` a `.env.local` y completá `VITE_SUPABASE_URL` y
`VITE_SUPABASE_ANON_KEY` (ver `backend/README.md`). `.env.local` está ignorado por git: **nunca lo commitees**.

---

## 11. Tests y build del firmware

PlatformIO está instalado en un entorno virtual de Python dentro del repo (`firmware\.venv`, ignorado por git).
Si esa carpeta no existe en tu máquina (por ejemplo, la clonaste de cero), creala:

```powershell
cd C:\dev\dosimetro-carga-plantar\firmware
python -m venv .venv
.\.venv\Scripts\pip install platformio
```

**Tests de la lógica de dosis en la PC (sin placa).** Necesitan un compilador C++ (GCC). Si `gcc --version`
no anda: `winget install BrechtSanders.WinLibs.POSIX.UCRT` y abrí una terminal nueva.

```powershell
cd C:\dev\dosimetro-carga-plantar\firmware
.\.venv\Scripts\Activate.ps1      # activa el entorno; el prompt pasa a mostrar (.venv)
pio test -e native
```
Si PowerShell no deja ejecutar `Activate.ps1` ("la ejecución de scripts está deshabilitada"), usá el
ejecutable directo sin activar: `.\.venv\Scripts\pio test -e native`.

Tiene que terminar con `9 Tests 0 Failures 0 Ignored`.

**Grabar un ESP32** (placa S3 o NodeMCU con el potenciómetro):
```powershell
pio run -e esp32s3 -t upload      # o -e esp32dev para el NodeMCU ESP32 (WROOM-32)
pio device monitor                # consola serie a 115200; Ctrl+C para salir
```
La primera vez baja el toolchain de Espressif (varios cientos de MB, a `C:\Users\<vos>\.platformio`).
Si Windows no ve la placa como puerto COM, falta el driver USB-serie: CP210x (Silicon Labs) o CH340,
según el chip que tenga el devkit.

También se puede usar la extensión **PlatformIO IDE** de VS Code, que hace lo mismo con botones.

---

## 12. Subir el repo a GitHub

Todo esto es una sola vez, cuando el grupo decida crear el repo.

1. En https://github.com/new creá el repo (por ejemplo `dosimetro-carga-plantar`), **vacío**: sin README,
   sin `.gitignore`, sin licencia (ya los tenemos; si los agregás desde GitHub, el primer push va a chocar).
   Privado o público según prefieran.
2. Conectá el repo local y subilo:
   ```powershell
   cd C:\dev\dosimetro-carga-plantar
   git remote add origin https://github.com/<usuario-u-organizacion>/dosimetro-carga-plantar.git
   git push -u origin main
   ```
   La primera vez Git abre una ventana para loguearte en GitHub (Git Credential Manager). Es normal.
3. Invitá al resto del grupo: en GitHub, **Settings → Collaborators → Add people**. Cada uno clona con
   `git clone https://github.com/.../dosimetro-carga-plantar.git C:\dev\dosimetro-carga-plantar`.
4. La CI (`.github/workflows/ci.yml`) corre sola en cada push a `main` y en cada PR: tests del firmware,
   `flutter analyze` + `flutter test` y el build de la web. Se ve en la pestaña **Actions**.

**Opcional: crear los issues del plan de avances con GitHub CLI.**
```powershell
gh auth login          # elegí GitHub.com → HTTPS → Login with a web browser
```
y después, desde **Git Bash** (clic derecho en la carpeta → *Open Git Bash here*, porque el script es `.sh`):
```bash
cd /c/dev/dosimetro-carga-plantar
bash scripts/crear-issues.sh
```
Crea las etiquetas (`firmware`, `app-paciente`, `web-medico`, `backend`, `docs`) y un issue por cada tarea
de `docs/plan-de-avances.md`.

---

## 13. Problemas frecuentes

- **"No se reconoce `flutter` / `node` / `pio` como comando"** → cerrá y abrí la terminal (y Android Studio).
  Si sigue, revisá que la carpeta esté en el PATH del usuario (§3).
- **"Building with plugins requires symlink support"** → Modo Desarrollador apagado (§2).
- **`flutter doctor` dice que falta cmdline-tools o licencias** → §4.
- **Gradle tarda una eternidad la primera vez** → es normal (baja ~1 GB). Dejalo.
- **Errores raros en `flutter run` después de un `git pull`** → `flutter clean` y de nuevo `flutter pub get`.
- **El celular no aparece en `flutter devices`** → cable de datos, driver USB, aceptar el cartel de depuración (§9).
- **`git status` muestra archivos modificados que no tocaste** → casi siempre finales de línea. El repo
  fuerza LF con `.gitattributes`; corré `git add --renormalize .` una vez y listo.
- **Archivos duplicados o "conflicto de sincronización" en el nombre** → el repo está dentro de OneDrive.
  Movelo a `C:\dev`.
- **`npm install` falla con EPERM** → cerrá el `npm run dev` que quedó corriendo en otra terminal.
