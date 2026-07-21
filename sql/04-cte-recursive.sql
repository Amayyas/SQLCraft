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

-- ---------------------------------------------------------------------------
-- Q2. All products in a category AND all of its sub-categories, walking DOWN.
-- "Show me everything sold under the Electronics branch, however deeply nested."
-- This is the mirror image of Q1: a storefront category page must include the
-- products of every descendant category, not just the ones directly attached.
--
-- The join direction is what flips:
--   * Q1 climbed with categories.id = ancestors.parent_category_id (child -> parent).
--   * Q2 descends with child.parent_category_id = subtree.id       (parent -> child).
-- The anchor is the starting category; the recursive term collects its children,
-- then their children, and so on until no descendant is left.
--
-- Change the category below to explore another branch.
WITH RECURSIVE subtree AS (
    -- anchor: the starting category itself
    SELECT
        c.id,
        c.name,
        c.parent_category_id,
        0 AS depth
    FROM categories c
    WHERE c.name = 'Electronics'         -- <-- the category branch to expand

    UNION ALL

    -- recursive: step one level down, from parent to child
    SELECT
        child.id,
        child.name,
        child.parent_category_id,
        s.depth + 1
    FROM subtree s
    JOIN categories child ON child.parent_category_id = s.id
)
SELECT
    s.depth,
    s.name  AS category_name,
    p.id    AS product_id,
    p.name  AS product_name,
    p.price
FROM subtree s
JOIN products p ON p.category_id = s.id
ORDER BY s.depth, s.name, p.name;

-- ---------------------------------------------------------------------------
-- Q2b. Same subtree, summarised: how many products sit in each (sub-)category.
-- LEFT JOIN keeps intermediate categories that hold no product directly (in this
-- schema products are attached to leaves, so parent nodes legitimately show 0).
WITH RECURSIVE subtree AS (
    SELECT c.id, c.name, c.parent_category_id, 0 AS depth
    FROM categories c
    WHERE c.name = 'Electronics'         -- <-- the category branch to expand

    UNION ALL

    SELECT child.id, child.name, child.parent_category_id, s.depth + 1
    FROM subtree s
    JOIN categories child ON child.parent_category_id = s.id
)
SELECT
    s.depth,
    s.name          AS category_name,
    COUNT(p.id)     AS products_count
FROM subtree s
LEFT JOIN products p ON p.category_id = s.id
GROUP BY s.depth, s.name
ORDER BY s.depth, s.name;
