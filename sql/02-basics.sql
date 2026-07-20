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
