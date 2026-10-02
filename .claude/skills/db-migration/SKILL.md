---
name: db-migration
description: Write a safe database migration. Reversible steps, expand and contract for destructive changes, batched backfills, RLS or policies on every new table, concurrent indexes, and tests against a local database only. Use for any schema change, new table, column, index, policy, or data backfill.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# /db-migration: safe schema change

**Arguments:** `$ARGUMENTS` (the schema change)

Migrations are Yellow tier. Read `.claude/rules/data-migrations.md` first. You run migrations against a local database only. Hooks block remote targets (`--linked`, `--db-url`, `db push`, `migrate deploy`).

## 1. Find the tool

Use the tool the repo already uses. Check for:
- `supabase/migrations/`: `supabase migration new <name>`, then `supabase db reset` locally
- `prisma/schema.prisma`: `npx prisma migrate dev --name <name>`
- `alembic/`: `alembic revision -m "<name>"`
- `db/migrate/`: `bin/rails generate migration <Name>`
- `migrations/` with sqlx, goose, golang-migrate, Flyway, Knex, Drizzle, or TypeORM

Never create a migration file by copying another file's timestamp. Use the generator.

## 2. Plan the change

Classify it:

| Change | Safe in one step? |
|---|---|
| Add a nullable column, add a table, add an index concurrently | Yes |
| Add a NOT NULL column with a constant default (Postgres 11+) | Yes |
| Rename a column or table | No, use expand and contract |
| Drop a column or table | No, use expand and contract |
| Change a column type | No, use expand and contract |
| Add NOT NULL to an existing column | No, add a CHECK NOT VALID, validate, then set NOT NULL |
| Add a foreign key on a big table | Add it NOT VALID, then VALIDATE in a later step |

Expand and contract, over separate PRs:
1. Expand: add the new column or table. Code writes to both.
2. Backfill: copy old data to new, in batches.
3. Switch: code reads from new.
4. Contract: drop the old column in a later PR, after a release.

One PR from an agent covers at most steps 1 to 3. The drop is a separate PR that a human schedules.

## 3. Write it

- Make each migration reversible. Write the down step, or a comment that says why it cannot reverse and what restores the data.
- Postgres indexes on existing tables: `CREATE INDEX CONCURRENTLY`, outside a transaction. Mark the migration non-transactional in the tool.
- Set a lock timeout at the top: `SET lock_timeout = '5s';`
- Backfills: batches of 1,000 to 10,000 rows by primary key, in a script or a separate migration. Never one `UPDATE` over a large table.
- Never put secrets or real user data in a migration or seed file.

## 4. Access control on new tables

Postgres and Supabase:
```sql
alter table public.<table> enable row level security;

create policy "<table> owner select" on public.<table>
  for select using (auth.uid() = user_id);
create policy "<table> owner insert" on public.<table>
  for insert with check (auth.uid() = user_id);
-- one policy per operation the app needs; none for the rest
```

- Every table with user data gets RLS in the same migration that creates it.
- `security definer` functions set `search_path` and check the caller.
- Grant the least privilege to app roles. Never grant to `anon` unless the data is public.

Other databases: put the same rules in the data access layer, with tests.

## 5. Test locally

1. Reset and apply all migrations from zero:
   ```bash
   supabase db reset          # or: alembic upgrade head on a local DB. prisma migrate reset is blocked by bash-guard; recreate the local DB with docker compose instead
   ```
2. Run the down step, then up again, if the tool supports it.
3. Run the DB tests. Add tests for each new policy: owner can, other user cannot, anon cannot. Use pgTAP (`supabase test db`) or the repo's test setup.
4. Regenerate types with the repo's command, for example `supabase gen types typescript --local`.

## 6. PR

In the `Security-Review:` section, state:
- Lock risk and the expected run time on the largest table.
- RLS or policy for each new table.
- The rollback plan.
- Any contract step left for a later PR.
