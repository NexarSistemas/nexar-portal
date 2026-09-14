# Flujos comerciales y coexistencia

Una venta contiene sus `venta_items`. Cada pago se vincula explícitamente a su
venta; el cumplimiento o la licencia se deriva de la operación correspondiente;
y la comisión se vincula a vendedor, venta y pago cuando corresponda.
`external_reference` es interoperabilidad, no una FK lógica principal.

Definir un único responsable por cada side effect e idempotencia ante callbacks
o webhooks repetidos. Las notificaciones se envían después de confirmar la
operación: fallos de Telegram o email no revierten una operación comercial ya
confirmada.

La migración desde legacy es gradual, sin big-bang, y conserva a los
consumidores existentes hasta tener evidencia para su retirada.
