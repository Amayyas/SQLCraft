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

-- Captured output (Postgres 16, ~26k order_items):
--
--  Sort  (cost=554.59..554.72 rows=52 width=56) (actual time=2.873..2.878 rows=4 loops=1)
--    Sort Key: o.order_date
--    Buffers: shared hit=183
--    ->  GroupAggregate  (cost=551.68..553.11 rows=52 width=56) (actual time=2.848..2.858 rows=4 loops=1)
--          Group Key: c.name, o.id
--          ->  Sort  (cost=551.68..551.81 rows=52 width=34) (actual time=2.831..2.836 rows=27 loops=1)
--                Sort Key: c.name, o.id
--                ->  Hash Join  (cost=30.41..550.20 rows=52 width=34) (actual time=0.165..2.811 rows=27 loops=1)
--                      Hash Cond: (oi.order_id = o.id)
--                      Buffers: shared hit=174
--                      ->  Seq Scan on order_items oi  (cost=0.00..422.65 rows=25765 width=14) (actual time=0.009..1.398 rows=25765 loops=1)
--                            Buffers: shared hit=165
--                      ->  Hash  (cost=30.31..30.31 rows=8 width=24) (actual time=0.050..0.053 rows=4 loops=1)
--                            ->  Nested Loop  (cost=4.61..30.31 rows=8 width=24) (actual time=0.030..0.047 rows=4 loops=1)
--                                  ->  Index Scan using customers_email_key on customers c  (actual time=0.018..0.018 rows=1 loops=1)
--                                        Index Cond: (email = 'customer42@example.com'::text)
--                                  ->  Bitmap Heap Scan on orders o  (actual time=0.010..0.026 rows=4 loops=1)
--                                        Recheck Cond: (c.id = customer_id)
--                                        ->  Bitmap Index Scan on idx_orders_customer_id  (actual time=0.006..0.007 rows=4 loops=1)
--                                              Index Cond: (customer_id = c.id)
--  Planning Time: 0.616 ms
--  Execution Time: 2.971 ms
--
-- Reading the plan:
--   * Seq Scan on order_items -> the whole table is read: 25765 rows scanned,
--     165 shared buffers hit, just to keep the 27 rows that match.
--   * Because no index can drive the join, the planner falls back to a Hash Join:
--     it builds a hash of the 4 relevant orders, then streams all 25765 line
--     items through it.
--   * The customers and orders sides are already fast (Index Scan on the unique
--     email index, Bitmap Index Scan on idx_orders_customer_id) -- those FKs are
--     indexed in 00-schema.sql. order_items(order_id) is the one that is not.
--   * Execution Time: 2.971 ms, dominated by that sequential scan.
--
-- The fix (creating the index and re-measuring) is the subject of the next
-- section, added in issue #14.
