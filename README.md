# feecutter

> See exactly how much your platform fees really cost.

Compare payment platform fees side-by-side, get your annual "fee bleed" number, and find out how much you'd save by switching.

## Quick Start

1. **Clone & install**
   ```bash
   git clone https://github.com/your-org/feecutter.git
   cd feecutter
   npm install
   ```
2. **Configure environment**
   ```bash
   cp .env.example .env.local
   # Fill in Supabase, Stripe, and Resend keys
   ```
3. **Push database schema**
   ```bash
   psql "$SUPABASE_DB_URL" -f schema.sql
   ```
4. **Run dev server**
   ```bash
   npm run dev
   # http://localhost:3000
   ```

## Environment Variables

| Variable | Description |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase anon/public key |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase service role key (server-only) |
| `SUPABASE_DB_URL` | Direct Postgres connection string |
| `STRIPE_SECRET_KEY` | Stripe secret key (server-only) |
| `STRIPE_WEBHOOK_SECRET` | Stripe webhook signing secret |
| `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` | Stripe publishable key |
| `STRIPE_PRO_MONTHLY_PRICE_ID` | Stripe Price ID for Pro $9/mo |
| `STRIPE_PRO_ANNUAL_PRICE_ID` | Stripe Price ID for Pro Annual $79/yr |
| `RESEND_API_KEY` | Resend API key for transactional email |
| `RESEND_FROM_EMAIL` | Verified sender address (e.g. hello@feecutter.com) |
| `NEXT_PUBLIC_APP_URL` | Full public URL (e.g. https://feecutter.com) |

## Deploy Notes

- **Vercel**: Connect repo → add all env vars → deploy. `NEXT_PUBLIC_*` vars must be set in Vercel dashboard to be available client-side.
- **Supabase**: Create project at supabase.com, run `schema.sql` via SQL editor or `psql`. Enable Email auth provider in Auth settings.
- **Stripe**: Create products + prices, copy Price IDs into env vars. Point webhook to `https://feecutter.com/api/webhooks/stripe`.
- **Estimated cost**: Vercel Hobby (free) or Pro ($20/mo) + Supabase Pro (~$25/mo).