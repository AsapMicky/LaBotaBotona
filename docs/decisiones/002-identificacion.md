# 002 · Identificación de pacientes y cuentas

**Estado:** propuesta

- La ortesis la provee la institución y se devuelve, así que el **alta la hace el médico**. El paciente no se loguea.
- Solo hay cuentas de médico. Se evaluó un rol de enfermería y se descartó: en este seguimiento ambulatorio
  no hay controles intermedios de enfermería.
- Clave del paciente: **ID interno** (UUID + código legible). El DNI no es clave: hubo casos de un mismo número asignado
  a personas distintas según sexo registral, además de errores de carga y pacientes extranjeros.
- El dispositivo solo conoce el ID de episodio, no quién es el paciente (Ley 25.326, datos de salud).
