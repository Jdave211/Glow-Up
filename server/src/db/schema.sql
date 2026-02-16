-- ═══════════════════════════════════════════════════════════════
-- GLOWUP DATABASE SCHEMA
-- Run this in Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ═══════════════════════════════════════════════════════════════
-- USERS TABLE
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  avatar_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════
-- PROFILES TABLE (User beauty profile)
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS profiles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE UNIQUE,
  skin_type TEXT NOT NULL DEFAULT 'normal',
  hair_type TEXT NOT NULL DEFAULT 'straight',
  concerns TEXT[] DEFAULT '{}',
  budget TEXT NOT NULL DEFAULT 'medium',
  fragrance_free BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════
-- PRODUCTS TABLE (Product catalog)
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS products (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT UNIQUE NOT NULL,
  brand TEXT NOT NULL,
  price DECIMAL(10,2) NOT NULL,
  category TEXT NOT NULL,
  description TEXT,
  image_url TEXT,
  tags TEXT[] DEFAULT '{}',
  buy_link TEXT,
  retailer TEXT,
  rating DECIMAL(3,2) DEFAULT 4.0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create index for product searches
CREATE INDEX IF NOT EXISTS idx_products_tags ON products USING GIN(tags);
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);

-- ═══════════════════════════════════════════════════════════════
-- ROUTINES TABLE (Generated routines)
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS routines (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  profile_id UUID REFERENCES skin_profiles(id) ON DELETE CASCADE,
  routine_data JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_routines_user ON routines(user_id);

-- ═══════════════════════════════════════════════════════════════
-- CART_ITEMS TABLE (Shopping cart)
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS cart_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  product_id UUID REFERENCES products(id) ON DELETE CASCADE,
  quantity INTEGER DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, product_id)
);

