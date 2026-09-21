# Baseline de datos de Nexar Portal

## Alcance y estado

Este documento describe el baseline SQL versionado en `supabase/migrations`.
Al crear esta version no se ejecutaron migraciones, SQL, conectores ni ninguna
operacion contra Supabase remoto. Los archivos no implican que el modelo este
desplegado.

El inventario legacy verificado y sanitizado se encuentra en
[legacy-schema-relevamiento.md](legacy-schema-relevamiento.md). Es el snapshot
operativo del 2026-09-14 y debe revalidarse antes de M04, M07 o cualquier otra
operacion destructiva.

La relacion comercial canonica es:

```text
CLIENTE -> VENTA -> VENTA_ITEM -> PAGO -> CUMPLIMIENTO / LICENCIA -> COMISION
```

Las relaciones conocidas se persisten con UUID y FK. `external_reference` sigue
siendo interoperabilidad y no una relacion canonica. Los importes usan
`numeric(14,2)`, las cantidades `numeric(12,3)`, las fechas temporales
`timestamptz`, y los estados/roles usan `text` con `CHECK`, no ENUM.

## Orden operativo

La futura aplicacion debe respetar este orden:

```text
M00
  -> M01
  -> M02
  -> M03
  -> M04
  -> M05
  -> M06
  -> provision manual y controlada de Auth para la identidad maestra
  -> vinculacion perfiles.vendedor_id
  -> M06.5: Auth+RLS transicional de vendedores, licencias y comisiones
  -> validacion funcional y de RLS
  -> M06.6: restringe ejecución pública del RPC legacy no consumido
  -> M07
```

M07 se incluye para revisión, pero no es apta para ejecutarse inmediatamente
despues de M06. M04 y M07 contienen guards que detienen su ejecucion hasta que
exista evidencia operativa suficiente.

## Coexistencia y compatibilidad

Se mantienen las tablas legacy `vendedores`, `pagos`, `licencias`,
`comisiones`, `precios_planes`, `referidos`, solicitudes, `portal_vendedor_sessions`
y `admin_audit_log`. En particular:

- `precios_planes` no se transforma en vista ni se retira; los nuevos precios
  versionados conviven con ella.
- Las nuevas FK de M03 son nullable. No se eliminan columnas legacy ni se
  cambia `external_reference`.
- `vendedores.id` debe ser UUID y se conserva como identidad comercial.
- `admin_audit_log` permanece como fuente de auditoria.
- No se copian passwords ni se provisiona ningun usuario real de `auth.users`.
- `perfiles` vincula Auth con `vendedores` mediante `vendedor_id`; las policies
  no usan metadata editable por el usuario.

`clientes.email` no es unico y el baseline no deduplica ni fusiona clientes por
email. Cada `venta_item` conserva nombre, cantidad, precio unitario e importe
históricos, por lo que un cambio en `precios` no altera ventas anteriores.
`precios` incluye modalidad de cobro, estado y vigencia; `ventas` incluye moneda
y estado. Los `venta_items` requieren producto y descripcion, mientras que plan
y precio de catalogo de origen permanecen opcionales.

M03 agrega solamente columnas nullable y relaciones canonicas nuevas. En pagos
cubre venta, proveedor/origen, estado del proveedor, decision administrativa e
idempotencia/correlacion; en licencias, cliente, venta, item, producto y plan;
y en comisiones, vendedor, venta, pago e importe historico. No presupone ni
altera columnas legacy que el repositorio no demuestra.

## M04: saneamiento condicionado

M04 exige `app.nexar_portal_m04_approved = 'approved'` y un preflight del
snapshot: tablas y columnas requeridas, la identidad maestra esperada y un vendedor de prueba, recuperaciones de password preservables, identidades verificadas y catalogo legacy compatible. La identidad maestra se resuelve mediante `codigo_vendedor`, nunca por UUID versionado. Si una condicion cambia, aborta antes de borrar.

Con el gate y el preflight aprobados, elimina solo movimientos de prueba de
licencias, pagos, comisiones, referidos y solicitudes, y luego el vendedor de
prueba. No altera `admin_audit_log`, `precios_planes`, la identidad maestra, sus sesiones o
auth legacy, recuperaciones de password, newsletter ni suscripciones. Las
identities se reinician solo para tablas ya vacias.

El catalogo canonico inicial se deriva de `precios_planes` sin modificarla:
crea los productos Nexar Comercio y Nexar Finanzas, usa `plan_comercial` como
codigo de plan y conserva el historial de precios, moneda, importe, modalidad,
estado y vigencias. Un codigo o precio legacy incompatible hace abortar M04.

## M06, M06.5, M06.6 y M07: seguridad y retirada legacy

M06 habilita RLS solo en las tablas nuevas canonicas. Las policies separan
administradores de vendedores por `perfiles.rol`, `perfiles.activo` y
`perfiles.vendedor_id`; autorizan ownership mediante FK, nunca por frontend,
secretos compartidos ni metadata editable.

