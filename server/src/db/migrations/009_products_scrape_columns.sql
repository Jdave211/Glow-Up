-- ═══════════════════════════════════════════════════════════════
-- ADD SCRAPE-ENRICHED COLUMNS TO PRODUCTS TABLE
-- ═══════════════════════════════════════════════════════════════

-- How to use instructions
ALTER TABLE products ADD COLUMN IF NOT EXISTS how_to_use TEXT;

-- Product size (e.g. "1.35 oz")
ALTER TABLE products ADD COLUMN IF NOT EXISTS size TEXT;

-- Benefits section
ALTER TABLE products ADD COLUMN IF NOT EXISTS benefits TEXT;

-- Full raw ingredients text (before parsing)
ALTER TABLE products ADD COLUMN IF NOT EXISTS ingredients_raw TEXT;

-- Full details section
ALTER TABLE products ADD COLUMN IF NOT EXISTS details_full TEXT;

-- Breadcrumb path from site
ALTER TABLE products ADD COLUMN IF NOT EXISTS breadcrumbs TEXT[];

-- Product ID from retailer (e.g. Ulta's pimprod ID)
ALTER TABLE products ADD COLUMN IF NOT EXISTS external_id TEXT;

-- SKU from retailer
ALTER TABLE products ADD COLUMN IF NOT EXISTS sku TEXT;




