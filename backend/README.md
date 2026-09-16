# Backend (Supabase)

1. Crear un proyecto en https://supabase.com (plan gratuito).
2. SQL Editor → pegar y correr `supabase/migrations/0001_esquema.sql`.
3. Authentication → Users → crear un usuario médico (email + contraseña).
4. SQL Editor → correr `supabase/seed.sql` (usa el primer usuario creado como médico y genera pacientes de prueba).
5. Copiar `Project URL` y `anon key` a `web-medico/.env.local`:
   ```
   VITE_SUPABASE_URL=https://xxxx.supabase.co
   VITE_SUPABASE_ANON_KEY=eyJ...
   ```
6. (Avance 3) Desplegar la función: `supabase functions deploy subir-datos --no-verify-jwt`.

La `anon key` es pública por diseño: lo que protege los datos son las políticas RLS del esquema.
La `service_role key` **nunca** va en las apps ni en el repo.
