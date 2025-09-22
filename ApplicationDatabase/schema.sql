-- Users
CREATE TABLE IF NOT EXISTS app_user (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Categories
CREATE TABLE IF NOT EXISTS category (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  image_url TEXT,
  sort_order INT DEFAULT 0
);

-- Menu items
CREATE TABLE IF NOT EXISTS menu_item (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id UUID REFERENCES category(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  ingredients JSONB DEFAULT '[]'::jsonb,
  allergens JSONB DEFAULT '[]'::jsonb,
  spice_level INT DEFAULT 0,
  image_url TEXT,
  nutrition JSONB DEFAULT '{}'::jsonb
);

-- Prices by portion
CREATE TABLE IF NOT EXISTS menu_price (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  menu_item_id UUID REFERENCES menu_item(id) ON DELETE CASCADE,
  portion TEXT NOT NULL,
  price_lkr NUMERIC(12,2) NOT NULL
);

-- Orders
CREATE TABLE IF NOT EXISTS app_order (
  id UUID PRIMARY KEY,
  status TEXT NOT NULL,
  fulfillment TEXT NOT NULL,
  total_lkr NUMERIC(12,2) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS order_item (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID REFERENCES app_order(id) ON DELETE CASCADE,
  menu_item_id UUID REFERENCES menu_item(id),
  portion TEXT NOT NULL,
  quantity INT NOT NULL DEFAULT 1,
  spice TEXT,
  add_ons JSONB DEFAULT '[]'::jsonb
);

-- Reviews
CREATE TABLE IF NOT EXISTS review (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID REFERENCES app_order(id),
  rating INT NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  photo_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Loyalty
CREATE TABLE IF NOT EXISTS loyalty_transaction (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES app_user(id),
  points INT NOT NULL,
  reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Promotions
CREATE TABLE IF NOT EXISTS promotion (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  description TEXT,
  active BOOLEAN NOT NULL DEFAULT true,
  sort_order INT DEFAULT 0
);

-- Notifications
CREATE TABLE IF NOT EXISTS notification (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  body TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
