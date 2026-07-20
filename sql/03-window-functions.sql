-- 03-window-functions.sql
-- Window functions: ranking, running totals, period-over-period change, top-N per group.
-- Run after 00-schema.sql and 01-seed.sql. Each query is preceded by a comment
-- describing the business question it answers.
--
-- Revenue convention (as in 02-basics.sql): line revenue is quantity * unit_price
-- and cancelled orders are excluded.

-- ---------------------------------------------------------------------------
-- Q1. Customer leaderboard by revenue, with RANK() and DENSE_RANK().
-- "Rank customers from best to worst by lifetime revenue."
--
-- RANK() vs DENSE_RANK() — both assign the same value to ties, but they differ
-- on what comes next:
--   * RANK()       leaves gaps: after two customers tied at rank 1, the next is
--                  rank 3 (positions 1, 1, 3, 4, ...).
--   * DENSE_RANK() leaves no gaps: the next rank is 2 (positions 1, 1, 2, 3, ...).
-- With cent-precision revenue, exact ties are rare here; the two columns are
-- shown side by side so the difference is visible whenever a tie does occur.
WITH customer_revenue AS (
    SELECT
        c.id,
        c.name,
        c.country,
        SUM(oi.quantity * oi.unit_price) AS revenue
    FROM customers c
    JOIN orders o       ON o.customer_id = c.id
    JOIN order_items oi ON oi.order_id = o.id
    WHERE o.status <> 'cancelled'
    GROUP BY c.id, c.name, c.country
)
SELECT
    id,
    name,
    country,
    revenue,
    RANK()       OVER (ORDER BY revenue DESC) AS revenue_rank,
    DENSE_RANK() OVER (ORDER BY revenue DESC) AS revenue_dense_rank
FROM customer_revenue
ORDER BY revenue DESC;

-- ---------------------------------------------------------------------------
-- Q2. Running total of revenue, month by month.
-- "What is the cumulative revenue over time?" First aggregate revenue per month
-- in a CTE, then apply a windowed SUM() ordered by month to accumulate it.
--
-- The frame ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW makes each row sum
-- every month up to and including itself — i.e. a running (cumulative) total.
-- It is the default frame for SUM() OVER (ORDER BY ...), but it is spelled out
-- here to make the intent explicit.
WITH monthly_revenue AS (
    SELECT
        date_trunc('month', o.order_date) AS month,
        SUM(oi.quantity * oi.unit_price)  AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.id
    WHERE o.status <> 'cancelled'
    GROUP BY date_trunc('month', o.order_date)
)
SELECT
    month,
    revenue,
    SUM(revenue) OVER (
        ORDER BY month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_total
FROM monthly_revenue
ORDER BY month;

-- ---------------------------------------------------------------------------
-- Q3. Month-over-month revenue evolution, with LAG() and LEAD().
-- "How does each month compare to the previous one?" LAG() reads the previous
-- month's revenue on the same row so we can compute the absolute delta and the
-- growth percentage; LEAD() peeks at the next month for context.
--
-- Edge cases:
--   * The first month has no previous row: LAG() is NULL, so the delta and the
--     growth % are NULL (nothing to compare against).
--   * NULLIF(prev, 0) guards against a division by zero if a month's revenue
--     were ever 0.
WITH monthly_revenue AS (
    SELECT
        date_trunc('month', o.order_date) AS month,
        SUM(oi.quantity * oi.unit_price)  AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.id
    WHERE o.status <> 'cancelled'
    GROUP BY date_trunc('month', o.order_date)
)
SELECT
    month,
    revenue,
    LAG(revenue)  OVER (ORDER BY month) AS prev_month_revenue,
    LEAD(revenue) OVER (ORDER BY month) AS next_month_revenue,
    revenue - LAG(revenue) OVER (ORDER BY month) AS mom_delta,
    ROUND(
        (revenue - LAG(revenue) OVER (ORDER BY month))
        / NULLIF(LAG(revenue) OVER (ORDER BY month), 0) * 100,
        2
    ) AS mom_growth_pct
FROM monthly_revenue
ORDER BY month;
