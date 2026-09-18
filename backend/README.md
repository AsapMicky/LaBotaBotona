# Backend (Supabase)

El proyecto del Grupo 6 ya está creado y funcionando. Esto es lo que hay y cómo rearmarlo de cero.

## Estado actual

- Proyecto `dosimetro-carga-plantar`, región us-east-2, Postgres 17.
- Migraciones `0001` y `0002` aplicadas; `seed.sql` corrido (3 pacientes de prueba, 4 episodios, 5 ortesis).
- Usuario médico de prueba: `medica@hospital.org`. La contraseña la tiene Migue; se cambia en
  Authentication → Users.
- Función `subir-datos` desplegada **con la verificación de JWT apagada**: el paciente no tiene cuenta y la
  función valida el `token_sync` del QR por su cuenta (decisión 005).
- La `Project URL` y la `anon key` están en `web-medico/.env.local`, que no se versiona. Pedíselas al grupo
  o sacalas de Settings → API.

## Rearmarlo de cero

1. Crear un proyecto en https://supabase.com (plan gratuito).
2. SQL Editor → correr `supabase/migrations/0001_esquema.sql` y después `0002_perfil_medico_automatico.sql`.
3. Authentication → Users → Add user → email y contraseña, con *Auto Confirm User* tildado.
   El trigger de la migración `0002` le crea solo la fila en `medicos`; sin eso el alta de pacientes
   falla por la clave foránea.
4. SQL Editor → correr `supabase/seed.sql` (usa el primer usuario creado como médico y genera pacientes
   de prueba).
5. Copiar `Project URL` y `anon key` (Settings → API) a `web-medico/.env.local`:
   ```
   VITE_SUPABASE_URL=https://xxxx.supabase.co
   VITE_SUPABASE_ANON_KEY=eyJ...
   ```
6. Desplegar la función: Edge Functions → Deploy → pegar `supabase/functions/subir-datos/index.ts`,
   y **apagar "Verify JWT"**. Con la CLI es `supabase functions deploy subir-datos --no-verify-jwt`.

## La app del paciente

No lee de Supabase: solo escribe, y siempre a través de `subir-datos` (decisión 005). Se le pasa la URL
del proyecto al compilar:

```bash
flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co
```

No necesita la `anon key`, porque la función está desplegada sin verificación de JWT.

## Claves

La `anon key` es pública por diseño: lo que protege los datos son las políticas RLS del esquema.
La `service_role key` **nunca** va en las apps ni en el repo: la usa solamente `subir-datos`, que corre
en el servidor y la toma de las variables de entorno que inyecta Supabase.
