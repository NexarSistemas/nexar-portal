# Baseline Supabase

Este directorio contiene el baseline SQL versionado de Nexar Portal. Los archivos
son artefactos de Git: **no se aplicaron ni se deben aplicar automáticamente al
proyecto Supabase remoto**.

Las migraciones siguen el orden M00 a M07. Cada una tiene una consulta de
validacion de solo lectura equivalente en `supabase/validation/`. La ejecucion
futura debe hacerse primero en un entorno controlado, de forma secuencial y con
las validaciones de cada paso. Este repositorio no contiene credenciales,
proyecto enlazado ni comandos de despliegue de base de datos.

| Migracion | Proposito | Estado de riesgo |
| --- | --- | --- |
| M00 | Verifica el minimo legacy y documenta la coexistencia. | No destructiva |
| M01 | Crea clientes, productos, planes y precios versionados. | Aditiva |
| M02 | Crea ventas y venta_items con snapshot historico. | Aditiva |
| M03 | Agrega FK nullable a pagos, licencias y comisiones. | Compatible |
| M04 | Sanea solo datos de prueba despues de relevar el schema. | Destructiva y bloqueada |
| M05 | Crea perfiles y helpers para Supabase Auth. | Aditiva |
| M06 | Declara grants, RLS y policies futuras. | Requiere prueba funcional |
| M07 | Retira Auth legacy solo despues del gate operativo. | Parcialmente destructiva y bloqueada |

`precios_planes`, las tablas legacy, `admin_audit_log` y la autenticacion propia
del Portal Vendedor siguen coexistiendo. No hay migracion de passwords ni
provision de usuarios Auth en este baseline.

La descripcion completa del contrato, riesgos, reversibilidad y gates se
encuentra en [docs/database/baseline.md](../docs/database/baseline.md).
