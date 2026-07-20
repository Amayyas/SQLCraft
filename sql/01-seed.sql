-- 01-seed.sql
-- Realistic seed data, generated with generate_series + Postgres random functions
-- (no long hand-written INSERT lists). Run after 00-schema.sql.
--
-- Target volumes:
--   categories  ~23   (3-level hierarchy with a known backbone)
--   customers    500
--   products     300  (attached to leaf categories)
--   orders      4000  (spread over ~2 years, random status)
--   order_items ~26k  (1-12 items per order, unit_price captured from product)
--
-- Idempotency: truncate first so the seed can be re-run on an existing schema.
-- RESTART IDENTITY resets the identity sequences; CASCADE clears dependents.
TRUNCATE order_items, orders, products, categories, customers RESTART IDENTITY CASCADE;

-- ---------------------------------------------------------------------------
-- categories: a small deterministic backbone so examples are reproducible
-- (e.g. the chain "Electronics > Computers > Laptops" used by the recursive CTEs).
-- Level 1 (roots)
INSERT INTO categories (name, parent_category_id) VALUES
    ('Electronics', NULL),
    ('Home',        NULL),
    ('Fashion',     NULL),
    ('Sports',      NULL);

-- Level 2 (linked to their root by name)
INSERT INTO categories (name, parent_category_id)
SELECT v.name, c.id
FROM (VALUES
    ('Computers',  'Electronics'),
    ('Phones',     'Electronics'),
    ('Audio',      'Electronics'),
    ('Furniture',  'Home'),
    ('Kitchen',    'Home'),
    ('Menswear',   'Fashion'),
    ('Womenswear', 'Fashion'),
    ('Fitness',    'Sports'),
    ('Outdoor',    'Sports')
) AS v(name, parent)
JOIN categories c ON c.name = v.parent AND c.parent_category_id IS NULL;

-- Level 3 (leaves, linked to their level-2 parent by name)
INSERT INTO categories (name, parent_category_id)
SELECT v.name, c.id
FROM (VALUES
    ('Laptops',     'Computers'),
    ('Desktops',    'Computers'),
    ('Tablets',     'Computers'),
    ('Smartphones', 'Phones'),
    ('Headphones',  'Audio'),
    ('Speakers',    'Audio'),
    ('Sofas',       'Furniture'),
    ('Cookware',    'Kitchen'),
    ('Running',     'Fitness'),
    ('Camping',     'Outdoor')
) AS v(name, parent)
JOIN categories c ON c.name = v.parent;

-- ---------------------------------------------------------------------------
-- customers: 500 rows spread across a fixed list of countries, created over
-- the last ~2 years.
INSERT INTO customers (name, email, country, created_at)
SELECT
    'Customer ' || g,
    'customer' || g || '@example.com',
    (ARRAY['France','Germany','Spain','Italy','USA',
           'UK','Canada','Netherlands','Belgium','Portugal'])[1 + floor(random() * 10)::int],
    now() - (random() * interval '730 days')
FROM generate_series(1, 500) AS g;

-- ---------------------------------------------------------------------------
-- products: 300 rows, each attached to a randomly chosen LEAF category
-- (a category with no children), with a realistic price between 10 and 500.
WITH leaves AS (
    SELECT array_agg(c.id) AS ids
    FROM categories c
    WHERE NOT EXISTS (SELECT 1 FROM categories ch WHERE ch.parent_category_id = c.id)
)
INSERT INTO products (name, category_id, price)
SELECT
    'Product ' || g,
    (SELECT ids[1 + floor(random() * array_length(ids, 1))::int] FROM leaves),
    round((random() * 490 + 10)::numeric, 2)
FROM generate_series(1, 300) AS g;

-- ---------------------------------------------------------------------------
-- orders: 4000 rows, random customer, order_date over the last ~2 years,
-- random lifecycle status.
WITH cust AS (SELECT array_agg(id) AS ids FROM customers)
INSERT INTO orders (customer_id, order_date, status)
SELECT
    (SELECT ids[1 + floor(random() * array_length(ids, 1))::int] FROM cust),
    now() - (random() * interval '730 days'),
    (ARRAY['pending','paid','shipped','delivered','cancelled'])[1 + floor(random() * 5)::int]
FROM generate_series(1, 4000) AS g;

-- ---------------------------------------------------------------------------
-- order_items: for each order, 1-12 distinct random products. unit_price is
-- captured from the product's current price. This is the large table (~26k rows)
-- that makes the EXPLAIN ANALYZE before/after in 05-optimisation.sql meaningful.
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT
    o.id,
    p.id,
    1 + floor(random() * 5)::int,
    p.price
FROM orders o
CROSS JOIN LATERAL (
    SELECT id, price
    FROM products
    -- Correlate on o.id so this subquery is re-executed per order: without a
    -- reference to the outer row the planner evaluates the random ORDER BY and
    -- LIMIT only once and every order ends up with the same items.
    WHERE o.id IS NOT NULL
    ORDER BY random()
    LIMIT (1 + floor(random() * 12)::int)
) AS p;

-- Refresh planner statistics so 05-optimisation.sql sees representative plans.
ANALYZE;
