# Laguna College ICT Services Portal: MS Teams Support Portal

Next.js (App Router) + TypeScript + Tailwind CSS v4 + Supabase (Postgres, Auth, Storage). Ready for Vercel.

## 1. Supabase setup

1. Create a Supabase project.
2. Open **SQL Editor**, paste `supabase/schema.sql`, and run it. This creates the `tickets` table, the atomic
   ticket-number generator, Row Level Security policies, the private `ms-teams-screenshots` bucket and the ICT staff list.
3. **Authentication → Providers → Email**: turn **off** "Allow new users to sign up" so nobody can self-register.
4. **Authentication → Users → Add user**: create each ICT staff account (email + password, auto-confirm).
5. Authorize each staff account (only people listed here can open the admin area):

   ```sql
   insert into public.ict_staff (user_id, full_name, email)
   select id, 'Juan Dela Cruz', email from auth.users where email = 'ict.admin@example.com';
   ```
   To remove access later: `update public.ict_staff set active = false where email = '...';`

## 2. Run locally

```bash
cp .env.example .env.local   # fill in the three Supabase values
npm install
npm run dev                  # http://localhost:3000
npm run build                # production build check
```

Requires Node 20.9+.

## 3. Deploy to Vercel

Import the GitHub repo, add the environment variables from `.env.example`, and deploy.
`SUPABASE_SERVICE_ROLE_KEY` must **not** have the `NEXT_PUBLIC_` prefix.

## 4. Replace the logo

`public/logo.png` is a **placeholder**. Replace it with the official Laguna College seal (square PNG, 256×256 or larger).

## How it works

| Area | Notes |
| --- | --- |
| Ticket numbers | `LC-YYYY-00001`, generated inside Postgres by a counter row with a row lock (no `COUNT`). `UNIQUE(ticket_id)` as a backstop. Counter resets each year (Philippine time). |
| File upload | Browser asks `/api/upload-url` (server validates name/type/size) → uploads straight to a private bucket with a one-time signed URL → `/api/submit` re-downloads the object and checks size and magic bytes before a ticket is created. Direct upload avoids Vercel's 4.5 MB request-body limit. |
| Screenshot rules | Required for most concerns, optional for Password Reset / Account Locked / Other, hidden for New MS Teams Account. Edit `OPTIONAL_FILE_CONCERNS` in `lib/validation.ts`. |
| Admin access | Supabase Auth session **and** an active row in `ict_staff`, checked on every page and API route. `proxy.ts` is only a first gate. Staff use their own session, so RLS applies. Staff can only update status, priority, assignee and resolution fields. |
| Service-role key | Used only in `/api/submit` and `/api/upload-url` through `lib/supabase-server.ts` (`server-only`). |
| Supporting files | `/api/admin/ticket/[id]?file=1` redirects to a 60-second signed URL for authorized staff. |
| Exports | New-accounts CSV (respects dashboard filters, always limited to New MS Teams Account) and per-ticket password-reset TXT. Neither contains any credential. CSV cells are protected against spreadsheet formula injection. |

## Business rules worth knowing

- If someone answers **No** to "Do you already have an account?", the only available request is **New MS Teams Account**. If they answer **Yes**, that option is hidden and a Laguna College email is required. This is enforced on the server too.
- Set `NEXT_PUBLIC_LC_EMAIL_DOMAIN` to require Laguna College emails to end with a given domain (leave empty to accept any valid email).
- Excel drops leading zeros when opening the CSV (09171234567 → 9171234567). Import the column as Text if that matters.

## Recommended before go-live

- Add rate limiting or a CAPTCHA (Vercel Firewall or Cloudflare Turnstile) on `/api/upload-url` and `/api/submit`. A hidden honeypot field is included but is not enough on its own.
- Files uploaded but never submitted stay under `pending/`. Schedule a cleanup of old objects in that folder.
- On Next.js 15 instead of 16, rename `proxy.ts` to `middleware.ts` and the exported function to `middleware`.
