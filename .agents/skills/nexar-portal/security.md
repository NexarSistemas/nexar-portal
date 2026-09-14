# Seguridad

Diseñar el repositorio como público desde ahora. Nunca versionar secretos,
tokens, passwords, credenciales, `.env`, `service_role` ni datos reales
sensibles. Una clave pública de cliente solo se incluye cuando su exposición sea
parte explícita del modelo de seguridad.

El objetivo de identidad es `auth.users -> perfiles -> rol/vendedor_id`. La
autorización se implementa con RLS y ownership, nunca mediante botones del
frontend ni metadata editable. Supabase Edge Functions es la opción preferida
para secretos y operaciones privilegiadas; Netlify requiere justificación
técnica concreta.

No reutilizar passwords, sesiones, RPC ni secretos compartidos del Portal
Vendedor legacy. Las funciones `SECURITY DEFINER` deben ser mínimas,
restringidas y revisadas. Las operaciones críticas deben ser auditables e
idempotentes.

Antes de hacer público el repositorio, auditar el árbol actual y el historial
Git, incluidos secretos que ya se hayan eliminado, y rotar cualquier secreto que
pudiera haberse expuesto.
