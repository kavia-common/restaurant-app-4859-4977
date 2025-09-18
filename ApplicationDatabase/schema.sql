-- Restaurant Application - PostgreSQL Schema
-- Safe to run multiple times on an empty DB; uses CREATE TYPE IF NOT EXISTS and CREATE TABLE IF NOT EXISTS patterns.
-- For destructive re-runs, uncomment DROP statements at section tops.

-- ========== EXTENSIONS ==========
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ========== ENUM TYPES ==========
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE user_role AS ENUM ('customer', 'staff', 'admin');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'order_status') THEN
        CREATE TYPE order_status AS ENUM ('pending', 'confirmed', 'preparing', 'ready', 'completed', 'cancelled', 'refunded');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'fulfillment_type') THEN
        CREATE TYPE fulfillment_type AS ENUM ('pickup', 'delivery', 'dine_in');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_status') THEN
        CREATE TYPE payment_status AS ENUM ('pending', 'authorized', 'paid', 'failed', 'refunded');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payment_method') THEN
        CREATE TYPE payment_method AS ENUM ('card', 'wallet', 'cod');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'spice_level') THEN
        CREATE TYPE spice_level AS ENUM ('none', 'mild', 'medium', 'hot', 'extra_hot');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'reservation_status') THEN
        CREATE TYPE reservation_status AS ENUM ('requested', 'confirmed', 'seated', 'cancelled', 'completed', 'no_show');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_channel') THEN
        CREATE TYPE notification_channel AS ENUM ('push', 'email', 'sms', 'inapp');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_status') THEN
        CREATE TYPE notification_status AS ENUM ('queued', 'sent', 'delivered', 'failed');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'loyalty_txn_type') THEN
        CREATE TYPE loyalty_txn_type AS ENUM ('earn', 'redeem', 'adjust');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'catering_status') THEN
        CREATE TYPE catering_status AS ENUM ('requested', 'quoted', 'confirmed', 'cancelled', 'completed');
    END IF;
END$$;

