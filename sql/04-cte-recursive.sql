-- 04-cte-recursive.sql
-- Recursive CTEs over the nested `categories` hierarchy
-- (categories.parent_category_id references categories.id).
-- Run after 00-schema.sql and 01-seed.sql.
--
-- The seed builds a 3-level backbone, e.g. Electronics > Computers > Laptops,
-- so the walks below have real depth to traverse.

-- ---------------------------------------------------------------------------
-- Q1. Full category path of a given product ("breadcrumb"), walking UP the tree.
-- "Which category does this product belong to, and what are all its parent
-- categories up to the root?" Useful to render a breadcrumb such as
-- Electronics > Computers > Laptops.
--
-- How the recursion works:
--   * Anchor term: the product's own category (depth 0).
--   * Recursive term: join categories to the rows already produced, matching
--     categories.id = ancestors.parent_category_id — i.e. we climb from CHILD
--     to PARENT. It stops on its own when a root is reached, because a root has
--     parent_category_id IS NULL and the join finds nothing.
--
-- Change the product below to explore another branch.
WITH RECURSIVE ancestors AS (
    -- anchor: the category the product sits in
    SELECT
        c.id,
        c.name,
        c.parent_category_id,
        0 AS depth
    FROM products p
    JOIN categories c ON c.id = p.category_id
    WHERE p.name = 'Product 42'          -- <-- the product to inspect

    UNION ALL

    -- recursive: climb one level up, from child to parent
    SELECT
        parent.id,
        parent.name,
        parent.parent_category_id,
        a.depth + 1
    FROM ancestors a
    JOIN categories parent ON parent.id = a.parent_category_id
)
SELECT
    depth,          -- 0 = the product's own category, increasing towards the root
    id AS category_id,
    name AS category_name
FROM ancestors
ORDER BY depth;

-- ---------------------------------------------------------------------------
-- Q1b. Same walk, collapsed into a single breadcrumb string.
-- Ordering by depth DESC puts the root first, giving the natural reading order
-- "Electronics > Computers > Laptops".
WITH RECURSIVE ancestors AS (
    SELECT c.id, c.name, c.parent_category_id, 0 AS depth
    FROM products p
    JOIN categories c ON c.id = p.category_id
    WHERE p.name = 'Product 42'          -- <-- the product to inspect

    UNION ALL

    SELECT parent.id, parent.name, parent.parent_category_id, a.depth + 1
    FROM ancestors a
    JOIN categories parent ON parent.id = a.parent_category_id
)
SELECT string_agg(name, ' > ' ORDER BY depth DESC) AS category_path
FROM ancestors;
