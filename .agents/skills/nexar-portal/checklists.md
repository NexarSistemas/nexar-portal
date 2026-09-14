# Checklists

## Cambio general

- [ ] Consulté la documentación aplicable y el código afectado.
- [ ] El cambio es focalizado, compatible y sin refactors ajenos.
- [ ] Revisé el diff y ejecuté las validaciones disponibles.

## Cambio de DB o migración

- [ ] Leí el baseline, migraciones y validaciones afectadas.
- [ ] Mantiene la compatibilidad legacy y no duplica tablas sin evidencia.
- [ ] Incluí validación de solo lectura o equivalente para la migración.
- [ ] No apliqué SQL remoto sin autorización y gates.

## Auth, RLS o seguridad

- [ ] La autorización usa RLS y ownership verificables.
- [ ] No incorporé secretos, sesiones ni autenticación legacy compartida.
- [ ] Revisé funciones privilegiadas, auditoría e idempotencia cuando aplican.

## Coexistencia o retirada legacy

- [ ] Identifiqué consumidores y evidencia de compatibilidad.
- [ ] El cambio no retira legacy de forma anticipada ni hace un big-bang.
- [ ] Para una retirada, documenté gates, respaldo y validación funcional.

## Cierre de PR

- [ ] La rama no es `main`, el alcance está completo y el diff es revisable.
- [ ] Las validaciones ejecutadas y las pendientes quedan informadas.
- [ ] La PR apunta a `main`; el merge queda pendiente de revisión.

## Antes de hacer público el repositorio

- [ ] Audité árbol actual e historial Git.
- [ ] Busqué secretos, `.env`, credenciales, tokens, passwords y datos sensibles.
- [ ] Revisé configuración, funciones y flujos privilegiados; rotaré cualquier
  secreto potencialmente expuesto.
