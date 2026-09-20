# Relevamiento del schema legacy

## Alcance del snapshot

Snapshot sanitizado del schema `public` verificado el **2026-09-14**. Describe
la estructura que condiciona M00–M07; no contiene PII, UUID, hashes, sesiones,
tokens ni valores de policies. Es un snapshot, no una prueba de estado actual:
debe revalidarse antes de cualquier operacion destructiva, en especial M04 y
M07.

## Inventario y relaciones relevantes

| Tabla | Rol para el baseline |
| --- | --- |
| `admin_audit_log` | Auditoria legacy a preservar integramente. |
| `comisiones` | Movimientos de prueba saneables; recibe relaciones canonicas nullable en M03. |
| `licencias` | Movimientos de prueba saneables; conserva `license_key` y `codigo_vendedor`. |
| `newsletter_preference_requests` | Fuera del saneamiento M04. |
| `pagos` | Movimientos de prueba saneables; recibe relaciones canonicas nullable en M03. |
| `portal_password_recovery_requests` | Recuperacion legacy operativa; se preserva. |
| `portal_vendedor_sessions` | Sesiones legacy operativas; se preservan las de la identidad maestra. |
| `precios_planes` | Catalogo comercial legacy en coexistencia y fuente de M04. |
| `referidos` | Datos de prueba saneables. |
| `solicitudes_demo`, `solicitudes_licencia`, `solicitudes_soporte`, `solicitudes_upgrade`, `solicitudes_vendedores` | Solicitudes actuales de prueba saneables. |
| `suscripciones_novedades` | Fuera del saneamiento M04. |
| `vendedores` | Identidad comercial legacy en coexistencia. |

Las PK relevantes para M00–M07 incluyen `vendedores.id` y `pagos.id` UUID. Las
FK verificadas son:

| Relacion | `ON DELETE` | Efecto operativo |
| --- | --- | --- |
| `referidos.vendedor_id -> vendedores.id` | `RESTRICT` | M04 elimina referidos antes de vendedores de prueba. |
| `portal_vendedor_sessions.vendedor_id -> vendedores.id` | `CASCADE` | Las sesiones legacy siguen bloqueando M07; M04 preserva las de la identidad maestra. |
| `portal_password_recovery_requests.vendedor_id -> vendedores.id` | `SET NULL` | M04 no elimina ni modifica recuperaciones; aborta si una referencia al vendedor de prueba exigiria alterarlas. |

`vendedores.codigo_vendedor` identifica la entidad comercial real. M04 resuelve la identidad maestra dentro de la transacción y no versiona su UUID. Las columnas `password_hash`, `password_change_required` y
`ultimo_login` siguen siendo auth legacy operativo. `vendedores.es_admin` se
conserva mientras existan consumidores externos.

## Catalogo, restricciones e identidades

`precios_planes` conserva `producto`, `plan_comercial`, `moneda`, `monto`,
`tipo_cobro`, `estado`, `vigencia_desde` y `vigencia_hasta`. Los productos
legacy permitidos son `nexar-tienda` y `nexar-finanzas`; sus nombres canonicos
son respectivamente **Nexar Comercio** y **Nexar Finanzas**. Los planes
comerciales son `BASICA`, `PRO` y `FULL`; `FULL` tiene actualmente
`plan_tecnico = MENSUAL_FULL`, que no se migra como codigo canonico.

M04 valida los codigos, los campos requeridos, vigencias y ausencia de
duplicados por producto, plan comercial y vigencia antes de borrar. Copia el
historial completo a `precios`, con `monto -> importe` y
`tipo_cobro -> modalidad_cobro`, sin alterar `precios_planes`.

Las tablas `solicitudes_demo`, `solicitudes_licencia`, `solicitudes_soporte` y
`solicitudes_vendedores` tienen `id` identity. M04 solo reinicia cada identity
si, despues del saneamiento, su tabla esta vacia. `solicitudes_upgrade.id` es
UUID y no tiene secuencia que reiniciar.

Las constraints canonicas que condicionan M03 son `planes_id_producto_id_key`,
`licencias_plan_requiere_producto_check` y
`licencias_plan_producto_fkey`: un plan de licencia requiere producto y debe
pertenecer a ese producto. Las relaciones de M03 permanecen nullable; M07 no
las endurece masivamente sin backfill y semantica final demostrados.

Los indices y constraints se verifican mediante las consultas de
`supabase/validation/m00.sql` a `m07.sql`. No se documentan nombres ni valores
de objetos de seguridad que pudieran exponer secretos. Los triggers legacy no
son alterados por este baseline; su inventario debe volver a consultarse antes
de un cambio que dependa de sus side effects.

## RLS, RPC y coexistencia

Existen policies legacy basadas en secretos compartidos; sus valores no se
incluyen en el repositorio. `public.portal_dashboard_vendedor(text)` es
`SECURITY DEFINER` y pertenece al Portal Vendedor legacy. M06 reemplaza solo la
lectura general `authenticated` de `solicitudes_upgrade` por una policy
administrativa basada en `app_private.es_admin()`; conserva el INSERT `anon`
necesario para solicitudes externas. No endurece otras policies legacy.

| Clasificacion | Objetos o datos |
| --- | --- |
| Conservar | `admin_audit_log`, `precios_planes`, la identidad maestra, su auth y sesiones, recuperaciones de password, newsletter y suscripciones. |
| Evolucionar | `vendedores`, `pagos`, `licencias`, `comisiones` con columnas/FK nullable de M03. |
| Sanear en M04 aprobada | Datos de prueba de licencias, pagos, comisiones, referidos, solicitudes enumeradas y el vendedor de prueba. |
| Retirar solo en M07 aprobada | `portal_dashboard_vendedor(text)`, policies `portal_secret_*`, sesiones, recuperacion propia, columnas de auth propia y secretos compartidos mediante una operacion externa. |

## Consumidores externos que bloquean M07

Existen consumidores externos legacy del Portal Vendedor y del panel administrativo anterior. Su inventario detallado debe mantenerse fuera de esta documentación pública y revalidarse antes de M07.

Ninguno de esos consumidores se modifica en este repositorio. M07 sigue
abortando hasta que Auth se provisione controladamente, exista un perfil activo
vinculado a la identidad maestra, se validen funcionalidad y RLS, se retiren o reemplacen los consumidores legacy necesarios,
se revalide el inventario externo y se otorgue aprobacion
explicita de retiro.
