# SQLCraft

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**A collection of PostgreSQL queries — 100% SQL, no application code — going from basic joins to window functions, recursive CTEs and index tuning with `EXPLAIN ANALYZE`.**

Every query runs against a single realistic e-commerce schema (customers, categories, products, orders, order items). The whole thing boots in one command with Docker Compose — no local PostgreSQL install required.

---

## Quick start

**Requirements:** Docker (with Compose). Nothing else — not even a `psql` client.

```sh
# 1. Start PostgreSQL 16 (waits until healthy)
docker compose up -d

# 2. Create the schema, then load the seed data
docker compose exec db psql -U sqlcraft -d sqlcraft -f /sql/00-schema.sql
docker compose exec db psql -U sqlcraft -d sqlcraft -f /sql/01-seed.sql

# 3. Run the query files, in order
docker compose exec db psql -U sqlcraft -d sqlcraft -f /sql/02-basics.sql
docker compose exec db psql -U sqlcraft -d sqlcraft -f /sql/03-window-functions.sql
docker compose exec db psql -U sqlcraft -d sqlcraft -f /sql/04-cte-recursive.sql
docker compose exec db psql -U sqlcraft -d sqlcraft -f /sql/05-optimisation.sql
```

The `sql/` folder is mounted read-only at `/sql` inside the container, so the scripts are run
explicitly rather than auto-executed at startup — that keeps the ordered, sectioned flow visible
and lets you re-run any single file on demand.

To poke around interactively:

```sh
docker compose exec db psql -U sqlcraft -d sqlcraft
```

<details>
<summary>Using an older <code>docker-compose</code> (v1), or a psql client on the host</summary>

With Compose v1, replace `docker compose` with `docker-compose` in every command above.

If you do have `psql` installed locally, you can connect from the host instead (the port is
published on `5432`):

```sh
psql -h localhost -p 5432 -U sqlcraft -d sqlcraft -f sql/00-schema.sql
```

</details>

**Defaults** (override via environment variables, see [`docker-compose.yml`](docker-compose.yml)):

| Variable | Default |
|----------|---------|
| `POSTGRES_USER` | `sqlcraft` |
| `POSTGRES_PASSWORD` | `sqlcraft` |
| `POSTGRES_DB` | `sqlcraft` |
| `POSTGRES_PORT` | `5432` |

Tear everything down (including the data volume) with `docker compose down -v`.

---

## The schema

Five tables: `customers`, `categories`, `products`, `orders`, `order_items`. Categories are a
**nested tree** (`parent_category_id` self-reference), which is what makes the recursive CTEs
meaningful.

See **[docs/schema-diagram.md](docs/schema-diagram.md)** for the ER diagram and a description of
every table and relationship.

---

## What's in `sql/`

Files are numbered in execution order. Every query is preceded by a comment explaining the
business question it answers. **SQL comments are written in English** throughout.

### `00-schema.sql` — the DDL
The 5 tables with all their constraints: primary keys, foreign keys, `NOT NULL`, a unique email,
and `CHECK`s on prices, quantities and the order status. Every foreign key is indexed — **except
`order_items(order_id)`**, deliberately left out to power the optimisation demo in `05`.

### `01-seed.sql` — the data
Realistic data generated with `generate_series` and Postgres random functions (no hand-written
INSERT lists): ~23 categories on 3 levels, 500 customers, 300 products, 4,000 orders spread over
two years, and **~26,000 order items** — enough volume for `EXPLAIN ANALYZE` to tell a real story.

### `02-basics.sql` — joins & aggregation
| Query | What it answers |
|-------|-----------------|
| Q1 | Total revenue per customer — who are the most valuable customers? |
| Q2 | Top 10 best-selling products by units sold |
| Q3 | Orders and revenue per country, filtered with `HAVING` (post-aggregation filtering) |
| Q4 | Average basket per month — per-order totals in a CTE, then averaged by `date_trunc('month', ...)` |

### `03-window-functions.sql` — window functions
| Query | What it answers |
|-------|-----------------|
| Q1 | Customer leaderboard with `RANK()` **and** `DENSE_RANK()` side by side, with the gap-vs-no-gap difference explained |
| Q2 | Running total of monthly revenue — `SUM() OVER (ORDER BY month ...)` with an explicit frame |
| Q3 | Month-over-month growth with `LAG()` / `LEAD()` — absolute delta and growth %, first month handled as `NULL` |
| Q4 | Best-selling product **per category** — the canonical top-N-per-group pattern with `ROW_NUMBER() PARTITION BY` |

### `04-cte-recursive.sql` — recursive CTEs
| Query | What it answers |
|-------|-----------------|
| Q1 | A product's full category **breadcrumb**, walking *up* the tree to the root (child → parent) |
| Q1b | The same walk collapsed into one string: `Home > Kitchen > Cookware` |
| Q2 | Every product under a category branch, walking *down* the tree (parent → child), at any depth |
| Q2b | The same subtree, summarised as a product count per sub-category |

### `05-optimisation.sql` — indexes & `EXPLAIN ANALYZE`
A deliberately selective query (one customer's orders and their line totals) that has to join the
large `order_items` table. The file captures the **real** query plan before and after creating the
missing foreign-key index:

| Metric | Before | After |
|--------|--------|-------|
| Scan on `order_items` | `Seq Scan` — **26,261 rows** | `Index Scan` — 5 rows × 5 loops |
| Join strategy | Hash Join | Nested Loop |
| Buffers | 187 | 28 |
| Execution time | **4.387 ms** | **0.227 ms** (~19× faster) |

Both plans are captured from the same database state, and pasted into the file as annotated
comments explaining *why* each node changed.

---

## Why this project

Most SQL portfolio samples stop at `SELECT ... JOIN ... GROUP BY`. This one is built to show the
next layer:

- **Window functions** — ranking, running totals, period-over-period change, top-N per group.
- **Recursive CTEs** — traversing a real hierarchy in both directions.
- **Query optimisation** — reading an execution plan, spotting a missing index, and *measuring* the
  improvement rather than assuming it.

It is also deliberately **pure SQL**: no ORM, no wrapper script, no application layer. The
repository is what it claims to be, and GitHub Linguist detects it as a SQL project without any
sleight of hand.

---

## License

[MIT](LICENSE)
