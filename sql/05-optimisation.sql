-- 05-optimisation.sql
-- Index tuning demonstrated with EXPLAIN ANALYZE: the same query before and
-- after creating a missing foreign-key index.
-- Run after 00-schema.sql and 01-seed.sql.
--
-- Background: 00-schema.sql indexes every foreign key EXCEPT order_items(order_id).
-- That omission is deliberate and exists for this file. order_items is by far the
-- largest table (~26k rows), so any join order_items -> orders has no index to
-- drive it and Postgres must read the whole table.
--
-- Statistics matter for a representative plan: 01-seed.sql ends with ANALYZE.
--
-- Run this file on a FRESH database (00-schema.sql then 01-seed.sql), where the
-- index does not exist yet. Running it a second time is harmless (the CREATE
-- INDEX is IF NOT EXISTS), but the "before" section would then already benefit
-- from the index and print the fast plan. The plans captured in the comments
-- below are the reference.

-- ---------------------------------------------------------------------------
-- The reference query.
-- "List every order of one given customer with its total value."
-- It is highly selective: a single customer, a handful of orders, a few dozen
-- line items. Ideally the database should touch only those few rows -- but
-- without an index on order_items(order_id) it cannot look them up directly.
SELECT
    c.name,
    o.id         AS order_id,
    o.order_date,
    SUM(oi.quantity * oi.unit_price) AS order_value
FROM customers c
JOIN orders o       ON o.customer_id = c.id
JOIN order_items oi ON oi.order_id = o.id
WHERE c.email = 'customer42@example.com'
GROUP BY c.name, o.id, o.order_date
ORDER BY o.order_date;

-- ---------------------------------------------------------------------------
-- BEFORE: plan without the index on order_items(order_id).
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    c.name,
    o.id         AS order_id,
    o.order_date,
    SUM(oi.quantity * oi.unit_price) AS order_value
FROM customers c
JOIN orders o       ON o.customer_id = c.id
JOIN order_items oi ON oi.order_id = o.id
WHERE c.email = 'customer42@example.com'
GROUP BY c.name, o.id, o.order_date
ORDER BY o.order_date;

-- Captured output (Postgres 16; 26261 order_items, customer with 5 orders /
-- 25 line items). This run and the "after" run below share the exact same
-- database state, so the two plans are directly comparable.
--
--  Sort  (cost=564.52..564.66 rows=53 width=56) (actual time=4.305..4.308 rows=5 loops=1)
--    Sort Key: o.order_date
--    Buffers: shared hit=187
--    ->  GroupAggregate  (cost=561.55..563.01 rows=53 width=56) (actual time=4.279..4.288 rows=5 loops=1)
--          Group Key: c.name, o.id
--          ->  Sort  (cost=561.55..561.68 rows=53 width=34) (actual time=4.261..4.265 rows=25 loops=1)
--                Sort Key: c.name, o.id
--                ->  Hash Join  (cost=30.41..560.03 rows=53 width=34) (actual time=0.527..4.226 rows=25 loops=1)
--                      Hash Cond: (oi.order_id = o.id)
--                      Buffers: shared hit=178
--                      ->  Seq Scan on order_items oi  (cost=0.00..430.61 rows=26261 width=14) (actual time=0.004..1.985 rows=26261 loops=1)
--                            Buffers: shared hit=168
--                      ->  Hash  (cost=30.31..30.31 rows=8 width=24) (actual time=0.062..0.063 rows=5 loops=1)
--                            ->  Nested Loop  (cost=4.61..30.31 rows=8 width=24) (actual time=0.044..0.059 rows=5 loops=1)
--                                  ->  Index Scan using customers_email_key on customers c  (actual time=0.024..0.024 rows=1 loops=1)
--                                        Index Cond: (email = 'customer42@example.com'::text)
--                                  ->  Bitmap Heap Scan on orders o  (actual time=0.017..0.031 rows=5 loops=1)
--                                        Recheck Cond: (c.id = customer_id)
--                                        ->  Bitmap Index Scan on idx_orders_customer_id  (actual time=0.011..0.011 rows=5 loops=1)
--                                              Index Cond: (customer_id = c.id)
--  Planning Time: 0.803 ms
--  Execution Time: 4.387 ms
--
-- Reading the plan:
--   * Seq Scan on order_items -> the whole table is read: 26261 rows scanned,
--     168 shared buffers hit, just to keep the 25 rows that match.
--   * Because no index can drive the join, the planner falls back to a Hash Join:
--     it builds a hash of the 5 relevant orders, then streams all 26261 line
--     items through it.
--   * The customers and orders sides are already fast (Index Scan on the unique
--     email index, Bitmap Index Scan on idx_orders_customer_id) -- those FKs are
--     indexed in 00-schema.sql. order_items(order_id) is the one that is not.
--   * Execution Time: 4.387 ms, dominated by that sequential scan.

