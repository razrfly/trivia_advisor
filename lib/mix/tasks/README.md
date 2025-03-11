# Mix Tasks

This directory contains custom mix tasks for the TriviaAdvisor application.

## Database Sync Task

### `mix sync_db`

Syncs your local development database with the production database from Supabase.

#### Prerequisites

- PostgreSQL client tools (`pg_dump` and `pg_restore`) must be installed on your system
- `.env` file with `SUPABASE_DATABASE_URL` properly configured
- Local PostgreSQL server running

#### What it does

1. Resets the local database using `mix ecto.reset`
2. Downloads the production database from Supabase using the `SUPABASE_DATABASE_URL` from `.env`
3. Imports the downloaded database into the local environment

#### Usage

```bash
mix sync_db
```

#### Benefits

- Ensures a clean local database matching production
- Prevents conflicts with migrations or outdated local data
- Minimizes API calls (e.g., Google Places) by reusing production data

#### Notes

- This task will completely replace your local database with the production data
- Any local-only data will be lost
- File storage differences between Tigris (production) and local storage (development) are maintained 