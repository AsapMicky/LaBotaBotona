#!/usr/bin/env bash
# Crea los issues del plan de avances. Requiere GitHub CLI (`gh auth login`) y estar dentro del repo.
set -euo pipefail

for l in "firmware:1d76db" "app-paciente:36c9b0" "web-medico:0b3b47" "backend:e39b3b" "docs:cccccc"; do
  gh label create "${l%%:*}" --color "${l##*:}" --force >/dev/null
done

issue() { gh issue create --title "$1" --label "$2" --body "$3" >/dev/null && echo "✓ $1"; }

issue "Cerrar el protocolo BLE v1" docs "Revisar docs/protocolo-ble.md entre los tres y congelarlo."
issue "Llevar decisiones 001–004 al profesor" docs "Conectividad, identificación, almacenamiento, re-lesión."
issue "Crear proyecto Supabase y correr migración + seed" backend "Ver backend/README.md."
issue "Web: login real con Supabase" web-medico "Probar con .env.local."
issue "Web: alta de paciente contra Supabase" web-medico "Verificar RLS con dos médicos distintos."
issue "App: pantalla de vinculación por QR" app-paciente "Leer {\"t\": token_sync} y guardarlo en el teléfono."
issue "App: subir resúmenes con la función subir-datos" app-paciente "POST con token, resumenes y registros."
issue "Firmware: probar el simulador con potenciómetro en un ESP32" firmware "pio run -e esp32s3 -t upload; conectar con nRF Connect y con la app."
issue "Firmware: guardar historial en LittleFS" firmware "Reemplazar el vector en RAM."
issue "Firmware: lectura FSR + ADG708 + ADS1115" firmware "Reemplazar leerCarga() cuando llegue el hardware."
issue "Firmware: seguimiento de línea de base (deriva del cero)" firmware "Algoritmo propio + tests con perfiles sintéticos."
