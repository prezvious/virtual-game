# Supabase Fresh Setup

Use `virtual_harvest_fresh_setup.sql` when you want to initialize a brand-new Supabase database from scratch for the full Virtual Harvest platform.

Regenerate it after migration changes with:

```bash
npm run build-supabase-baseline
```

Rules:

- Use the fresh setup SQL only on an empty database or after a full reset.
- Keep `supabase/migrations/` for incremental updates and deployment history.
- Do not replace migration history with the fresh setup file.
