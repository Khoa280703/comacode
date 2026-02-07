-- SQL sample file - Advanced PostgreSQL patterns

-- ===== Database Setup =====

-- Create custom types
CREATE TYPE user_role AS ENUM ('admin', 'user', 'guest');
CREATE TYPE order_status AS ENUM ('pending', 'processing', 'shipped', 'delivered', 'cancelled');

-- ===== Tables =====

-- Users table with constraints
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    uuid UUID DEFAULT gen_random_uuid() NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL CHECK (length(name) >= 2),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role user_role NOT NULL DEFAULT 'user',
    is_active BOOLEAN NOT NULL DEFAULT true,
    email_verified BOOLEAN NOT NULL DEFAULT false,
    metadata JSONB DEFAULT '{}',
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted_at TIMESTAMPTZ,

    -- Partial unique index for soft delete
    CONSTRAINT users_email_not_deleted EXCLUDE (email WITH =) WHERE (deleted_at IS NULL)
);

-- Products table
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    sku VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price DECIMAL(10, 2) NOT NULL CHECK (price >= 0),
    quantity_in_stock INTEGER NOT NULL DEFAULT 0 CHECK (quantity_in_stock >= 0),
    category_id INTEGER,
    tags TEXT[] DEFAULT '{}',
    attributes JSONB DEFAULT '{}',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- Orders table
CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    order_number VARCHAR(50) NOT NULL UNIQUE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    status order_status NOT NULL DEFAULT 'pending',
    subtotal DECIMAL(10, 2) NOT NULL DEFAULT 0,
    tax DECIMAL(10, 2) NOT NULL DEFAULT 0,
    shipping DECIMAL(10, 2) NOT NULL DEFAULT 0,
    total DECIMAL(10, 2) GENERATED ALWAYS AS (subtotal + tax + shipping) STORED,
    notes TEXT,
    shipping_address JSONB NOT NULL,
    billing_address JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,
    completed_at TIMESTAMPTZ
);

-- Order items (junction table)
CREATE TABLE IF NOT EXISTS order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10, 2) NOT NULL,
    total_price DECIMAL(10, 2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL,

    UNIQUE (order_id, product_id)
);

-- Audit log table
CREATE TABLE IF NOT EXISTS audit_log (
    id BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(100) NOT NULL,
    record_id INTEGER NOT NULL,
    action VARCHAR(20) NOT NULL,
    old_values JSONB,
    new_values JSONB,
    user_id INTEGER REFERENCES users(id),
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP NOT NULL
);

-- ===== Indexes =====

-- Users indexes
CREATE INDEX idx_users_email ON users(email) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_role ON users(role) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_created_at ON users(created_at DESC);
CREATE INDEX idx_users_metadata ON users USING GIN (metadata);

-- Products indexes
CREATE INDEX idx_products_category ON products(category_id) WHERE is_active = true;
CREATE INDEX idx_products_price ON products(price);
CREATE INDEX idx_products_tags ON products USING GIN (tags);
CREATE INDEX idx_products_attributes ON products USING GIN (attributes);
CREATE INDEX idx_products_search ON products USING GIN (to_tsvector('english', name || ' ' || COALESCE(description, '')));

