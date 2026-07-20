-- 02-basics.sql
-- Basic SQL: joins, aggregations, GROUP BY / HAVING, simple subqueries.
-- Run after 00-schema.sql and 01-seed.sql. Each query is preceded by a comment
-- describing the business question it answers.
--
-- Revenue convention used throughout this file: an order line's revenue is
-- quantity * unit_price, and cancelled orders are excluded from revenue.

-- ---------------------------------------------------------------------------
-- Q1. Total revenue per customer.
-- "How much has each customer spent?" Rank customers by lifetime revenue to
-- spot the most valuable ones.
SELECT
    c.id,
    c.name,
    c.country,
    SUM(oi.quantity * oi.unit_price) AS total_revenue
FROM customers c
JOIN orders o       ON o.customer_id = c.id
JOIN order_items oi ON oi.order_id = o.id
WHERE o.status <> 'cancelled'
GROUP BY c.id, c.name, c.country
ORDER BY total_revenue DESC;

-- ---------------------------------------------------------------------------
-- Q2. Top 10 best-selling products (by units sold).
-- "Which products move the most volume?" Total revenue is shown alongside for
-- context. Cancelled orders are excluded.
SELECT
    p.id,
    p.name,
    SUM(oi.quantity)                  AS units_sold,
    SUM(oi.quantity * oi.unit_price)  AS revenue
FROM products p
JOIN order_items oi ON oi.product_id = p.id
JOIN orders o       ON o.id = oi.order_id
WHERE o.status <> 'cancelled'
GROUP BY p.id, p.name
ORDER BY units_sold DESC
LIMIT 10;

-- ---------------------------------------------------------------------------
-- Q3. Orders and revenue per country, for the busier markets only.
-- "Which countries drive the business?" Grouped by the customer's country;
-- HAVING keeps only countries with more than 300 orders (a filter applied
-- after aggregation, unlike WHERE).
SELECT
    c.country,
    COUNT(DISTINCT o.id)              AS orders_count,
    SUM(oi.quantity * oi.unit_price)  AS revenue
FROM customers c
JOIN orders o       ON o.customer_id = c.id
JOIN order_items oi ON oi.order_id = o.id
WHERE o.status <> 'cancelled'
GROUP BY c.country
HAVING COUNT(DISTINCT o.id) > 300
ORDER BY revenue DESC;

-- ---------------------------------------------------------------------------
-- Q4. Average basket (order value) per month.
-- "How does the typical order value evolve month by month?" Order value is the
-- sum of its line items; we first compute the total per order in a CTE, then
-- average those totals grouped by month. date_trunc('month', ...) buckets the
-- orders by calendar month.
WITH order_totals AS (
    SELECT
        o.id,
        date_trunc('month', o.order_date) AS month,
        SUM(oi.quantity * oi.unit_price)  AS order_value
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.id
    WHERE o.status <> 'cancelled'
    GROUP BY o.id, date_trunc('month', o.order_date)
)
SELECT
    month,
    COUNT(*)                 AS orders_count,
    ROUND(AVG(order_value), 2) AS avg_basket
FROM order_totals
GROUP BY month
ORDER BY month;
