# Instrucciones operativas

Antes de cualquier tarea, consultar el skill
[`nexar-portal`](.agents/skills/nexar-portal/SKILL.md). La prioridad de fuentes
es: repositorio y documentación actual > skill > contexto histórico o prompts.

- Mantener el MVP incremental y el alcance pedido; no introducir trabajo no
  relacionado.
- Nunca trabajar directamente sobre `main`: usar una rama por cambio, abrir PR
  obligatorio y usar Squash and Merge por defecto.
- Escribir commits breves, descriptivos y en español.
- No aplicar migraciones ni operaciones remotas destructivas sin autorización
  explícita y los gates correspondientes.
- Tratar el repositorio como futuro público: no versionar secretos,
  credenciales, passwords, tokens, `service_role`, `.env` ni datos sensibles.
- GitHub Pages no contiene lógica privilegiada. No transportar autenticación ni
  secretos compartidos del Portal Vendedor legacy.
- Respetar la coexistencia legacy hasta contar con evidencia para retirarla.