-- ========== CORE: USERS & AUTH ==========
CREATE TABLE IF NOT EXISTS app_users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email           CITEXT UNIQUE NOT NULL,
    phone           VARCHAR(30),
    full_name       VARCHAR(150),
    password_hash   TEXT,                         -- null for social accounts
    role            user_role NOT NULL DEFAULT 'customer',
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT email_or_phone CHECK (email IS NOT NULL OR phone IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS auth_providers (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    provider        VARCHAR(50) NOT NULL,         -- e.g., google, apple, facebook
    provider_user_id VARCHAR(255) NOT NULL,
    access_token    TEXT,
    refresh_token   TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (provider, provider_user_id),
    UNIQUE (user_id, provider)
);

-- ========== LOCALIZATION / SETTINGS ==========
CREATE TABLE IF NOT EXISTS locales (
    code            VARCHAR(10) PRIMARY KEY,      -- e.g., en, si, ta
    name            VARCHAR(100) NOT NULL,
    is_default      BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS app_settings (
    key             VARCHAR(100) PRIMARY KEY,
    value           JSONB NOT NULL,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========== MENU & CATALOG ==========
CREATE TABLE IF NOT EXISTS menu_categories (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    slug            VARCHAR(60) UNIQUE NOT NULL,
    position        INT NOT NULL DEFAULT 0,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Translations for categories
CREATE TABLE IF NOT EXISTS menu_category_i18n (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category_id     UUID NOT NULL REFERENCES menu_categories(id) ON DELETE CASCADE,
    locale_code     VARCHAR(10) NOT NULL REFERENCES locales(code) ON DELETE CASCADE,
    title           VARCHAR(120) NOT NULL,
    description     TEXT,
    UNIQUE (category_id, locale_code)
);

CREATE INDEX IF NOT EXISTS idx_menu_category_i18n_cat ON menu_category_i18n(category_id);

CREATE TABLE IF NOT EXISTS allergens (
    code            VARCHAR(30) PRIMARY KEY,      -- e.g., nuts, gluten, dairy
    label           VARCHAR(120) NOT NULL
);

CREATE TABLE IF NOT EXISTS menu_items (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category_id     UUID NOT NULL REFERENCES menu_categories(id) ON DELETE RESTRICT,
    sku             VARCHAR(50) UNIQUE,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    base_spice      spice_level NOT NULL DEFAULT 'none',
    image_url       TEXT,                         -- primary image
    calories        INT,                          -- optional nutrition
    nutrition_info  JSONB,                        -- additional nutrition details
    allergens       TEXT[],                       -- quick lookup labels (denormalized from link table)
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Translations for items
CREATE TABLE IF NOT EXISTS menu_item_i18n (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    item_id         UUID NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
    locale_code     VARCHAR(10) NOT NULL REFERENCES locales(code) ON DELETE CASCADE,
    title           VARCHAR(160) NOT NULL,
    description     TEXT,
    ingredients     TEXT,                         -- localized ingredient list
    UNIQUE (item_id, locale_code)
);

CREATE INDEX IF NOT EXISTS idx_menu_item_i18n_item ON menu_item_i18n(item_id);

-- Multiple images for items
CREATE TABLE IF NOT EXISTS menu_item_images (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    item_id         UUID NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
    image_url       TEXT NOT NULL,
    position        INT NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_menu_item_images_item ON menu_item_images(item_id);

-- Portion/pricing options
CREATE TABLE IF NOT EXISTS menu_item_options (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    item_id         UUID NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
    option_code     VARCHAR(30) NOT NULL,         -- e.g., normal, full
    price_lkr       NUMERIC(12,2) NOT NULL CHECK (price_lkr >= 0),
    is_default      BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE (item_id, option_code)
);

CREATE INDEX IF NOT EXISTS idx_menu_item_options_item ON menu_item_options(item_id);

-- Add-ons for items
CREATE TABLE IF NOT EXISTS menu_item_addons (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    item_id         UUID NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
    name            VARCHAR(120) NOT NULL,
    price_lkr       NUMERIC(12,2) NOT NULL CHECK (price_lkr >= 0),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE INDEX IF NOT EXISTS idx_menu_item_addons_item ON menu_item_addons(item_id);

-- Allergen mapping (normalized, in addition to denormalized array on items)
CREATE TABLE IF NOT EXISTS menu_item_allergens (
    item_id         UUID NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
    allergen_code   VARCHAR(30) NOT NULL REFERENCES allergens(code) ON DELETE RESTRICT,
    PRIMARY KEY (item_id, allergen_code)
);

-- ========== CARTS (optional server-side carts storage) ==========
CREATE TABLE IF NOT EXISTS carts (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID REFERENCES app_users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS cart_items (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    cart_id         UUID NOT NULL REFERENCES carts(id) ON DELETE CASCADE,
    item_id         UUID NOT NULL REFERENCES menu_items(id) ON DELETE RESTRICT,
    option_id       UUID REFERENCES menu_item_options(id) ON DELETE SET NULL,
    quantity        INT NOT NULL CHECK (quantity > 0),
    spice           spice_level,
    customizations  JSONB, -- addons selected and other customization details
    unit_price_lkr  NUMERIC(12,2) NOT NULL CHECK (unit_price_lkr >= 0),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cart_items_cart ON cart_items(cart_id);

-- ========== ORDERS ==========
CREATE TABLE IF NOT EXISTS orders (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID REFERENCES app_users(id) ON DELETE SET NULL,
    fulfillment         fulfillment_type NOT NULL,
    status              order_status NOT NULL DEFAULT 'pending',
    subtotal_lkr        NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (subtotal_lkr >= 0),
    discount_lkr        NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (discount_lkr >= 0),
    tax_lkr             NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (tax_lkr >= 0),
    delivery_fee_lkr    NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (delivery_fee_lkr >= 0),
    total_lkr           NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total_lkr >= 0),
    delivery_address    JSONB,                           -- for delivery
    dine_in_reservation_id UUID REFERENCES reservations(id) DEFERRABLE INITIALLY DEFERRED,
    special_instructions TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    confirmed_at        TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    cancelled_at        TIMESTAMPTZ
);

-- We'll create reservations table first before adding FK above in a second pass due to forward ref.
-- Create a placeholder to avoid error; then we will alter after reservations exists if needed.

CREATE TABLE IF NOT EXISTS order_items (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id        UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    item_id         UUID NOT NULL REFERENCES menu_items(id) ON DELETE RESTRICT,
    title_snapshot  TEXT NOT NULL,                         -- snapshot for analytics/history
    option_code     VARCHAR(30),
    spice           spice_level,
    quantity        INT NOT NULL CHECK (quantity > 0),
    unit_price_lkr  NUMERIC(12,2) NOT NULL CHECK (unit_price_lkr >= 0),
    addons          JSONB,                                 -- selected add-ons snapshot
    notes           TEXT
);

CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);

-- ========== PAYMENTS ==========
CREATE TABLE IF NOT EXISTS payments (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id        UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    method          payment_method NOT NULL,
    provider_ref    VARCHAR(200),                          -- gateway id or receipt reference
    status          payment_status NOT NULL DEFAULT 'pending',
    amount_lkr      NUMERIC(12,2) NOT NULL CHECK (amount_lkr >= 0),
    currency        VARCHAR(3) NOT NULL DEFAULT 'LKR',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    authorized_at   TIMESTAMPTZ,
    paid_at         TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_order_unique_paid
    ON payments(order_id)
    WHERE status IN ('authorized','paid');

-- ========== RESERVATIONS ==========
CREATE TABLE IF NOT EXISTS reservations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID REFERENCES app_users(id) ON DELETE SET NULL,
    reservation_time TIMESTAMPTZ NOT NULL,
    party_size      INT NOT NULL CHECK (party_size > 0),
    status          reservation_status NOT NULL DEFAULT 'requested',
    table_notes     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    confirmed_at    TIMESTAMPTZ,
    cancelled_at    TIMESTAMPTZ
);

-- Now that reservations exists, add the optional dine-in link if not already present properly
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='orders' AND column_name='dine_in_reservation_id') THEN
        -- Ensure FK constraint exists; try to add if missing
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.table_constraints
            WHERE table_name='orders' AND constraint_type='FOREIGN KEY' AND constraint_name='orders_dine_in_reservation_id_fkey'
        ) THEN
            ALTER TABLE orders
            ADD CONSTRAINT orders_dine_in_reservation_id_fkey
            FOREIGN KEY (dine_in_reservation_id) REFERENCES reservations(id) DEFERRABLE INITIALLY DEFERRED;
        END IF;
    END IF;
END$$;

-- ========== REVIEWS ==========
CREATE TABLE IF NOT EXISTS reviews (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id        UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    user_id         UUID REFERENCES app_users(id) ON DELETE SET NULL,
    item_id         UUID REFERENCES menu_items(id) ON DELETE SET NULL,
    rating          INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    title           VARCHAR(200),
    comment         TEXT,
    is_featured     BOOLEAN NOT NULL DEFAULT FALSE,
    is_moderated    BOOLEAN NOT NULL DEFAULT TRUE, -- mark true once approved
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_reviews_unique_order_item
    ON reviews(order_id, item_id)
    WHERE item_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS review_photos (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    review_id       UUID NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
    image_url       TEXT NOT NULL,
    position        INT NOT NULL DEFAULT 0
);

-- ========== LOYALTY ==========
CREATE TABLE IF NOT EXISTS loyalty_accounts (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID UNIQUE NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    points_balance  INT NOT NULL DEFAULT 0 CHECK (points_balance >= 0),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS loyalty_transactions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    account_id      UUID NOT NULL REFERENCES loyalty_accounts(id) ON DELETE CASCADE,
    txn_type        loyalty_txn_type NOT NULL,
    points          INT NOT NULL CHECK (points >= 0),
    related_order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
    description     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_loyalty_txn_account ON loyalty_transactions(account_id);

-- ========== REFERRALS (marketing) ==========
CREATE TABLE IF NOT EXISTS referrals (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    referrer_user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    referred_user_id UUID UNIQUE REFERENCES app_users(id) ON DELETE SET NULL,
    code_used       VARCHAR(40),
    reward_points   INT NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========== PROMOTIONS ==========
CREATE TABLE IF NOT EXISTS promotions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code            VARCHAR(40) UNIQUE NOT NULL,
    title           VARCHAR(200),
    description     TEXT,
    discount_type   VARCHAR(20) NOT NULL DEFAULT 'amount', -- amount|percent
    discount_value  NUMERIC(12,2) NOT NULL CHECK (discount_value >= 0),
    active_from     TIMESTAMPTZ,
    active_to       TIMESTAMPTZ,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS promotion_usages (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    promotion_id    UUID NOT NULL REFERENCES promotions(id) ON DELETE CASCADE,
    user_id         UUID REFERENCES app_users(id) ON DELETE SET NULL,
    order_id        UUID UNIQUE REFERENCES orders(id) ON DELETE SET NULL,
    used_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========== NOTIFICATIONS ==========
CREATE TABLE IF NOT EXISTS notification_tokens (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    token           TEXT NOT NULL,
    platform        VARCHAR(20), -- ios/android/web
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, token)
);

CREATE TABLE IF NOT EXISTS notifications (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID REFERENCES app_users(id) ON DELETE SET NULL,
    channel         notification_channel NOT NULL DEFAULT 'inapp',
    title           VARCHAR(200) NOT NULL,
    body            TEXT NOT NULL,
    metadata        JSONB,
    status          notification_status NOT NULL DEFAULT 'queued',
    scheduled_at    TIMESTAMPTZ,
    sent_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id);

-- ========== ANALYTICS ==========
-- Event log for generic analytics
CREATE TABLE IF NOT EXISTS analytics_events (
    id              BIGSERIAL PRIMARY KEY,
    user_id         UUID REFERENCES app_users(id) ON DELETE SET NULL,
    event_name      VARCHAR(100) NOT NULL,
    event_time      TIMESTAMPTZ NOT NULL DEFAULT now(),
    properties      JSONB
);

-- Daily aggregates for quick dashboard
CREATE TABLE IF NOT EXISTS analytics_daily (
    day             DATE PRIMARY KEY,
    total_orders    INT NOT NULL DEFAULT 0,
    revenue_lkr     NUMERIC(14,2) NOT NULL DEFAULT 0,
    avg_order_value NUMERIC(12,2) NOT NULL DEFAULT 0,
    new_users       INT NOT NULL DEFAULT 0,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Popular items aggregates
CREATE TABLE IF NOT EXISTS analytics_popular_items (
    id              BIGSERIAL PRIMARY KEY,
    item_id         UUID NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
    day             DATE NOT NULL,
    order_count     INT NOT NULL DEFAULT 0,
    UNIQUE (item_id, day)
);

-- ========== CATERING REQUESTS ==========
CREATE TABLE IF NOT EXISTS catering_requests (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID REFERENCES app_users(id) ON DELETE SET NULL,
    event_date      DATE NOT NULL,
    event_time      TIME,
    people_count    INT NOT NULL CHECK (people_count > 0),
    location        TEXT,
    notes           TEXT,
    status          catering_status NOT NULL DEFAULT 'requested',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS catering_request_items (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    request_id      UUID NOT NULL REFERENCES catering_requests(id) ON DELETE CASCADE,
    item_id         UUID NOT NULL REFERENCES menu_items(id) ON DELETE RESTRICT,
    option_id       UUID REFERENCES menu_item_options(id) ON DELETE SET NULL,
    quantity        INT NOT NULL CHECK (quantity > 0)
);

-- ========== FEEDBACK ==========
CREATE TABLE IF NOT EXISTS feedback (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID REFERENCES app_users(id) ON DELETE SET NULL,
    subject         VARCHAR(200),
    message         TEXT NOT NULL,
    metadata        JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ========== CONFIGURATION / OPERATING HOURS ==========
CREATE TABLE IF NOT EXISTS operating_hours (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    day_of_week     INT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6), -- 0=Sunday
    open_time       TIME NOT NULL,
    close_time      TIME NOT NULL,
    is_open_24h     BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE (day_of_week)
);

-- ========== INDEXES FOR PERFORMANCE ==========
CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created ON orders(created_at);

CREATE INDEX IF NOT EXISTS idx_payments_order ON payments(order_id);

CREATE INDEX IF NOT EXISTS idx_reservations_user ON reservations(user_id);
CREATE INDEX IF NOT EXISTS idx_reservations_time ON reservations(reservation_time);

CREATE INDEX IF NOT EXISTS idx_reviews_item ON reviews(item_id);
CREATE INDEX IF NOT EXISTS idx_reviews_user ON reviews(user_id);

-- ========== TRIGGERS & FUNCTIONS ==========
-- Updated_at auto-update trigger
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_users_updated_at') THEN
        CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON app_users
        FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_menu_categories_updated_at') THEN
        CREATE TRIGGER trg_menu_categories_updated_at BEFORE UPDATE ON menu_categories
        FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_menu_items_updated_at') THEN
        CREATE TRIGGER trg_menu_items_updated_at BEFORE UPDATE ON menu_items
        FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_orders_updated_at') THEN
        CREATE TRIGGER trg_orders_updated_at BEFORE UPDATE ON orders
        FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_payments_updated_at') THEN
        CREATE TRIGGER trg_payments_updated_at BEFORE UPDATE ON payments
        FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_reservations_updated_at') THEN
        CREATE TRIGGER trg_reservations_updated_at BEFORE UPDATE ON reservations
        FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_loyalty_accounts_updated_at') THEN
        CREATE TRIGGER trg_loyalty_accounts_updated_at BEFORE UPDATE ON loyalty_accounts
        FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_catering_requests_updated_at') THEN
        CREATE TRIGGER trg_catering_requests_updated_at BEFORE UPDATE ON catering_requests
        FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
    END IF;
END$$;

-- ========== SEED DATA (SMOKE TEST) ==========
-- Locales
INSERT INTO locales (code, name, is_default)
VALUES 
('en', 'English', TRUE),
('si', 'Sinhala', FALSE),
('ta', 'Tamil', FALSE)
ON CONFLICT (code) DO NOTHING;

-- Operating hours sample
INSERT INTO operating_hours (day_of_week, open_time, close_time, is_open_24h)
VALUES
(0, '00:00', '23:59', TRUE),
(1, '00:00', '23:59', TRUE),
(2, '00:00', '23:59', TRUE),
(3, '00:00', '23:59', TRUE),
(4, '00:00', '23:59', TRUE),
(5, '00:00', '23:59', TRUE),
(6, '00:00', '23:59', TRUE)
ON CONFLICT (day_of_week) DO NOTHING;

-- Allergens
INSERT INTO allergens (code, label) VALUES
('nuts', 'Nuts'), ('gluten', 'Gluten'), ('dairy', 'Dairy'), ('soy', 'Soy')
ON CONFLICT (code) DO NOTHING;

-- Users (one admin, one staff, one customer)
INSERT INTO app_users (email, full_name, password_hash, role)
VALUES
('admin@example.com', 'Admin User', 'hash_admin', 'admin'),
('staff@example.com', 'Staff User', 'hash_staff', 'staff'),
('customer@example.com', 'Customer One', 'hash_customer', 'customer')
ON CONFLICT (email) DO NOTHING;

-- Loyalty accounts for users
INSERT INTO loyalty_accounts (user_id, points_balance)
SELECT id, 100 FROM app_users WHERE email = 'customer@example.com'
ON CONFLICT (user_id) DO NOTHING;

-- Categories
INSERT INTO menu_categories (slug, position, is_active)
VALUES ('traditional', 1, TRUE), ('street-food', 2, TRUE), ('grilled', 3, TRUE)
ON CONFLICT (slug) DO NOTHING;

-- Category i18n
INSERT INTO menu_category_i18n (category_id, locale_code, title, description)
SELECT id, 'en', 'Traditional', 'Traditional rice and curry combinations' FROM menu_categories WHERE slug='traditional'
ON CONFLICT DO NOTHING;

INSERT INTO menu_category_i18n (category_id, locale_code, title, description)
SELECT id, 'en', 'Street Food', 'Street food specialties like kottu' FROM menu_categories WHERE slug='street-food'
ON CONFLICT DO NOTHING;

-- Items
WITH cat AS (SELECT id FROM menu_categories WHERE slug='traditional' LIMIT 1)
INSERT INTO menu_items (category_id, sku, is_active, base_spice, image_url, calories, nutrition_info, allergens)
SELECT id, 'RICCURRY001', TRUE, 'mild', 'https://example.com/images/rice-curry.jpg', 850, '{"protein":25,"carbs":110,"fat":20}', ARRAY['dairy']
FROM cat
ON CONFLICT (sku) DO NOTHING;

WITH cat AS (SELECT id FROM menu_categories WHERE slug='street-food' LIMIT 1)
INSERT INTO menu_items (category_id, sku, is_active, base_spice, image_url, calories, nutrition_info, allergens)
SELECT id, 'KOTTU001', TRUE, 'medium', 'https://example.com/images/kottu.jpg', 950, '{"protein":30,"carbs":120,"fat":25}', ARRAY['gluten', 'soy']
FROM cat
ON CONFLICT (sku) DO NOTHING;

-- Item i18n
INSERT INTO menu_item_i18n (item_id, locale_code, title, description, ingredients)
SELECT id, 'en', 'Rice & Curry', 'Classic rice with assorted curries', 'Rice, lentils, vegetables, spices'
FROM menu_items WHERE sku='RICCURRY001'
ON CONFLICT DO NOTHING;

INSERT INTO menu_item_i18n (item_id, locale_code, title, description, ingredients)
SELECT id, 'en', 'Kottu Roti', 'Chopped flatbread stir-fried with vegetables and spices', 'Roti, vegetables, egg, spices'
FROM menu_items WHERE sku='KOTTU001'
ON CONFLICT DO NOTHING;

-- Item options (portion/pricing)
INSERT INTO menu_item_options (item_id, option_code, price_lkr, is_default)
SELECT id, 'normal', 1200, TRUE FROM menu_items WHERE sku='RICCURRY001'
ON CONFLICT (item_id, option_code) DO NOTHING;

INSERT INTO menu_item_options (item_id, option_code, price_lkr, is_default)
SELECT id, 'full', 1800, FALSE FROM menu_items WHERE sku='RICCURRY001'
ON CONFLICT (item_id, option_code) DO NOTHING;

INSERT INTO menu_item_options (item_id, option_code, price_lkr, is_default)
SELECT id, 'normal', 1500, TRUE FROM menu_items WHERE sku='KOTTU001'
ON CONFLICT (item_id, option_code) DO NOTHING;

-- Item add-ons
INSERT INTO menu_item_addons (item_id, name, price_lkr, is_active)
SELECT id, 'Extra Curry', 200, TRUE FROM menu_items WHERE sku='RICCURRY001'
ON CONFLICT DO NOTHING;

INSERT INTO menu_item_addons (item_id, name, price_lkr, is_active)
SELECT id, 'Cheese', 150, TRUE FROM menu_items WHERE sku='KOTTU001'
ON CONFLICT DO NOTHING;

-- Allergen mapping
INSERT INTO menu_item_allergens (item_id, allergen_code)
SELECT id, 'dairy' FROM menu_items WHERE sku='RICCURRY001'
ON CONFLICT DO NOTHING;

INSERT INTO menu_item_allergens (item_id, allergen_code)
SELECT id, 'gluten' FROM menu_items WHERE sku='KOTTU001'
ON CONFLICT DO NOTHING;

-- Sample order flow for smoke testing
-- Create a simple order for the customer with one item
WITH c AS (SELECT id AS user_id FROM app_users WHERE email='customer@example.com' LIMIT 1),
     i AS (SELECT mi.id AS item_id, mio.option_code, mio.price_lkr
           FROM menu_items mi JOIN menu_item_options mio ON mio.item_id=mi.id
           WHERE mi.sku='RICCURRY001' AND mio.option_code='normal' LIMIT 1)
INSERT INTO orders (user_id, fulfillment, status, subtotal_lkr, tax_lkr, total_lkr, special_instructions)
SELECT c.user_id, 'pickup', 'confirmed', i.price_lkr, (i.price_lkr*0.08)::NUMERIC, (i.price_lkr*1.08)::NUMERIC, 'No onions'
FROM c, i
RETURNING id INTO TEMP TABLE created_order_ids;

-- Add order item snapshot
WITH o AS (SELECT id FROM created_order_ids LIMIT 1),
     snap AS (
        SELECT mi.id AS item_id, mii.title AS title_snapshot, mio.option_code, mio.price_lkr
        FROM menu_items mi
        JOIN menu_item_i18n mii ON mii.item_id=mi.id AND mii.locale_code='en'
        JOIN menu_item_options mio ON mio.item_id=mi.id AND mio.option_code='normal'
        WHERE mi.sku='RICCURRY001' LIMIT 1
     )
INSERT INTO order_items (order_id, item_id, title_snapshot, option_code, spice, quantity, unit_price_lkr, addons, notes)
SELECT o.id, snap.item_id, snap.title_snapshot, snap.option_code, 'mild', 1, snap.price_lkr, '[]'::jsonb, 'Less spicy please'
FROM o, snap;

-- Add payment
WITH o AS (SELECT id FROM created_order_ids LIMIT 1),
     totals AS (SELECT total_lkr FROM orders, created_order_ids WHERE orders.id = created_order_ids.id)
INSERT INTO payments (order_id, method, status, amount_lkr, currency, provider_ref, authorized_at, paid_at)
SELECT o.id, 'cod', 'paid', totals.total_lkr, 'LKR', 'CASH-RECEIPT-001', now(), now()
FROM o, totals
ON CONFLICT DO NOTHING;

-- Review for the order
WITH o AS (SELECT id, user_id FROM created_order_ids LIMIT 1),
     item AS (SELECT id FROM menu_items WHERE sku='RICCURRY001' LIMIT 1)
INSERT INTO reviews (order_id, user_id, item_id, rating, title, comment, is_featured, is_moderated)
SELECT o.id, o.user_id, item.id, 5, 'Delicious!', 'Truly authentic taste.', TRUE, TRUE
FROM o, item
ON CONFLICT DO NOTHING;

-- ========== END OF SCHEMA ==========
