# 003 · Qué se guarda en la flash

**Estado:** propuesta

| Qué | Cálculo | Por día |
|---|---|---|
| Señal cruda | 8 canales × 2 B × 50 Hz = 800 B/s | ≈ 69 MB — **no entra** en 16 MB |
| Agregados por minuto | 12 B × 1440 min | ≈ 17 KB |
| Resumen diario | 28 B | 28 B |

Con agregados por minuto, 10 MB de partición alcanzan para más de 1,5 años de uso continuo.
El indicador (dosis) se integra a 50 Hz en el microcontrolador; lo que se guarda es el resultado, no la señal.
La señal cruda solo se transmite en un modo de calibración de banco (a definir).
