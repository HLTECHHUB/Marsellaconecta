# Setting up new-business email alerts

This adds an email to you every time someone submits a new business,
so nothing sits unnoticed in "Pendiente Validacion". Takes about
10 minutes, all through the Supabase and Resend dashboards.

## 1. Create a free Resend account

1. Go to https://resend.com and sign up (free tier: 100 emails/day,
   3,000/month — more than enough for this).
2. Once logged in, go to **API Keys** → **Create API Key**. Copy it —
   you'll need it in step 3.

### About the "from" address

Resend's free tier lets you send from `onboarding@resend.dev`
immediately, but **only to the email address you signed up with**.
That's fine to start — it'll work for you receiving your own alerts.

If you want to send from `notificaciones@hl-techhub.com` (or similar)
instead, go to **Domains** in Resend and verify `hl-techhub.com` by
adding the DNS records they give you (a few TXT/CNAME records at
wherever you manage hl-techhub.com's DNS). Not required to get this
working today — just needed if you want a branded sender later.

## 2. Deploy the Edge Function

The function code is in `supabase/functions/notify-new-business/index.ts`.

**Easiest path — Supabase Studio (no CLI needed):**
1. Supabase Studio → **Edge Functions** (left sidebar) → **Create a new function**
2. Name it exactly: `notify-new-business`
3. Paste in the contents of `index.ts`
4. Deploy

**Alternative — Supabase CLI** (if you prefer, e.g. from the same
Codespace you used for the migration script):
```bash
npx supabase login
npx supabase link --project-ref kydazssjktgsagayuupo
npx supabase functions deploy notify-new-business
```

## 3. Add the secrets

Supabase Studio → **Edge Functions** → **Secrets** (or **Settings** tab
depending on your dashboard version) → add:

| Secret | Value |
|---|---|
| `RESEND_API_KEY` | the key you copied in step 1 |
| `NOTIFY_EMAIL` | the email you want alerts sent to |
| `FROM_EMAIL` | `onboarding@resend.dev` (or your verified domain address) |

## 4. Wire it up so it actually triggers

This is what makes the function fire when a business is inserted.
There are two ways to do this — pick whichever works for you.

### Option A: SQL (recommended — most reliable)

Database Webhooks in the dashboard are just a convenience wrapper
around a Postgres trigger + the `pg_net` extension. You can create
that trigger directly instead of hunting for the UI:

Run **`notify-webhook-trigger.sql`** in the SQL Editor. That's it —
it enables `pg_net` and creates the trigger in one step.

### Option B: Dashboard UI (if you'd rather click through it)

The location can be easy to miss since it's nested — in Supabase
Studio's left sidebar, click **Database** (not Edge Functions), then
look for a **Webhooks** tab among the sub-sections in that area
(alongside Tables, Triggers, Extensions, Backups, etc.). If you
still can't find it, Option A does the exact same thing via SQL
and is one copy-paste, so no need to keep hunting.

1. Database → Webhooks → **Create a new webhook**
2. Name: `notify-new-business`
3. Table: `businesses`
4. Events: check **Insert** only
5. Type: **Supabase Edge Functions**
6. Select the `notify-new-business` function
7. Save

## 5. Test it

Submit a test business through `register.html` on your live site.
You should get an email within a few seconds. If not:

- Supabase Studio → **Edge Functions** → `notify-new-business` → **Logs**
  will show you the actual error (usually a missing/wrong secret, or
  Resend rejecting the "to" address if you haven't verified a domain
  yet — see the note in step 1).
- If you used Option A (SQL trigger), you can also run this in the
  SQL Editor to see whether the trigger even fired and what response
  it got back:
  ```sql
  select id, status_code, content, created
  from net._http_response
  order by created desc
  limit 5;
  ```
  `status_code` 200 means it worked — check your inbox (and spam
  folder). Anything else means the HTTP call itself failed before
  it ever reached Resend.

## Later: WhatsApp instead of / in addition to email

A WhatsApp alert is possible but meaningfully more setup (Meta
Business API approval, a WhatsApp Business number, template message
approval) — not something achievable in one sitting the way email is.
If you want to go that route later, Twilio's WhatsApp API is the
most common shortcut and I'm happy to help wire it up when you're
ready to create that account.
