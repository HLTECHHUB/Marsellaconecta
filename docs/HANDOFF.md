# Conecta Marsella — Handoff (corrected)

**Revised:** October 12, 2026
**What this is:** A corrected version of `MARSELLA_CONECTA_COMPLETE_HANDOFF.md`, rewritten to match the files actually delivered and the repositories actually inspected. Anything I could not confirm is labeled **UNVERIFIED** rather than stated as fact.

---

## 1. Corrections to the previous handoff

| Previous handoff said | Actual state |
|---|---|
| `admin.html` is "not yet built" / planned | **Built.** Four tabs: Negocios, Vecinos, Promociones, Estadísticas. Gated by a real `admins` table and `is_admin()` check, not a hidden page. |
| RLS "not enabled yet" | **Enabled on every table** in the delivered SQL, with explicit policies (section 5). *Whether the SQL has been run on the live project is UNVERIFIED for most scripts; see section 8.* |
| Passwords stored as "plaintext/simple hash" | The **old Google Sheets version** stored plaintext passwords in a publicly published CSV. The Supabase version uses **Supabase Auth (hashed)**. Old passwords were deliberately **not migrated**; every migrated neighbor must sign up again with the same email. |
| `businesses.dueno_id`, `profiles.tipo_usuario` | Actual columns are `businesses.owner_profile_id`. There is **no** `tipo_usuario`; admin status lives in the separate `admins` table. |
| `estado` values include `'Pendiente'` | Actual value is `'Pendiente Validacion'`. Also `'Activo'`, `'Rechazado'`. (`'Verificado'` is still read by the frontend as active.) |
| Owner DUI / email stored on the business | Stored in a separate **`business_private`** table that the public cannot read. |
| `events_log.id` is UUID | It is `bigint generated always as identity`. |
| `register-user.html`, `reset-password.html`, `mi-negocio.html` are "future" | **All built.** |
| `plans.html` exists with four tiers (Gratis/$5/$12/$25, 20% annual discount) | **`plans.html` was never built in this build, and `index.html` links to it (dead link).** The registration form offers three tiers only: Gratuito $0, Básico $5, Pro $12. There is no Premium tier in the form, the admin dropdown, or the database defaults. |
| Credentials go in `config.js` | The delivered pages have the Supabase URL and anon key **hardcoded in each HTML file** (`index`, `register`, `register-user`, `reset-password`, `admin`, `mi-negocio`). `config.js` exists only in a different repo (section 2). |
| Repo is `hltechhub/Marsella-Conecta`, Pages URL `hltechhub.github.io/Marsella-Conecta/` | See section 2. The live site is on a custom domain, and two different repos exist. |
| Contact: "Milton (Pithy Marketing), Savannah GA, operations.petbizexperts@gmail.com" | **Wrong.** Correct contact: info@hl-techhub.com, based in El Salvador. Admin account: milcooffices1@gmail.com. |
| Email confirmations via Formspree/EmailJS | Not used. An admin alert is built as a Supabase Edge Function + Resend (section 7). There is **no** confirmation email to the business owner. |

---

## 2. Repositories and hosting: UNRESOLVED

Three identifiers appear in the history. They are not the same thing.

| Identifier | What it is |
|---|---|
| `strategygd80/marsella-conecta` | The repo the project started from. Contains the **Google Sheets + Apps Script** version, a `CNAME` for `marsella.hl-techhub.com`. Most likely what serves the live custom domain. **Not re-inspected this session.** |
| `HLTECHHUB/Marsellaconecta` | Inspected October 12. Last commit Sept 22. Files: `index.html`, `admin.html`, `business.html`, `product-upload-form.html`, `config.js`. **A different build**: marketplace with products, different Supabase project, different data model (below). |
| `marsella.hl-techhub.com` | Live custom domain. Which repo deploys it is **UNVERIFIED**. |

**The two builds are not versions of each other:**

| | Delivered build (this handoff) | `HLTECHHUB/Marsellaconecta` |
|---|---|---|
| Supabase project | `kydazssjktgsagayuupo` | `tlvnolvfrujhlrffdmeb` |
| Tables used | `businesses`, `profiles`, `business_private`, `promotions`, `events_log`, `admins` | `businesses`, `products`, `product_categories`, `featured_businesses`, `promotions`, `analytics_events`, `users`, `profiles` |
| Credentials | Hardcoded per page | `config.js` |
| Extra pages | register, register-user, reset-password, mi-negocio | `business.html`, `product-upload-form.html` |

**None of the delivered files are in `HLTECHHUB/Marsellaconecta`.** Its `index.html` and `admin.html` differ from ours. Do not overwrite either repo until the owner decides which build is canonical or how to merge (products functionality exists only in the other repo).

---

## 3. Architecture