-- Orders indexes
CREATE INDEX idx_orders_user ON orders(user_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_created_at ON orders(created_at DESC);

-- Audit log indexes
CREATE INDEX idx_audit_table_record ON audit_log(table_name, record_id);
CREATE INDEX idx_audit_created_at ON audit_log(created_at DESC);

-- ===== Functions =====

-- Update timestamp function
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Audit trigger function
CREATE OR REPLACE FUNCTION audit_trigger()
RETURNS TRIGGER AS $$
DECLARE
    old_row JSONB;
    new_row JSONB;
    user_id_val INTEGER;
BEGIN
    -- Try to get user_id from session variable
    BEGIN
        user_id_val := current_setting('app.current_user_id')::INTEGER;
    EXCEPTION WHEN OTHERS THEN
        user_id_val := NULL;
    END;

    IF TG_OP = 'DELETE' THEN
        old_row := to_jsonb(OLD);
        INSERT INTO audit_log (table_name, record_id, action, old_values, user_id)
        VALUES (TG_TABLE_NAME, OLD.id, 'DELETE', old_row, user_id_val);
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        old_row := to_jsonb(OLD);
        new_row := to_jsonb(NEW);
        INSERT INTO audit_log (table_name, record_id, action, old_values, new_values, user_id)
        VALUES (TG_TABLE_NAME, NEW.id, 'UPDATE', old_row, new_row, user_id_val);
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        new_row := to_jsonb(NEW);
        INSERT INTO audit_log (table_name, record_id, action, new_values, user_id)
        VALUES (TG_TABLE_NAME, NEW.id, 'INSERT', new_row, user_id_val);
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Calculate order subtotal function
CREATE OR REPLACE FUNCTION calculate_order_subtotal(p_order_id INTEGER)
RETURNS DECIMAL(10, 2) AS $$
    SELECT COALESCE(SUM(total_price), 0)
    FROM order_items
    WHERE order_id = p_order_id;
$$ LANGUAGE SQL STABLE;

-- Search products function
CREATE OR REPLACE FUNCTION search_products(
    search_query TEXT,
    min_price DECIMAL DEFAULT NULL,
    max_price DECIMAL DEFAULT NULL,
    category_ids INTEGER[] DEFAULT NULL,
    tag_filter TEXT[] DEFAULT NULL,
    limit_count INTEGER DEFAULT 20,
    offset_count INTEGER DEFAULT 0
)
RETURNS TABLE (
    id INTEGER,
    name VARCHAR,
    description TEXT,
    price DECIMAL,
    relevance REAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.id,
        p.name,
        p.description,
        p.price,
        ts_rank(to_tsvector('english', p.name || ' ' || COALESCE(p.description, '')),
                plainto_tsquery('english', search_query)) AS relevance
    FROM products p
    WHERE p.is_active = true
      AND (search_query IS NULL OR
           to_tsvector('english', p.name || ' ' || COALESCE(p.description, '')) @@
           plainto_tsquery('english', search_query))
      AND (min_price IS NULL OR p.price >= min_price)
      AND (max_price IS NULL OR p.price <= max_price)
      AND (category_ids IS NULL OR p.category_id = ANY(category_ids))
      AND (tag_filter IS NULL OR p.tags && tag_filter)
    ORDER BY relevance DESC, p.created_at DESC
    LIMIT limit_count
    OFFSET offset_count;
END;
$$ LANGUAGE plpgsql STABLE;

-- ===== Triggers =====

-- Updated_at triggers
CREATE TRIGGER users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER products_updated_at
    BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER orders_updated_at
    BEFORE UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Audit triggers
CREATE TRIGGER users_audit
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW EXECUTE FUNCTION audit_trigger();

CREATE TRIGGER orders_audit
    AFTER INSERT OR UPDATE OR DELETE ON orders
    FOR EACH ROW EXECUTE FUNCTION audit_trigger();

-- ===== Views =====

-- Active users view
CREATE OR REPLACE VIEW active_users AS
SELECT id, uuid, name, email, role, created_at, last_login_at
FROM users
WHERE deleted_at IS NULL AND is_active = true;

-- Order summary view
CREATE OR REPLACE VIEW order_summary AS
SELECT
    o.id,
    o.order_number,
    u.name AS customer_name,
    u.email AS customer_email,
    o.status,
    COUNT(oi.id) AS item_count,
    o.subtotal,
    o.tax,
    o.shipping,
    o.total,
    o.created_at,
    o.completed_at
FROM orders o
JOIN users u ON o.user_id = u.id
LEFT JOIN order_items oi ON o.id = oi.order_id
GROUP BY o.id, u.name, u.email;

-- Product inventory view
CREATE OR REPLACE VIEW product_inventory AS
SELECT
    p.id,
    p.sku,
    p.name,
    p.price,
    p.quantity_in_stock,
    CASE
        WHEN p.quantity_in_stock = 0 THEN 'out_of_stock'
        WHEN p.quantity_in_stock < 10 THEN 'low_stock'
        ELSE 'in_stock'
    END AS stock_status,
    COALESCE(SUM(oi.quantity), 0) AS total_sold
FROM products p
LEFT JOIN order_items oi ON p.id = oi.product_id
WHERE p.is_active = true
GROUP BY p.id;

-- ===== Sample Data =====

INSERT INTO users (name, email, password_hash, role, email_verified, metadata) VALUES
    ('Alice Admin', 'alice@example.com', '$2b$10$xxxxxxxxxxxxx', 'admin', true, '{"department": "IT"}'),
    ('Bob User', 'bob@example.com', '$2b$10$xxxxxxxxxxxxx', 'user', true, '{"preferences": {"theme": "dark"}}'),
    ('Charlie Guest', 'charlie@example.com', '$2b$10$xxxxxxxxxxxxx', 'guest', false, '{}')
ON CONFLICT (email) DO NOTHING;

INSERT INTO products (sku, name, description, price, quantity_in_stock, tags, attributes) VALUES
    ('PROD-001', 'Laptop Pro', 'High-performance laptop for professionals', 1299.99, 50, ARRAY['electronics', 'computers'], '{"brand": "TechCo", "ram": "16GB", "storage": "512GB SSD"}'),
    ('PROD-002', 'Wireless Mouse', 'Ergonomic wireless mouse', 49.99, 200, ARRAY['electronics', 'accessories'], '{"brand": "PeripheralCo", "dpi": 3200}'),
    ('PROD-003', 'USB-C Hub', '7-in-1 USB-C hub', 79.99, 100, ARRAY['electronics', 'accessories'], '{"ports": 7, "power_delivery": true}')
ON CONFLICT (sku) DO NOTHING;

-- ===== Common Queries =====

-- Get user with order count
SELECT
    u.id,
    u.name,
    u.email,
    u.role,
    COUNT(o.id) AS order_count,
    COALESCE(SUM(o.total), 0) AS total_spent
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
WHERE u.deleted_at IS NULL
GROUP BY u.id
ORDER BY total_spent DESC;

-- Get low stock products
SELECT * FROM product_inventory
WHERE stock_status IN ('out_of_stock', 'low_stock')
ORDER BY quantity_in_stock ASC;

-- Get recent orders with items
SELECT
    o.order_number,
    u.name AS customer,
    o.status,
    o.total,
    json_agg(json_build_object(
        'product', p.name,
        'quantity', oi.quantity,
        'price', oi.total_price
    )) AS items
FROM orders o
JOIN users u ON o.user_id = u.id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id
WHERE o.created_at > NOW() - INTERVAL '30 days'
GROUP BY o.id, u.name
ORDER BY o.created_at DESC;

-- Search products example
SELECT * FROM search_products(
    'laptop',
    min_price := 100,
    max_price := 2000,
    tag_filter := ARRAY['electronics']
);

-- ===== Window Functions =====

-- Row number and ranking
SELECT
    id,
    name,
    price,
    category_id,
    ROW_NUMBER() OVER (ORDER BY price DESC) AS price_rank,
    RANK() OVER (PARTITION BY category_id ORDER BY price DESC) AS category_rank,
    DENSE_RANK() OVER (ORDER BY price DESC) AS dense_rank,
    NTILE(4) OVER (ORDER BY price) AS price_quartile
FROM products
WHERE is_active = true;

-- Running totals and averages
SELECT
    o.id,
    o.created_at::DATE AS order_date,
    o.total,
    SUM(o.total) OVER (ORDER BY o.created_at) AS running_total,
    AVG(o.total) OVER (ORDER BY o.created_at ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS rolling_7_day_avg,
    COUNT(*) OVER (PARTITION BY DATE_TRUNC('month', o.created_at)) AS orders_in_month
FROM orders o
ORDER BY o.created_at;

-- Lead and lag for comparisons
SELECT
    id,
    name,
    price,
    LAG(price, 1) OVER (ORDER BY id) AS prev_price,
    LEAD(price, 1) OVER (ORDER BY id) AS next_price,
    price - LAG(price, 1) OVER (ORDER BY id) AS price_diff,
    FIRST_VALUE(name) OVER (PARTITION BY category_id ORDER BY price DESC) AS most_expensive_in_category,
    LAST_VALUE(name) OVER (PARTITION BY category_id ORDER BY price DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS cheapest_in_category
FROM products;

-- Percent rank and cumulative distribution
SELECT
    id,
    name,
    price,
    PERCENT_RANK() OVER (ORDER BY price) AS price_percentile,
    CUME_DIST() OVER (ORDER BY price) AS cumulative_distribution
FROM products;

-- ===== Common Table Expressions (CTEs) =====

-- Simple CTE
WITH active_orders AS (
    SELECT * FROM orders
    WHERE status NOT IN ('cancelled', 'delivered')
),
high_value_orders AS (
    SELECT * FROM active_orders
    WHERE total > 500
)
SELECT * FROM high_value_orders;

-- Recursive CTE for hierarchical data
WITH RECURSIVE category_tree AS (
    -- Base case: top-level categories
    SELECT
        id,
        name,
        parent_id,
        1 AS level,
        name::TEXT AS path
    FROM categories
    WHERE parent_id IS NULL

    UNION ALL

    -- Recursive case: child categories
    SELECT
        c.id,
        c.name,
        c.parent_id,
        ct.level + 1,
        ct.path || ' > ' || c.name
    FROM categories c
    JOIN category_tree ct ON c.parent_id = ct.id
    WHERE ct.level < 10 -- Prevent infinite recursion
)
SELECT * FROM category_tree
ORDER BY path;

-- CTE with INSERT
WITH new_order AS (
    INSERT INTO orders (order_number, user_id, status, shipping_address, billing_address)
    VALUES (
        'ORD-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(NEXTVAL('order_seq')::TEXT, 6, '0'),
        1,
        'pending',
        '{"street": "123 Main St", "city": "NYC", "zip": "10001"}',
        '{"street": "123 Main St", "city": "NYC", "zip": "10001"}'
    )
    RETURNING *
)
SELECT * FROM new_order;

-- ===== Subqueries =====

-- Correlated subquery
SELECT
    u.id,
    u.name,
    (SELECT COUNT(*) FROM orders o WHERE o.user_id = u.id) AS order_count,
    (SELECT COALESCE(SUM(total), 0) FROM orders o WHERE o.user_id = u.id) AS total_spent
FROM users u
WHERE (SELECT COUNT(*) FROM orders o WHERE o.user_id = u.id) > 0;

-- EXISTS subquery
SELECT * FROM users u
WHERE EXISTS (
    SELECT 1 FROM orders o
    WHERE o.user_id = u.id
    AND o.status = 'delivered'
    AND o.created_at > NOW() - INTERVAL '30 days'
);

-- NOT EXISTS subquery
SELECT * FROM products p
WHERE NOT EXISTS (
    SELECT 1 FROM order_items oi
    WHERE oi.product_id = p.id
);

-- Lateral join (row-wise subquery)
SELECT
    u.id,
    u.name,
    recent_orders.order_count,
    recent_orders.total_value
FROM users u
CROSS JOIN LATERAL (
    SELECT
        COUNT(*) AS order_count,
        COALESCE(SUM(total), 0) AS total_value
    FROM orders o
    WHERE o.user_id = u.id
    AND o.created_at > NOW() - INTERVAL '90 days'
) recent_orders
WHERE recent_orders.order_count > 0;

-- ===== Advanced Joins =====

-- Self join
SELECT
    e1.id AS employee_id,
    e1.name AS employee_name,
    e2.name AS manager_name
FROM employees e1
LEFT JOIN employees e2 ON e1.manager_id = e2.id;

-- Full outer join
SELECT
    COALESCE(c.name, 'Uncategorized') AS category,
    COUNT(p.id) AS product_count
FROM categories c
FULL OUTER JOIN products p ON c.id = p.category_id
GROUP BY c.id, c.name;

-- Cross join for date series
SELECT
    d.date,
    COALESCE(COUNT(o.id), 0) AS order_count,
    COALESCE(SUM(o.total), 0) AS daily_revenue
FROM generate_series(
    CURRENT_DATE - INTERVAL '30 days',
    CURRENT_DATE,
    '1 day'::INTERVAL
) AS d(date)
LEFT JOIN orders o ON DATE_TRUNC('day', o.created_at) = d.date
GROUP BY d.date
ORDER BY d.date;

-- ===== JSON Operations =====

-- JSON extraction
SELECT
    id,
    name,
    metadata->>'department' AS department,
    metadata->'preferences'->>'theme' AS theme,
    jsonb_array_length(metadata->'tags') AS tag_count
FROM users
WHERE metadata ? 'department';

-- JSON containment
SELECT * FROM products
WHERE attributes @> '{"brand": "TechCo"}';

-- JSON path query (PostgreSQL 12+)
SELECT
    id,
    name,
    jsonb_path_query(attributes, '$.specifications.*.value') AS spec_values
FROM products
WHERE jsonb_path_exists(attributes, '$.specifications');

-- Build JSON from query
SELECT jsonb_build_object(
    'user', jsonb_build_object(
        'id', u.id,
        'name', u.name,
        'email', u.email
    ),
    'orders', (
        SELECT jsonb_agg(jsonb_build_object(
            'id', o.id,
            'total', o.total,
            'status', o.status
        ))
        FROM orders o WHERE o.user_id = u.id
    )
) AS user_data
FROM users u
WHERE u.id = 1;

-- JSON aggregation
SELECT
    category_id,
    jsonb_agg(jsonb_build_object(
        'id', id,
        'name', name,
        'price', price
    ) ORDER BY price DESC) AS products
FROM products
WHERE is_active = true
GROUP BY category_id;

-- ===== Aggregate Functions =====

-- Basic aggregates with filters
SELECT
    COUNT(*) AS total_orders,
    COUNT(*) FILTER (WHERE status = 'delivered') AS delivered_orders,
    COUNT(*) FILTER (WHERE status = 'cancelled') AS cancelled_orders,
    AVG(total) FILTER (WHERE status = 'delivered') AS avg_delivered_value,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total) AS median_order_value,
    PERCENTILE_DISC(0.95) WITHIN GROUP (ORDER BY total) AS p95_order_value
FROM orders;

-- String aggregation
SELECT
    category_id,
    STRING_AGG(name, ', ' ORDER BY name) AS product_names,
    ARRAY_AGG(DISTINCT tags) AS all_tags
FROM products
GROUP BY category_id;

-- Mode and statistical aggregates
SELECT
    MODE() WITHIN GROUP (ORDER BY status) AS most_common_status,
    STDDEV(total) AS std_dev,
    VARIANCE(total) AS variance,
    CORR(subtotal, tax) AS subtotal_tax_correlation
FROM orders;

-- ===== Materialized Views =====

CREATE MATERIALIZED VIEW IF NOT EXISTS daily_sales_stats AS
SELECT
    DATE_TRUNC('day', o.created_at)::DATE AS date,
    COUNT(*) AS order_count,
    SUM(o.total) AS total_revenue,
    AVG(o.total) AS avg_order_value,
    COUNT(DISTINCT o.user_id) AS unique_customers
FROM orders o
WHERE o.status NOT IN ('cancelled')
GROUP BY DATE_TRUNC('day', o.created_at)
WITH DATA;

CREATE UNIQUE INDEX ON daily_sales_stats (date);

-- Refresh materialized view
REFRESH MATERIALIZED VIEW CONCURRENTLY daily_sales_stats;

-- ===== Stored Procedures =====

-- Procedure with transaction control
CREATE OR REPLACE PROCEDURE process_order(
    p_order_id INTEGER,
    p_status order_status
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_status order_status;
BEGIN
    -- Get current status with lock
    SELECT status INTO v_current_status
    FROM orders
    WHERE id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order % not found', p_order_id;
    END IF;

    -- Validate status transition
    IF v_current_status = 'cancelled' THEN
        RAISE EXCEPTION 'Cannot update cancelled order';
    END IF;

    -- Update order
    UPDATE orders
    SET status = p_status,
        completed_at = CASE WHEN p_status = 'delivered' THEN NOW() ELSE completed_at END
    WHERE id = p_order_id;

    -- Update inventory if delivered
    IF p_status = 'delivered' THEN
        UPDATE products p
        SET quantity_in_stock = quantity_in_stock - oi.quantity
        FROM order_items oi
        WHERE oi.order_id = p_order_id
        AND p.id = oi.product_id;
    END IF;

    COMMIT;
END;
$$;

-- ===== Advanced Constraints =====

-- Exclusion constraint for booking system
CREATE TABLE IF NOT EXISTS room_bookings (
    id SERIAL PRIMARY KEY,
    room_id INTEGER NOT NULL,
    guest_name VARCHAR(100) NOT NULL,
    check_in DATE NOT NULL,
    check_out DATE NOT NULL,
    CONSTRAINT no_overlapping_bookings EXCLUDE USING gist (
        room_id WITH =,
        daterange(check_in, check_out) WITH &&
    ),
    CONSTRAINT valid_dates CHECK (check_out > check_in)
);

-- Deferrable foreign key
ALTER TABLE order_items
ADD CONSTRAINT fk_order_items_order
FOREIGN KEY (order_id) REFERENCES orders(id)
DEFERRABLE INITIALLY DEFERRED;

-- ===== Partitioning =====

-- Range partitioning by date
CREATE TABLE IF NOT EXISTS events (
    id SERIAL,
    event_type VARCHAR(50) NOT NULL,
    payload JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
) PARTITION BY RANGE (created_at);

-- Create partitions
CREATE TABLE events_2024_q1 PARTITION OF events
    FOR VALUES FROM ('2024-01-01') TO ('2024-04-01');

CREATE TABLE events_2024_q2 PARTITION OF events
    FOR VALUES FROM ('2024-04-01') TO ('2024-07-01');

CREATE TABLE events_2024_q3 PARTITION OF events
    FOR VALUES FROM ('2024-07-01') TO ('2024-10-01');

CREATE TABLE events_2024_q4 PARTITION OF events
    FOR VALUES FROM ('2024-10-01') TO ('2025-01-01');

-- Default partition for future data
CREATE TABLE events_default PARTITION OF events DEFAULT;

-- List partitioning
CREATE TABLE IF NOT EXISTS sales_by_region (
    id SERIAL,
    region VARCHAR(20) NOT NULL,
    amount DECIMAL(10,2),
    sale_date DATE
) PARTITION BY LIST (region);

CREATE TABLE sales_north PARTITION OF sales_by_region FOR VALUES IN ('north', 'northeast', 'northwest');
CREATE TABLE sales_south PARTITION OF sales_by_region FOR VALUES IN ('south', 'southeast', 'southwest');
CREATE TABLE sales_other PARTITION OF sales_by_region DEFAULT;

-- ===== Row Level Security =====

-- Enable RLS
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- Policy for users to see only their orders
CREATE POLICY user_orders_policy ON orders
    FOR ALL
    TO authenticated_users
    USING (user_id = current_setting('app.current_user_id')::INTEGER);

-- Admin can see all
CREATE POLICY admin_all_orders ON orders
    FOR ALL
    TO admin_role
    USING (true)
    WITH CHECK (true);

-- ===== Performance Analysis =====

-- Explain analyze
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT u.name, COUNT(o.id)
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
GROUP BY u.id
ORDER BY COUNT(o.id) DESC
LIMIT 10;

-- Index usage stats
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;

-- Table bloat estimation
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS total_size,
    pg_size_pretty(pg_relation_size(schemaname || '.' || tablename)) AS table_size,
    pg_size_pretty(pg_indexes_size(schemaname || '.' || tablename)) AS index_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC;

-- ===== Data Migration Example =====

-- Add new column with default
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(20);

-- Backfill in batches
DO $$
DECLARE
    batch_size INTEGER := 1000;
    affected INTEGER;
BEGIN
    LOOP
        WITH batch AS (
            SELECT id FROM users
            WHERE phone IS NULL
            AND metadata->>'phone' IS NOT NULL
            LIMIT batch_size
            FOR UPDATE SKIP LOCKED
        )
        UPDATE users u
        SET phone = u.metadata->>'phone'
        FROM batch b
        WHERE u.id = b.id;

        GET DIAGNOSTICS affected = ROW_COUNT;

        IF affected = 0 THEN
            EXIT;
        END IF;

        RAISE NOTICE 'Updated % rows', affected;
        COMMIT;
    END LOOP;
END $$;

-- ===== Full Text Search =====

-- Create text search configuration
CREATE TEXT SEARCH CONFIGURATION IF NOT EXISTS english_custom (COPY = english);

-- Add search vector column
ALTER TABLE products ADD COLUMN IF NOT EXISTS search_vector tsvector
    GENERATED ALWAYS AS (
        setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(description, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(array_to_string(tags, ' '), '')), 'C')
    ) STORED;

-- Create GIN index
CREATE INDEX IF NOT EXISTS idx_products_search_vector ON products USING GIN (search_vector);

-- Full text search query
SELECT
    id,
    name,
    ts_rank(search_vector, query) AS rank,
    ts_headline('english', description, query) AS highlighted
FROM products, plainto_tsquery('english', 'wireless mouse') query
WHERE search_vector @@ query
ORDER BY rank DESC;

-- Phrase search
SELECT * FROM products
WHERE search_vector @@ phraseto_tsquery('english', 'high performance');

-- ===== Transactions and Savepoints =====

BEGIN;

SAVEPOINT before_update;

UPDATE products SET price = price * 1.1 WHERE category_id = 1;

-- Check results
SELECT COUNT(*), AVG(price) FROM products WHERE category_id = 1;

-- Rollback if needed
ROLLBACK TO SAVEPOINT before_update;

-- Or commit
COMMIT;

-- ===== Event Triggers =====

CREATE OR REPLACE FUNCTION log_ddl_changes()
RETURNS event_trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO ddl_log (event, object_type, object_name, executed_at)
    SELECT
        tg_event,
        object_type,
        object_identity,
        NOW()
    FROM pg_event_trigger_ddl_commands();
END;
$$;

CREATE EVENT TRIGGER log_ddl ON ddl_command_end
    EXECUTE FUNCTION log_ddl_changes();

-- ===== End of Extended SQL Examples =====

