---
paths:
  - "**/migrations/**"
  - "**/migrate/**"
  - "**/supabase/migrations/**"
  - "**/prisma/**"
  - "**/alembic/**"
  - "**/db/**"
  - "**/*.sql"
  - "**/schema.*"
---

# Databases and migrations

Every file here is Yellow tier. Run the `db-migration` skill. Running a migration against a shared or production database is Red tier.

## Migrations

- Every schema change is a migration file in version control. Never change a schema by hand.
- Never edit a migration that already ran on a shared environment. Add a new one.
- Each migration is reversible, or the PR states why it is not and how to recover.
- Destructive changes take two steps across two releases (expand, then contract):
  1. Add the new column or table. Write to both. Backfill.
  2. In a later release, stop reads of the old one, then drop it.
- Never rename or drop a column that running code still reads.
- Large tables: add indexes concurrently (`CREATE INDEX CONCURRENTLY` in Postgres). Backfill in batches. Avoid long locks.
- Set `NOT NULL` only after the backfill.
- Test migrations up and down on a local database (`supabase db reset`, `prisma migrate dev`, `alembic upgrade head` then `downgrade -1`).

## Access control in the database

- Postgres with an exposed API (Supabase, PostgREST, Hasura): enable RLS on every new table in the same migration that creates it.
- Write a policy per operation. Use `auth.uid()` (or the tenant claim) in `USING` and `WITH CHECK`.
- `SECURITY DEFINER` functions: set `search_path` explicitly, check the caller inside, and revoke `EXECUTE` from `public` and `anon` unless needed.
- Views over RLS tables use `security_invoker = true`.
- Grant the least privilege to app roles. The app role never owns the schema.

## Data safety

- Constraints in the database: foreign keys, `NOT NULL`, `CHECK`, and unique indexes. Do not rely only on app code.
- Store money as integer minor units or `numeric`. Never as float.
- Store timestamps as `timestamptz` in UTC.
- Encrypt sensitive columns at rest when the data class needs it. Keep keys outside the database.
- Seed and test data are fake. Never copy production data into dev or test.

## Tests

- A test for each RLS policy, run as at least two users and as `anon`.
- A test that the migration applies cleanly from an empty database.

## Done means

- [ ] Migration file added. No old migration edited.
- [ ] Reversible, or the PR explains the recovery plan.
- [ ] RLS on and policies tested for every new table.
- [ ] No destructive change in a single step.
- [ ] The PR lists the migration under `Security-Review:`.
