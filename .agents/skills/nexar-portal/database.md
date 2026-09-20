# Datos y migraciones

El estado documentado de M00–M07 está en el
[baseline de datos](../../../docs/database/baseline.md); las migraciones y sus
validaciones reales están en `supabase/migrations/` y `supabase/validation/`.
Son artefactos versionados y no demuestran despliegue remoto.
El [relevamiento legacy sanitizado](../../../docs/database/legacy-schema-relevamiento.md)
es la fuente operativa del snapshot 2026-09-14; debe revalidarse antes de M04,
M07 o cualquier operacion destructiva.

La relación canónica es `CLIENTE -> VENTA -> VENTA_ITEM -> PAGO ->
CUMPLIMIENTO/LICENCIA -> COMISION`. Las relaciones conocidas usan IDs y FK, no
conciliación heurística como arquitectura principal. Las ventas y sus items
conservan snapshots históricos.

Evolucionar las tablas legacy compatibles: no crear por defecto `pagos_v2`,
`licencias_v2`, `vendedores_v2` ni `comisiones_v2`. `precios_planes` coexiste
mientras tenga consumidores. Cada migración nueva necesita su validación
correspondiente. No aplicar migraciones remotas sin autorización explícita.

## Saneamiento condicionado

Existe una única entidad comercial maestra que debe preservarse durante el
saneamiento controlado. Su identificador operativo se resuelve en tiempo de
ejecución según las migraciones ya versionadas; no se deben hardcodear UUID ni
datos personales adicionales en documentación pública.

Los demás vendedores, referidos, solicitudes, pagos, comisiones y movimientos
del snapshot inicial se consideran de prueba salvo evidencia concreta en
contrario. Las licencias actuales de Comercio y Finanzas también se tratan como
datos de prueba regenerables bajo el procedimiento documentado.

Las secuencias autoincrementales se ajustan después del saneamiento solo según
el schema real. Nunca hardcodear UUID ni relaciones no demostradas. M04 y M07
continúan condicionadas y bloqueadas por sus guards actuales.
