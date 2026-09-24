# Baseline Supabase

Este directorio contiene el baseline SQL versionado de Nexar Portal. Los archivos
son artefactos de Git: **no se aplicaron ni se deben aplicar automáticamente al
proyecto Supabase remoto**.

Las migraciones legacy siguen el orden M00 a M07, con M06.5 como transición aditiva y M06.6 como hardening acotado entre M06 y M07. Las migraciones aditivas
posteriores usan nombres timestampados y descriptivos. Cada una tiene una consulta de
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
| M04 | Sanea datos de prueba y crea catalogo inicial desde `precios_planes`. | Destructiva y gated |
| M05 | Crea perfiles y helpers para Supabase Auth. | Aditiva |
| M06 | Declara grants, RLS y policies futuras. | Requiere prueba funcional |
| M06.5 | Prepara Auth+RLS transicional para vendedores, licencias y comisiones legacy. | Aditiva; coexistencia legacy |
| M06.6 | Revoca la ejecución pública del RPC legacy `portal_dashboard_vendedor(text)` ya no consumido por runtime. | Hardening acotado; reversible |
| Fidelización Fase 1 | Crea el esquema multi-tenant del MVP, integridad cruzada, grants mínimos y RLS de solo lectura para clientes y staff. | Aditiva; requiere prueba local de autorización |
| Fidelización Fase 2 | Agrega RPC para crear, resolver por QR y confirmar acreditaciones `earn` con autorización, atomicidad e idempotencia. | Aditiva; requiere prueba local transaccional |
| Fidelización Fase 3 | Agrega RPC para intención, escaneo, confirmación y cancelación de canjes `redeem`, con costo congelado y saldo derivado. | Aditiva; requiere prueba local transaccional y de concurrencia |
| Fidelización Fase 4 | Agrega la búsqueda exacta por email y saldo derivado para staff del panel operador, sin exponer `auth.users`. | Aditiva; requiere prueba local de autorización y aislamiento |
| Fidelización Fase 5 | Agrega el registro idempotente de la cuenta cliente mediante el QR público del tenant y la identidad de Auth, y la lectura atómica de saldo derivado para su propia cuenta. | Aditiva; requiere prueba local de concurrencia, autorización y aislamiento |
| M07 | Retira Auth legacy solo despues del gate operativo. | Parcialmente destructiva y bloqueada |

`precios_planes`, las tablas legacy, `admin_audit_log` y la autenticacion propia
del Portal Vendedor siguen coexistiendo. No hay migracion de passwords ni
provision de usuarios Auth en este baseline.

La prueba transaccional `supabase/tests/fidelizacion_fase1_rls.sql` usa fixtures
sintéticos, valida aislamiento e integridad —incluida la igualdad entre los
puntos de cada operación y su movimiento firmado— y finaliza con `ROLLBACK`.
No debe ejecutarse contra el proyecto remoto sin una autorización separada.

La prueba `supabase/tests/fidelizacion_fase2_acreditacion.sql` valida creación
autorizada, aislamiento, QR sin efectos, cliente correcto, expiración,
idempotencia, doble confirmación, concurrencia estructural, atomicidad ante un
fallo controlado y saldo derivado. También finaliza con `ROLLBACK` y conserva
el mismo límite de ejecución exclusivamente local y autorizada.

La prueba `supabase/tests/fidelizacion_fase3_canje.sql` cubre intención desde
recompensa activa, QR como localizador sin débito, autorización de staff,
congelamiento del costo, idempotencia, saldo insuficiente, cancelación y el
caso de dos canjes contra la misma cuenta. Finaliza con `ROLLBACK`; la
serialización se implementa bloqueando la cuenta antes de recalcular el saldo.

La prueba `supabase/tests/fidelizacion_fase4_panel_operador.sql` valida búsqueda
exacta normalizada, roles `admin` y `operador`, saldo cero y saldo derivado,
cuentas y membresías inactivas, tenant inactivo y aislamiento entre tenants. La
suite es transaccional y finaliza con `ROLLBACK`.

La prueba `supabase/tests/fidelizacion_fase5_registro_cliente.sql` valida alta
idempotente por QR, asociaciones aisladas por usuario y tenant, rechazo de QR o
cuentas no habilitadas y conservación del bloqueo de `INSERT` directo. La suite
es transaccional y finaliza con `ROLLBACK`.

La prueba `supabase/tests/fidelizacion_fase5_saldo_cliente.sql` valida saldo
cero, movimientos `earn` y `redeem`, más de 100 movimientos y el aislamiento de
cuentas propias, inactivas, de otro usuario o de tenant inactivo. También
finaliza con `ROLLBACK`.

La descripcion completa del contrato, riesgos, reversibilidad y gates se
encuentra en [docs/database/baseline.md](../docs/database/baseline.md). El
snapshot legacy sanitizado esta en
[docs/database/legacy-schema-relevamiento.md](../docs/database/legacy-schema-relevamiento.md).
