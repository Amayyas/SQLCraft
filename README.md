# sqlcraft

> A collection of PostgreSQL queries (100% SQL, no application code) showing a progression from basic to advanced SQL on a single realistic e-commerce schema.

**This README is a placeholder.** It will be completed in issue #16.

## Quick start (preview)

```sh
docker compose up -d
# then run the sql/ scripts in order (see issue #16 for the documented flow)
```

## Contents

| File | Purpose |
|------|---------|
| `sql/00-schema.sql` | Schema DDL (5 tables) |
| `sql/01-seed.sql` | Generated seed data |
| `sql/02-basics.sql` | Joins, aggregations, GROUP BY / HAVING |
| `sql/03-window-functions.sql` | Window functions |
| `sql/04-cte-recursive.sql` | Recursive CTEs |
| `sql/05-optimisation.sql` | Indexes & EXPLAIN ANALYZE |
| `docs/schema-diagram.md` | Schema diagram (Mermaid) |

## License

[MIT](LICENSE)
