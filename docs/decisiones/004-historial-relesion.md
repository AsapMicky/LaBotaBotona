# 004 · ¿Conservar el historial ante una re-lesión?

**Estado:** propuesta

**Sí.** El razonamiento es el mismo que con un Holter: el registro previo sirve de referencia.
Cada tratamiento es un **episodio** separado del mismo paciente, con su miembro y su lesión.
La web permite ver episodios anteriores del mismo miembro.

**Cuidado al comparar:** los límites prescriptos cambian entre episodios, así que la dosis absoluta no es comparable.
Se comparan los índices normalizados (cumplimiento, permanencia en ventana) y la evolución semana a semana.

El mismo cuidado vale **dentro** de un episodio. La carga permitida se progresa durante la rehabilitación, y
la dosis de sobrecarga es la integral de lo que excede el límite: si L cambió, las barras de antes y después
no miden lo mismo. Por eso la prescripción tiene historia (tabla `indicaciones`) y el gráfico de evolución
marca el día en que cambió. El cumplimiento y la permanencia sí siguen siendo comparables, porque son
relativos al límite que regía cada día.