-- ═══════════════════════════════════════════════════════════════
-- PURCHASES TABLE (Order history)
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS purchases (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  routine_id UUID REFERENCES routines(id),
  products JSONB NOT NULL,
  total_amount DECIMAL(10,2) NOT NULL,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY (RLS)
-- ═══════════════════════════════════════════════════════════════

-- Enable RLS on all tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE routines ENABLE ROW LEVEL SECURITY;
ALTER TABLE cart_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchases ENABLE ROW LEVEL SECURITY;

-- Products are public read
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Products are viewable by everyone" ON products FOR SELECT USING (true);

-- Users can only see their own data
CREATE POLICY "Users can view own profile" ON users FOR SELECT USING (true);
CREATE POLICY "Users can insert own profile" ON users FOR INSERT WITH CHECK (true);

CREATE POLICY "Profiles viewable by owner" ON profiles FOR SELECT USING (true);
CREATE POLICY "Profiles insertable by owner" ON profiles FOR INSERT WITH CHECK (true);
CREATE POLICY "Profiles updatable by owner" ON profiles FOR UPDATE USING (true);

CREATE POLICY "Routines viewable by owner" ON routines FOR SELECT USING (true);
CREATE POLICY "Routines insertable" ON routines FOR INSERT WITH CHECK (true);

CREATE POLICY "Cart viewable by owner" ON cart_items FOR SELECT USING (true);
CREATE POLICY "Cart insertable" ON cart_items FOR INSERT WITH CHECK (true);
CREATE POLICY "Cart updatable" ON cart_items FOR UPDATE USING (true);
CREATE POLICY "Cart deletable" ON cart_items FOR DELETE USING (true);

CREATE POLICY "Purchases viewable by owner" ON purchases FOR SELECT USING (true);
CREATE POLICY "Purchases insertable" ON purchases FOR INSERT WITH CHECK (true);

-- ═══════════════════════════════════════════════════════════════
-- SEED PRODUCTS
-- ═══════════════════════════════════════════════════════════════

INSERT INTO products (name, brand, price, category, description, tags, buy_link, retailer, rating) VALUES
-- Cleansers
('Hydrating Facial Cleanser', 'CeraVe', 15.99, 'cleanser', 'Gentle, non-foaming cleanser for normal to dry skin.', ARRAY['fragrance-free', 'sensitive-safe', 'dry-skin', 'ceramides'], 'https://www.amazon.com/dp/B01MSSDEPK', 'Amazon', 4.7),
('Foaming Facial Cleanser', 'CeraVe', 16.99, 'cleanser', 'Foaming cleanser for normal to oily skin.', ARRAY['fragrance-free', 'oily-skin', 'niacinamide'], 'https://www.amazon.com/dp/B01N1LL62W', 'Amazon', 4.6),
('Salicylic Acid Cleanser', 'The Inkey List', 11.99, 'cleanser', 'BHA cleanser to reduce acne and oil.', ARRAY['acne', 'oily-skin', 'bha'], 'https://www.sephora.com/product/salicylic-acid-cleanser', 'Sephora', 4.3),
('Soy Face Cleanser', 'Fresh', 42.00, 'cleanser', 'Gentle gel cleanser for all skin types.', ARRAY['all-skin', 'gentle', 'luxury'], 'https://www.sephora.com/product/soy-face-cleanser', 'Sephora', 4.5),

-- Moisturizers
('Daily Moisturizing Lotion', 'CeraVe', 13.99, 'moisturizer', 'Lightweight moisturizer for all skin types.', ARRAY['fragrance-free', 'dry-skin', 'sensitive-safe'], 'https://www.amazon.com/dp/B00E4PI2MO', 'Amazon', 4.7),
('Natural Moisturizing Factors + HA', 'The Ordinary', 8.50, 'moisturizer', 'Non-greasy hydration with hyaluronic acid.', ARRAY['fragrance-free', 'oily-skin', 'dry-skin', 'budget'], 'https://www.sephora.com/product/natural-moisturizing-factors-ha', 'Sephora', 4.4),
('Water Cream', 'Tatcha', 69.00, 'moisturizer', 'Lightweight water-burst hydration.', ARRAY['oily-skin', 'luxury', 'japanese'], 'https://www.sephora.com/product/the-water-cream', 'Sephora', 4.6),
('Ultra Facial Cream', 'Kiehls', 35.00, 'moisturizer', '24-hour hydration for all skin types.', ARRAY['all-skin', 'hydrating'], 'https://www.sephora.com/product/ultra-facial-cream', 'Sephora', 4.5),

-- Sunscreens
('UV Clear Broad-Spectrum SPF 46', 'EltaMD', 41.00, 'sunscreen', 'Oil-free sunscreen for sensitive or acne-prone skin.', ARRAY['acne', 'sensitive-safe', 'fragrance-free', 'niacinamide'], 'https://www.amazon.com/dp/B002MSN3QQ', 'Amazon', 4.8),
('Anthelios Melt-in Milk SPF 60', 'La Roche-Posay', 36.99, 'sunscreen', 'High protection for face and body.', ARRAY['fragrance-free', 'sensitive-safe', 'high-spf'], 'https://www.ulta.com/anthelios-melt-in-milk', 'Ulta', 4.7),
('Unseen Sunscreen SPF 40', 'Supergoop', 38.00, 'sunscreen', 'Invisible, weightless, scentless SPF.', ARRAY['oily-skin', 'makeup-friendly', 'invisible'], 'https://www.sephora.com/product/unseen-sunscreen', 'Sephora', 4.6),

-- Treatments
('Niacinamide 10% + Zinc 1%', 'The Ordinary', 6.50, 'treatment', 'High-strength vitamin and mineral blemish formula.', ARRAY['acne', 'oiliness', 'pigmentation', 'budget'], 'https://www.sephora.com/product/niacinamide-10-zinc-1', 'Sephora', 4.3),
('Retinol 0.5% in Squalane', 'The Ordinary', 9.00, 'treatment', 'Anti-aging and texture smoothing.', ARRAY['aging', 'texture', 'retinol', 'budget'], 'https://www.sephora.com/product/retinol-0-5-in-squalane', 'Sephora', 4.2),
('Azelaic Acid Suspension 10%', 'The Ordinary', 8.90, 'treatment', 'Brightening formula for uneven skin tone.', ARRAY['pigmentation', 'acne', 'redness', 'budget'], 'https://www.sephora.com/product/azelaic-acid-suspension', 'Sephora', 4.1),
('C E Ferulic', 'SkinCeuticals', 182.00, 'treatment', 'Advanced vitamin C serum.', ARRAY['aging', 'pigmentation', 'antioxidant', 'luxury'], 'https://www.dermstore.com/skinceuticals-c-e-ferulic', 'Dermstore', 4.7),
('Good Genes All-In-One Lactic Acid Treatment', 'Sunday Riley', 122.00, 'treatment', 'Exfoliating treatment for radiance.', ARRAY['aging', 'texture', 'brightening', 'luxury'], 'https://www.sephora.com/product/good-genes-treatment', 'Sephora', 4.4),

-- Hair - Shampoos
('No. 4 Bond Maintenance Shampoo', 'Olaplex', 30.00, 'shampoo', 'Repairs and protects hair from everyday stresses.', ARRAY['damage', 'all-hair-types', 'sulfate-free', 'bond-repair'], 'https://www.sephora.com/product/no-4-bond-maintenance-shampoo', 'Sephora', 4.5),
('Curl Quencher Moisturizing Shampoo', 'Ouidad', 26.00, 'shampoo', 'Hydrating shampoo for tight curls.', ARRAY['curly', 'coily', 'dryness', 'moisture'], 'https://www.ulta.com/curl-quencher-shampoo', 'Ulta', 4.3),
('Scalp Revival Charcoal + Coconut Oil Shampoo', 'Briogeo', 42.00, 'shampoo', 'Detoxifying shampoo for itchy scalp.', ARRAY['scalp-itch', 'clarifying', 'all-hair-types'], 'https://www.sephora.com/product/scalp-revival-shampoo', 'Sephora', 4.4),
('Color Wow Color Security Shampoo', 'Color Wow', 26.00, 'shampoo', 'Sulfate-free shampoo for color-treated hair.', ARRAY['color-treated', 'sulfate-free', 'gentle'], 'https://www.ulta.com/color-security-shampoo', 'Ulta', 4.5),

-- Hair - Conditioners
('No. 5 Bond Maintenance Conditioner', 'Olaplex', 30.00, 'conditioner', 'Restores, repairs, and hydrates.', ARRAY['damage', 'all-hair-types', 'bond-repair'], 'https://www.sephora.com/product/no-5-bond-maintenance-conditioner', 'Sephora', 4.5),
('Dont Despair, Repair! Deep Conditioning Mask', 'Briogeo', 38.00, 'conditioner', 'Weekly deep conditioning treatment.', ARRAY['damage', 'dryness', 'all-hair-types', 'deep-conditioning'], 'https://www.sephora.com/product/dont-despair-repair-mask', 'Sephora', 4.6),

-- Hair - Styling
('Ghost Oil', 'Verb', 20.00, 'styling', 'Weightless hair oil to fight frizz.', ARRAY['frizz', 'shine', 'all-hair-types', 'lightweight'], 'https://www.sephora.com/product/ghost-oil', 'Sephora', 4.4),
('Dream Coat Supernatural Spray', 'Color Wow', 28.00, 'styling', 'Anti-frizz humidity-proofing treatment.', ARRAY['frizz', 'humidity', 'straight', 'wavy'], 'https://www.ulta.com/dream-coat-spray', 'Ulta', 4.6),
('Curl Defining Cream', 'Ouai', 28.00, 'styling', 'Defines curls and reduces frizz.', ARRAY['curly', 'wavy', 'frizz', 'definition'], 'https://www.sephora.com/product/curl-defining-cream', 'Sephora', 4.3),
('No. 7 Bonding Oil', 'Olaplex', 30.00, 'styling', 'Highly concentrated reparative styling oil.', ARRAY['damage', 'frizz', 'shine', 'all-hair-types'], 'https://www.sephora.com/product/no-7-bonding-oil', 'Sephora', 4.5)

ON CONFLICT (name) DO NOTHING;