- **Frontend:** static HTML/CSS/vanilla JS, no build step, Supabase JS v2 via `esm.sh`. Fonts: Syne (headings), DM Sans (body).
- **Backend:** Supabase (Postgres + Auth + Storage + one Edge Function).
- **Hosting:** GitHub Pages. Custom domain `marsella.hl-techhub.com`.
- **Country code** for WhatsApp/tel links: `503` (El Salvador).
- **Public data flow:** `index.html` reads `businesses` and `promotions` with the anon key; RLS decides what is visible.

---

## 4. Files in the delivered build

| File | Purpose |
|---|---|
| `index.html` | Directory: hero search with live dropdown and quick chips, category grid (SVG icons), promotions grid, filters, business cards with optional photo, login/profile modals, event logging. Shows a red banner if Supabase fails to load (falls back to one sample listing). |
| `register.html` | 3-step business registration. Optional photo (auto-compressed). Public insert; new rows are forced to `Pendiente Validacion`. |
| `register-user.html` | Neighbor signup via Supabase Auth. Profile fields travel as auth metadata; a DB trigger creates or links the profile. |
| `reset-password.html` | Password reset landing page for the Supabase recovery email link. |
| `mi-negocio.html` | Owner self-service: log in, claim a listing by confirming the registration email, edit phone/hours/description/photo. |
| `admin.html` | Admin dashboard (see section 6). |
| `migrate-from-sheets.js`, `package.json` | One-time Google Sheets to Supabase migration. Ran once: 47 businesses, 5 of 7 neighbor profiles (2 skipped, likely duplicate/blank emails; not reviewed). |
| `supabase-schema.sql` | Core tables, RLS, triggers. |
| `promotions-schema.sql` | `promotions` table + `promo-images` bucket. |
| `admin-schema.sql` | `admins` table, `is_admin()`, admin policies, admin storage policies. |
| `admin-stats-schema.sql` | Lets admins read `events_log`. |
| `business-images-schema.sql` | `businesses.imagen_url` + `business-images` bucket + policies. |
| `claim-business-schema.sql` | `claim_business()` function. |
| `notify-webhook-trigger.sql` | Trigger that calls the Edge Function on new businesses. |
| `supabase/functions/notify-new-business/index.ts`, `NOTIFY-SETUP.md` | Admin email alert via Resend, with setup steps. |

**Known dead link:** `plans.html` (referenced in the `index.html` nav; file does not exist in this build).

---

## 5. Database (as defined by the delivered SQL)

**`profiles`** — `id`, `auth_user_id` (unique, to `auth.users`), `nombre`, `apellido`, `email` (unique, not null), `whatsapp`, `quartier`, `source`, `estado` (default `Activo`), `migrated` (bool), `created_at`.
**`businesses`** — `id`, `owner_profile_id`, `nombre`, `categoria`, `sub_categoria`, `barrio`, `telefono`, `descripcion`, `estado` (default `Pendiente Validacion`), `estrellas`, `horario`, `plan` (default `Gratuito`), `origen`, `imagen_url`, `created_at`.
**`business_private`** — `business_id` (PK), `propietario`, `dui`, `email`, `created_at`. Public can insert, nobody but admins can read.
**`promotions`** — `id`, `titulo`, `descripcion`, `negocio_nombre`, `imagen_url`, `cta_text`, `cta_url`, `expira_at`, `activo`, `orden`, `created_at`.
**`events_log`** — `id` (bigint), `profile_id`, `evento_tipo`, `valor_busqueda`, `negocio_nombre`, `created_at`. Public insert only; admins read.
**`admins`** — `id` (PK, to `auth.users`), `email`, `created_at`.

**Event types logged by the site:** `Busqueda_Palabra`, `Busqueda_Boton`, `Click_Llamar`, `Click_WhatsApp`, `Login_Exitoso`, `Cierre_Sesion`, `Edicion_Perfil_Exitoso`, `Solicitud_Recuperacion_Clave`.

**RLS summary**
- `profiles`: user reads/updates own row; admins read/update all. No client insert (trigger only).
- `businesses`: public reads everything except `Rechazado`; anyone can insert; owner updates own; admins read/update/delete all. A trigger forces new rows to `Pendiente Validacion` for non-admins and stops non-admins changing `estado`.
- `business_private`: public insert; admin read/update.
- `promotions`: public reads `activo = true`; admin insert/update/delete.
- `events_log`: public insert; admin select.
- Storage: `promo-images` and `business-images` are public-read. `business-images` allows public upload (listings are moderated before going live); admin-only update/delete. `promo-images` writes are admin-only.

**Functions / triggers:** `handle_new_user()` (links a migrated profile by email on signup, else creates one), `is_admin()`, `enforce_business_review_status()`, `claim_business(uuid, text)` (checks the private email server-side), `trigger_notify_new_business()`.

---

## 6. Roles and admin

- **Vecino:** Supabase Auth account + `profiles` row.
- **Business owner:** a vecino who has claimed a business (`owner_profile_id` set).
- **Admin:** a row in `admins`. Created by: add the user in Supabase Studio, Authentication, Users (Auto Confirm on), then insert their UID into `admins`. An admin account exists for `milcooffices1@gmail.com`.
- **Admin dashboard:** approve/reject/edit/delete businesses (shows private owner data), edit/suspend neighbor profiles, create/edit/hide/delete promotions with image upload, activity stats (searches, logins, logouts, call/WhatsApp clicks, top terms, top businesses, recent feed).
- **Not possible from the browser by design:** resetting a user's password or deleting their login (needs the service role key).

