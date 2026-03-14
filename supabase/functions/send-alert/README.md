# send-alert Edge Function

Last updated: March 15, 2026

This Supabase Edge Function sends alert emails through Resend.

It is called by the Next.js route `/api/alerts`, not directly by browser game clients.

## Required Secret

```bash
supabase secrets set RESEND_API_KEY=your_resend_api_key
```

## Current Behavior (Important)

In `index.ts`, sender and recipient are currently hardcoded:

- From: `FishingGame Alert <onboarding@resend.dev>`
- To: `unvermicular@gmail.com`

So only `RESEND_API_KEY` is required for this function to run as currently written.

## Deploy

```bash
supabase functions deploy send-alert --no-verify-jwt
```

`--no-verify-jwt` is required because alert traffic can come from non-authenticated players through the platform alert proxy.
