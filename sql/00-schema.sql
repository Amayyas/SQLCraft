-- 00-schema.sql
-- Complete DDL for the SQLCraft e-commerce schema (5 tables).
-- Run first, before 01-seed.sql. Comments are in English (project convention).
--
-- Tables are dropped in reverse dependency order so the script is re-runnable.
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
DROP TABLE IF EXISTS customers CASCADE;

-- customers: people who place orders.
CREATE TABLE customers (
    id          integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        text        NOT NULL,
    email       text        NOT NULL UNIQUE,
    country     text        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- categories: nested product taxonomy. `parent_category_id` self-references
-- categories to build an arbitrarily deep hierarchy; it is NULL for root
-- categories. This hierarchy is exercised by the recursive CTEs (04-cte-recursive.sql).
CREATE TABLE categories (
    id                 integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name               text    NOT NULL,
    parent_category_id integer REFERENCES categories (id)
);

-- products: items for sale, each attached to a category.
CREATE TABLE products (
    id          integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        text          NOT NULL,
    category_id integer       NOT NULL REFERENCES categories (id),
    price       numeric(10,2) NOT NULL CHECK (price >= 0),
    created_at  timestamptz   NOT NULL DEFAULT now()
);

-- orders: a purchase placed by a customer. `status` is constrained to a small
-- known set of lifecycle values.
CREATE TABLE orders (
    id          integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id integer     NOT NULL REFERENCES customers (id),
    order_date  timestamptz NOT NULL DEFAULT now(),
    status      text        NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'paid', 'shipped', 'delivered', 'cancelled'))
);

-- order_items: line items of an order. `unit_price` is captured at order time
-- (it may differ from the product's current price). quantity must be positive.
CREATE TABLE order_items (
    id         integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id   integer       NOT NULL REFERENCES orders (id),
    product_id integer       NOT NULL REFERENCES products (id),
    quantity   integer       NOT NULL CHECK (quantity > 0),
    unit_price numeric(10,2) NOT NULL CHECK (unit_price >= 0)
);

-- Indexes on foreign keys.
-- Postgres does NOT create these automatically; they speed up joins and the
-- referential-integrity checks on cascading operations.
CREATE INDEX idx_categories_parent_category_id ON categories (parent_category_id);
CREATE INDEX idx_products_category_id          ON products (category_id);
CREATE INDEX idx_orders_customer_id            ON orders (customer_id);
CREATE INDEX idx_order_items_product_id        ON order_items (product_id);

-- NOTE: the FK index on order_items(order_id) is INTENTIONALLY omitted here.
-- order_items is the largest table, so a join order_items -> orders without
-- this index forces a sequential scan. 05-optimisation.sql uses that to show a
-- real EXPLAIN ANALYZE before/after (Seq Scan -> Index Scan) and creates the
-- index there. Do not add CREATE INDEX ... ON order_items (order_id) in this file.