-- ---------------------------------------------------------------------------
-- THE FIX: create the missing foreign-key index.
-- This is the index deliberately left out of 00-schema.sql. Creating it gives
-- the planner a way to fetch the line items of a known order directly.
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items (order_id);

-- Refresh statistics so the planner immediately accounts for the new index.
ANALYZE order_items;

-- ---------------------------------------------------------------------------
-- AFTER: exact same query, now with the index in place.
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    c.name,
    o.id         AS order_id,
    o.order_date,
    SUM(oi.quantity * oi.unit_price) AS order_value
FROM customers c
JOIN orders o       ON o.customer_id = c.id
JOIN order_items oi ON oi.order_id = o.id
WHERE c.email = 'customer42@example.com'
GROUP BY c.name, o.id, o.order_date
ORDER BY o.order_date;

-- Captured output (same database state as the "before" run above):
--
--  Sort  (cost=38.63..38.76 rows=53 width=56) (actual time=0.146..0.147 rows=5 loops=1)
--    Sort Key: o.order_date
--    Buffers: shared hit=23 read=5
--    ->  HashAggregate  (cost=36.45..37.11 rows=53 width=56) (actual time=0.115..0.117 rows=5 loops=1)
--          Group Key: c.name, o.id
--          ->  Nested Loop  (cost=4.90..35.78 rows=53 width=34) (actual time=0.042..0.096 rows=25 loops=1)
--                Buffers: shared hit=20 read=5
--                ->  Nested Loop  (cost=4.61..30.31 rows=8 width=24) (actual time=0.028..0.044 rows=5 loops=1)
--                      ->  Index Scan using customers_email_key on customers c  (actual time=0.016..0.016 rows=1 loops=1)
--                            Index Cond: (email = 'customer42@example.com'::text)
--                      ->  Bitmap Heap Scan on orders o  (actual time=0.010..0.025 rows=5 loops=1)
--                            Recheck Cond: (c.id = customer_id)
--                            ->  Bitmap Index Scan on idx_orders_customer_id  (actual time=0.007..0.007 rows=5 loops=1)
--                                  Index Cond: (customer_id = c.id)
--                ->  Index Scan using idx_order_items_order_id on order_items oi  (cost=0.29..0.61 rows=7 width=14) (actual time=0.009..0.010 rows=5 loops=5)
--                      Index Cond: (order_id = o.id)
--                      Buffers: shared hit=10 read=5
--  Planning Time: 0.689 ms
--  Execution Time: 0.227 ms
--
-- What changed:
--   * Seq Scan on order_items  ->  Index Scan using idx_order_items_order_id.
--     Instead of reading 26261 rows, the query now looks up only the line items
--     of the 5 orders it actually needs (rows=5, loops=5).
--   * Hash Join -> Nested Loop. With an index available, the planner switches
--     strategy entirely: for each order it probes the index, rather than
--     building a hash table and streaming the whole table through it.
--   * GroupAggregate (which required a Sort) -> HashAggregate: with only 25 rows
--     coming out of the join, the intermediate Sort disappears too.
--
-- Measured gain on this dataset:
--   Execution Time  4.387 ms -> 0.227 ms   (~19x faster)
--   Buffers          187     -> 28         (~85% fewer blocks touched)
--
-- The relative gain grows with the size of order_items: the Seq Scan cost is
-- proportional to the whole table, while the Index Scan cost depends only on how
-- many rows the query actually returns.
--
-- Note: this index is created here rather than in 00-schema.sql purely for the
-- demonstration. In a real schema, indexing a foreign key like this one from the
-- start is the sane default.
