-- ═══════════════════════════════════════════════════════════════
-- EXTENDED PRODUCTS TABLE - With Rich Metadata
-- ═══════════════════════════════════════════════════════════════

-- Drop existing products table if needed (to rebuild with new schema)
DROP TABLE IF EXISTS products CASCADE;

CREATE TABLE IF NOT EXISTS products (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  
  -- Basic Info
  name TEXT NOT NULL,
  brand TEXT NOT NULL,
  category TEXT NOT NULL, -- Cleanser, Moisturizer, Sunscreen, Treatment, etc.
  subcategory TEXT, -- Oil Cleanser, Gel Moisturizer, etc.
  
  -- Pricing & Availability
  price DECIMAL(10,2) NOT NULL,
  tier TEXT DEFAULT 'mid', -- budget, mid, premium, luxury
  stock_availability TEXT DEFAULT 'in_stock',
  
  -- Descriptions
  summary TEXT,
  moat TEXT, -- What makes this product unique
  
  -- Targeting
  target_skin_type TEXT[], -- oily, dry, combination, sensitive, normal, acne-prone
  target_hair_type TEXT[], -- straight, wavy, curly, coily
  target_concerns TEXT[], -- acne, aging, pigmentation, frizz, damage, etc.
  target_audience TEXT, -- Unisex, Women, Men
  
  -- Attributes (tags)
  attributes TEXT[] DEFAULT '{}', -- fragrance-free, non-comedogenic, vegan, etc.
  ingredients TEXT[], -- Key ingredients
  
  -- Links & Sources
  buy_link TEXT,
  source_links TEXT[],
  retailer TEXT,
  image_url TEXT,
  
  -- Ratings
  rating DECIMAL(3,2) DEFAULT 4.0,
  review_count INTEGER DEFAULT 0,
  
  -- Metadata
  data_source TEXT, -- data1, data2, manual
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Unique constraint for upsert
CREATE UNIQUE INDEX IF NOT EXISTS idx_products_name_brand ON products(name, brand);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_products_brand ON products(brand);
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);
CREATE INDEX IF NOT EXISTS idx_products_price ON products(price);
CREATE INDEX IF NOT EXISTS idx_products_target_skin ON products USING GIN(target_skin_type);
CREATE INDEX IF NOT EXISTS idx_products_target_concerns ON products USING GIN(target_concerns);
CREATE INDEX IF NOT EXISTS idx_products_attributes ON products USING GIN(attributes);

-- Full text search
CREATE INDEX IF NOT EXISTS idx_products_search ON products USING GIN(
  to_tsvector('english', coalesce(name, '') || ' ' || coalesce(brand, '') || ' ' || coalesce(summary, ''))
);

-- RLS
ALTER TABLE products ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'products' AND policyname = 'Products readable by all') THEN
    CREATE POLICY "Products readable by all" ON products FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'products' AND policyname = 'Products insertable') THEN
    CREATE POLICY "Products insertable" ON products FOR INSERT WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'products' AND policyname = 'Products updatable') THEN
    CREATE POLICY "Products updatable" ON products FOR UPDATE USING (true);
  END IF;
END $$;

-- Updated at trigger
CREATE OR REPLACE FUNCTION update_products_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_products_timestamp ON products;
CREATE TRIGGER trigger_update_products_timestamp
  BEFORE UPDATE ON products
  FOR EACH ROW
  EXECUTE FUNCTION update_products_timestamp();