---

## 7. Setup order for a fresh Supabase project

1. `supabase-schema.sql`
2. `promotions-schema.sql`
3. `admin-schema.sql`, then create the admin user and insert into `admins`
4. `admin-stats-schema.sql`
5. `business-images-schema.sql`
6. `claim-business-schema.sql`
7. Optional alerts: follow `NOTIFY-SETUP.md` (Resend account, deploy function, set `RESEND_API_KEY` / `NOTIFY_EMAIL` / `FROM_EMAIL`), then run `notify-webhook-trigger.sql`
8. Migration (once): `migrate-from-sheets.js` with the service role key set only in the terminal environment
9. Put the project URL and anon key into each HTML file

Auth setting to decide: email confirmation on or off. The signup flow handles both.

---

## 8. Verified vs unverified

**Confirmed**
- Migration ran: 47 businesses, 5 of 7 profiles.
- Admin login works (so `admins` and `is_admin()` exist and an admin row was inserted).
- Trigger `on_business_created_notify` exists on the live project.
- Layout overflow fix (grid `minmax(min(...,100%),1fr)` plus `overflow-x: hidden`) is in the delivered files.

**UNVERIFIED (could not check; the Supabase connection available here only reaches an unrelated project)**
- Whether `promotions-schema.sql`, `admin-stats-schema.sql`, `business-images-schema.sql`, `claim-business-schema.sql` were run.
- Whether the Edge Function is deployed and its secrets set. The one check made showed `net._http_response` empty, meaning no notification had fired yet.
- Whether the latest HTML files are what is deployed on `marsella.hl-techhub.com`.
- Whether the **search bar** works on the live site. Two real bugs were fixed (unguarded `.replace()` on a null name) but the original report was never reproduced; a stale cached file remains the leading suspect.
- Whether the 2 skipped profiles need manual entry.

---

## 9. Open items

**Security**
- The Supabase **service role key was pasted into chat twice**, and the second paste matched the first, so rotation may not have happened. Rotate it and never paste it again.
- The admin password is a guessable pattern. Change it.
- `business_private` holds DUI numbers in plain columns. Access-restricted by RLS, not encrypted. Consider app-level encryption or dropping DUI collection.
- Add a short privacy note to the registration forms.

**Product**
- Neighbors with migrated profiles (5) must re-register with the same email before they can log in. No one has been notified yet.
- Build `plans.html` or remove the nav link. Decide whether the Premium tier ($25) and annual discount from the old handoff are real; they are not in the form, admin, or database.
- Owner confirmation email is not built.
- Reviews and ratings by residents are not built (`estrellas` is set by admin only).
- Most of the 47 migrated businesses have no photo. Owners can add one via `mi-negocio.html` once they claim a listing.

**Decision needed**
- Which repo is canonical, and whether to merge the products functionality from `HLTECHHUB/Marsellaconecta` (section 2).

---

## 10. Design system (unchanged from the previous handoff, confirmed against the files)

| Name | Hex |
|---|---|
| Primary blue | `#0d67a7` |
| Nav / hover blue | `#1c74b3` |
| Green (CTAs, verified) | `#159957` |
| Orange (promo expiry, featured) | `#e48727` |
| Gold (premium badge) | `#c9a84c` |
| Background | `#f4f6f9` |
| Text / muted | `#101828` / `#667085` |
| Border | `#e3e7ee` |

Five pages define these as CSS variables (`index`, `register`, `register-user`, `admin`, `mi-negocio`). `reset-password.html` uses a reduced set (blue, text, border) with no green. "Featured" is shown when `plan` contains `pro`, `premium`, or `destacado`.

**Image sizes:** promo and business photos 800×600 px (4:3). Uploads are auto-resized client-side to max 1200 px and re-encoded as JPEG (~82%).

---

## 11. Roadmap (updated)

- **Done:** directory + search, Supabase migration, real auth, registration, owner claim/self-service, admin dashboard, promotions with image upload, activity analytics, layout fixes.
- **Next:** resolve repo/hosting question; confirm which SQL scripts are live; deploy Edge Function alert; notify migrated neighbors; build or remove `plans.html`; rotate keys and change admin password.
- **Later:** owner confirmation emails, resident reviews, owner analytics, WhatsApp alerts (Meta Business API), payment tracking for paid tiers, SEO (the site is client-rendered, so individual listings index poorly).


## Repo decision (Oct 2026)
`HLTECHHUB/Marsellaconecta` is the canonical repo. It was restructured onto the Supabase Auth + RLS core (see README). The legacy `users` table / client-side hash login and `admin` default password were removed. Contact: info@hl-techhub.com, El Salvador.
