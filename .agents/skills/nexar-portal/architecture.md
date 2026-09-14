# Arquitectura

El frontend futuro es estático y se publicará en GitHub Pages; no se ha
versionado un framework frontend, por lo que no debe elegirse ni suponerse uno.
GitHub Pages nunca contiene secretos ni lógica privilegiada.

Las operaciones normales se diseñan con Supabase Auth y RLS. Los secretos y las
operaciones privilegiadas priorizan Supabase Edge Functions. Netlify Functions
solo se justifican ante una necesidad técnica concreta o una integración legacy.

La coexistencia con Nexar Admin, Portal Vendedor, Nexar Pagos y otros
consumidores legacy es gradual mientras corresponda. No crear nuevas
dependencias de autenticación compartida legacy y mantener una única fuente de
verdad por responsabilidad.
