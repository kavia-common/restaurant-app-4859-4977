-- Create a demo user (password: demo123)
INSERT INTO app_user (id, name, email, password_hash)
VALUES (
  gen_random_uuid(),
  'Demo User',
  'demo@example.com',
  '$2a$10$8qD3uJ3Jw0T2rjF9GZQH2O4gkP/9Q1rflQ0Q3P2q2OqF0yQY5E1Qq' -- bcrypt hash for 'demo123' (example)
)
ON CONFLICT (email) DO NOTHING;

-- Categories
INSERT INTO category (id, name, description, image_url, sort_order)
VALUES
  (gen_random_uuid(), 'Traditional', 'Rice and curry combinations', '', 1),
  (gen_random_uuid(), 'Street Food', 'Kottu, etc.', '', 2),
  (gen_random_uuid(), 'Grilled', 'Grilled and sizzling items', '', 3)
ON CONFLICT DO NOTHING;

-- One sample item per category
WITH c AS (SELECT id FROM category ORDER BY sort_order)
INSERT INTO menu_item (id, category_id, name, description, ingredients, allergens, spice_level, image_url, nutrition)
SELECT
  gen_random_uuid(), (SELECT id FROM c LIMIT 1), 'Chicken Rice & Curry', 'Classic rice and curry plate',
  '["rice","chicken","curry","sambol"]'::jsonb, '["gluten-free"]'::jsonb, 1, '',
  '{"calories": 680}'::jsonb
ON CONFLICT DO NOTHING;

WITH c AS (SELECT id FROM category ORDER BY sort_order)
INSERT INTO menu_item (id, category_id, name, description, ingredients, allergens, spice_level, image_url, nutrition)
SELECT
  gen_random_uuid(), (SELECT id FROM c OFFSET 1 LIMIT 1), 'Chicken Kottu', 'Street food favorite',
  '["roti","egg","chicken","leeks"]'::jsonb, '["gluten"]'::jsonb, 2, '',
  '{"calories": 720}'::jsonb
ON CONFLICT DO NOTHING;

WITH c AS (SELECT id FROM category ORDER BY sort_order)
INSERT INTO menu_item (id, category_id, name, description, ingredients, allergens, spice_level, image_url, nutrition)
SELECT
  gen_random_uuid(), (SELECT id FROM c OFFSET 2 LIMIT 1), 'Grilled Fish', 'Fresh grilled fish with herbs',
  '["fish","herbs","lemon"]'::jsonb, '["fish"]'::jsonb, 1, '',
  '{"calories": 500}'::jsonb
ON CONFLICT DO NOTHING;

-- Prices
INSERT INTO menu_price (id, menu_item_id, portion, price_lkr)
SELECT gen_random_uuid(), mi.id, 'normal', 1200 FROM menu_item mi
ON CONFLICT DO NOTHING;
INSERT INTO menu_price (id, menu_item_id, portion, price_lkr)
SELECT gen_random_uuid(), mi.id, 'full', 2000 FROM menu_item mi
ON CONFLICT DO NOTHING;

-- Promotions
INSERT INTO promotion (id, title, description, active, sort_order)
VALUES (gen_random_uuid(), 'New Year Special', 'Celebrate with 20% off traditional menu', true, 1)
ON CONFLICT DO NOTHING;

-- Notifications
INSERT INTO notification (id, title, body)
VALUES (gen_random_uuid(), 'Welcome', 'Thanks for installing our app!')
ON CONFLICT DO NOTHING;
