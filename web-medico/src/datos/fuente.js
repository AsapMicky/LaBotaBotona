import { fuenteMock } from './mock.js'
import { crearFuenteSupabase } from './supabase.js'

const url = import.meta.env.VITE_SUPABASE_URL
const clave = import.meta.env.VITE_SUPABASE_ANON_KEY

// Sin credenciales, datos simulados: sirve para diseñar y para mostrar avances.
export const fuente = url && clave ? crearFuenteSupabase(url, clave) : fuenteMock
