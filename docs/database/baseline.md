# Baseline de datos de Nexar Portal

## Alcance y estado

Este documento describe el baseline SQL versionado en `supabase/migrations`.
Al crear esta version no se ejecutaron migraciones, SQL, conectores ni ninguna
operacion contra Supabase remoto. Los archivos no implican que el modelo este
desplegado.

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
  -> provision manual y controlada de Auth para RONA596
  -> vinculacion perfiles.vendedor_id
  -> validacion funcional y de RLS
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

## M04: saneamiento condicionado

La regla de negocio indica conservar solo la entidad maestra `RONA596` y su UUID
existente. Sus movimientos de prueba, junto con licencias, pagos, comisiones,
solicitudes y referidos de prueba, pueden eliminarse una vez aprobado el plan
de saneamiento. Las secuencias deben reiniciarse solo si sus tablas quedan
vacías.

El checkout no contiene un dump, migraciones anteriores ni el esquema legacy;
por ello no demuestra la columna de identidad comercial de `RONA596`, los FK de
sus movimientos ni los nombres de tablas de solicitudes. M04 se deja bloqueada
en vez de inventar `DELETE`, UUID o relaciones. Para completarla se requiere un
relevamiento aprobado que defina el orden de borrado, preservacion del UUID y
reset de las secuencias reales. Tampoco se insertan productos, planes ni precios
inferidos: faltan sus valores aprobados.

## M06 y M07: seguridad y retirada legacy

M06 habilita RLS en las tablas canonicas y en las tablas legacy que reciben
relaciones canonicas (`pagos`, `licencias`, `comisiones`). Las policies separan
administradores de vendedores por `perfiles.rol` y `perfiles.vendedor_id`;
autorizan ownership mediante FK, nunca por frontend, secretos compartidos ni
metadata editable.

No se habilita RLS en los demás objetos legacy sin inventario de consumidores.
La prueba funcional debe comprobar tanto las operaciones administrativas como
las lecturas de cada vendedor antes de considerar M06 operativa.

M07 requiere provisionar manualmente el Auth de RONA596, vincular su perfil,
validar el flujo y RLS, y demostrar que ya no hay consumidores de sesiones,
passwords, RPC ni policies legacy. Solo entonces puede reemplazarse su guard por
el DDL de retiro revisado. El baseline no elimina esas estructuras de manera
anticipada.

## Validacion y reversibilidad

Las consultas en `supabase/validation/m00.sql` a `m07.sql` son de lectura y se
ejecutan despues de cada paso en el entorno controlado. Verifican tablas,
columnas, tipos, constraints, indices, RLS, policies, grants y las condiciones
de los gates. No sustituyen una validacion funcional contra consumidores reales.

M00 solo valida. M01, M02, M03, M05 y M06 son reversibles mediante una migracion
posterior revisada que retire solo objetos sin dependencias ni consumidores. M04
destruye datos de prueba y exige respaldo/plan aprobado. M07 es parcialmente
destructiva y exige respaldo, inventario de consumidores y validacion posterior.
No se debe revertir RLS ni borrar Auth legacy como accion automatica.
