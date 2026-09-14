# Datos y migraciones

El estado documentado de M00–M07 está en el
[baseline de datos](../../../docs/database/baseline.md); las migraciones y sus
validaciones reales están en `supabase/migrations/` y `supabase/validation/`.
Son artefactos versionados y no demuestran despliegue remoto.

La relación canónica es `CLIENTE -> VENTA -> VENTA_ITEM -> PAGO ->
CUMPLIMIENTO/LICENCIA -> COMISION`. Las relaciones conocidas usan IDs y FK, no
conciliación heurística como arquitectura principal. Las ventas y sus items
conservan snapshots históricos.

Evolucionar las tablas legacy compatibles: no crear por defecto `pagos_v2`,
`licencias_v2`, `vendedores_v2` ni `comisiones_v2`. `precios_planes` coexiste
mientras tenga consumidores. Cada migración nueva necesita su validación
correspondiente. No aplicar migraciones remotas sin autorización explícita.

## Saneamiento condicionado

`RONA596` / Rolando Navarta es el único vendedor real que se debe conservar como
entidad y se conserva su UUID real. Sus movimientos actuales son pruebas y se
pueden eliminar. Los demás vendedores, referidos, solicitudes, pagos,
comisiones y movimientos actuales se consideran pruebas salvo evidencia concreta
en contrario. Las licencias actuales de Comercio y Finanzas son pruebas y se
pueden eliminar o regenerar; al regenerarlas se puede reasignar `RONA596`.

Las secuencias autoincrementales se ajustan después del saneamiento solo según
el schema real. Nunca hardcodear UUID ni relaciones no demostradas. M04 y M07
continúan condicionadas y bloqueadas por sus guards actuales.
