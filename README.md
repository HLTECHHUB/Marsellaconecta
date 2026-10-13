# Marsella Conecta

Directorio de negocios y vecinos de la Colonia Marsella, El Salvador.
Contacto: info@hl-techhub.com · Static site (GitHub Pages) + Supabase (Auth, Postgres/RLS, Storage, Edge Functions).

## Estructura
```
index.html                 Directorio público (búsqueda, promociones, negocios)
pages/                     register, register-user, reset-password, mi-negocio,
                           product-upload, plans, admin
assets/js/config.js        URL + anon key públicos (nunca service_role)
assets/js/supabase.js      Cliente compartido
assets/css/theme.css       Variables de color/tipografía
sql/01…08-*.sql            Migraciones: ejecutar en orden en el SQL Editor
supabase/functions/        notify-new-business (Resend)
scripts/                   migrate-from-sheets.js (migración única desde Google Sheets)
docs/                      HANDOFF.md, NOTIFY-SETUP.md
```

## Puesta en marcha
1. Crear proyecto Supabase; ajustar `assets/js/config.js`.
2. Ejecutar `sql/01` a `sql/08` en orden (07 requiere desplegar la función, ver docs/NOTIFY-SETUP.md).
3. Auth → URL Configuration: añadir `https://hltechhub.github.io/Marsellaconecta/pages/reset-password.html` a Redirect URLs.
4. Crear usuario admin en Authentication → Users e insertar su UID en `public.admins`.
5. Activar GitHub Pages (rama main, raíz).

## Seguridad
- Sin contraseñas en el repo ni hashes en cliente: login con Supabase Auth.
- Datos privados (DUI, email del dueño) en `business_private`, solo escritura pública.
- Rotar cualquier `service_role` que se haya compartido; usarla solo en scripts locales.