El hardening de `pagos`, `licencias` y `comisiones` queda condicionado: no se
habilita ni modifica RLS, policies o grants legacy sin inventario de consumidores
y policies existentes. La prueba funcional debe comprobar tanto las operaciones
administrativas como las lecturas de cada vendedor antes de considerar M06
operativa.

M06.5 es una capa transicional posterior a M06 y previa a M07. Habilita para
`authenticated` la lectura administrativa basada en `perfiles` y la lectura de
ownership de vendedor sobre `vendedores`, `licencias` y `comisiones`. En
las tres tablas el contrato SELECT de `authenticated` usa grants por columna:
en `vendedores`, `id`, `codigo_vendedor`, `email`, `telefono` y `alias_cbu`;
en `licencias`, `license_key`, `producto`, `usuario`, `plan`, `plan_vendido`,
`expira` y `created_at`; y en `comisiones`, `tipo`, `producto`, `license_key`,
`monto`, `estado`, `created_at` y `paid_at`. No expone columnas de Auth legacy,
operativas ni relaciones internas solo por ser necesarias para ownership. El
vendedor solo puede actualizar `email`, `telefono` y `alias_cbu` de su propia
fila mediante grants por columna y una policy de ownership. Las licencias con
`venta_id` usan la relacion canonica; solo las filas legacy sin `venta_id`
pueden resolver el vendedor por `codigo_vendedor`. Las comisiones usan
unicamente `vendedor_id`, sin inferir relaciones legacy no relevadas. No se
modifican policies `portal_secret_*`, sesiones, recuperacion, dashboard ni
columnas de Auth legacy.

M06.6 conserva `portal_dashboard_vendedor(text)` por trazabilidad, pero revoca su ejecución a `PUBLIC`, `anon` y `authenticated` después de verificar que los consumidores runtime actuales ya no lo usan. `service_role` conserva ejecución. No elimina sesiones, columnas ni otros objetos legacy y no ejecuta M07.

M07 requiere provisionar manualmente el Auth de la identidad maestra, vincular su perfil,
validar el flujo y RLS, retirar o reemplazar los consumidores legacy necesarios,
revalidar el inventario externo y aprobar expresamente el retiro. Mientras existan esos
consumidores, el guard aborta de forma intencional. El inventario concreto de
retiro incluye `portal_dashboard_vendedor(text)`, policies `portal_secret_*`,
sesiones, recuperacion propia y las columnas `password_hash`,
`password_change_required` y `ultimo_login`; `vendedores.es_admin` se conserva
por ahora. El baseline no elimina esas estructuras de manera anticipada.

## Fidelización Fase 2: acreditación de puntos

La migración incremental de Fase 2 agrega tres RPC públicas `SECURITY INVOKER`
que delegan en tres funciones `SECURITY DEFINER` dentro de `app_private`.
Todas fijan `search_path` vacío y su ejecución queda restringida a
`authenticated`:

- `fidelizacion_crear_earn` deriva el tenant desde la cuenta y exige staff
  activo `admin` u `operador` del mismo tenant. La unicidad
  `(tenant_id, idempotency_key)` devuelve la misma operación ante reintentos
  equivalentes y rechaza la reutilización con otros datos.
- `fidelizacion_obtener_earn_pendientes` usa el QR opaco para localizar el
  tenant y devuelve únicamente pendientes vigentes de la cuenta autenticada.
  Es de solo lectura: escanear nunca crea ni confirma movimientos.
- `fidelizacion_confirmar_earn` deriva la cuenta desde `auth.uid()`, valida
  QR, tenant, cuenta, tipo, estado y expiración, bloquea la operación con
  `FOR UPDATE` y crea el movimiento positivo junto con el estado
  `confirmed` en una sola transacción.

La FK compuesta entre operación y movimiento conserva la igualdad de tenant,
cuenta, tipo y puntos. `UNIQUE (operation_id)` impide un segundo movimiento
incluso ante solicitudes concurrentes. El saldo continúa derivándose como
`SUM(fidelizacion_point_movements.puntos)`; no se agrega saldo mutable ni se
modifica `public.perfiles`.

## Validacion y reversibilidad

Las consultas en `supabase/validation/m00.sql` a `m07.sql`, incluida `m06_6.sql`, son de lectura y se
ejecutan despues de cada paso en el entorno controlado. Verifican tablas,
columnas, tipos, constraints, indices, RLS, policies, grants y las condiciones
de los gates. No sustituyen una validacion funcional contra consumidores reales.

M00 solo valida. M01, M02, M03, M05 y M06 son reversibles mediante una migracion
posterior revisada que retire solo objetos sin dependencias ni consumidores. M04
destruye datos de prueba y exige respaldo/plan aprobado. M07 es parcialmente
destructiva y exige respaldo, inventario de consumidores y validacion posterior.
No se debe revertir RLS ni borrar Auth legacy como accion automatica.
