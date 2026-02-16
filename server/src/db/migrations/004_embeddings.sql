-- ═══════════════════════════════════════════════════════════════
-- EMBEDDINGS FOR HYBRID SEARCH
-- Requires pgvector extension (enabled by default in Supabase)
-- ═══════════════════════════════════════════════════════════════

-- Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Add embedding column to products
ALTER TABLE products 
ADD COLUMN IF NOT EXISTS embedding vector(1536);

-- Add text search vector for hybrid search
ALTER TABLE products
ADD COLUMN IF NOT EXISTS search_vector tsvector;

-- Create function to generate search vector
CREATE OR REPLACE FUNCTION products_search_vector_update() RETURNS trigger AS $$
BEGIN
  NEW.search_vector := 
    setweight(to_tsvector('english', coalesce(NEW.name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.brand, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(NEW.summary, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(NEW.moat, '')), 'B') ||
    setweight(to_tsvector('english', coalesce(array_to_string(NEW.attributes, ' '), '')), 'C') ||
    setweight(to_tsvector('english', coalesce(array_to_string(NEW.target_concerns, ' '), '')), 'C') ||
    setweight(to_tsvector('english', coalesce(NEW.category, '')), 'D');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for auto-updating search vector
DROP TRIGGER IF EXISTS products_search_vector_trigger ON products;
CREATE TRIGGER products_search_vector_trigger
  BEFORE INSERT OR UPDATE ON products
  FOR EACH ROW
  EXECUTE FUNCTION products_search_vector_update();

-- Update existing products with search vectors
UPDATE products SET search_vector = 
  setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
  setweight(to_tsvector('english', coalesce(brand, '')), 'B') ||
  setweight(to_tsvector('english', coalesce(summary, '')), 'B') ||
  setweight(to_tsvector('english', coalesce(moat, '')), 'C') ||
  setweight(to_tsvector('english', coalesce(array_to_string(attributes, ' '), '')), 'C') ||
  setweight(to_tsvector('english', coalesce(array_to_string(target_concerns, ' '), '')), 'C') ||
  setweight(to_tsvector('english', coalesce(category, '')), 'D')
WHERE search_vector IS NULL;

-- Index for vector similarity search (cosine distance)
CREATE INDEX IF NOT EXISTS idx_products_embedding ON products 
USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);

-- Index for full-text search
CREATE INDEX IF NOT EXISTS idx_products_search_vector ON products 
USING GIN (search_vector);

-- ═══════════════════════════════════════════════════════════════
-- HYBRID SEARCH FUNCTION
-- Combines semantic (vector) + keyword (text) search
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION hybrid_product_search(
  query_embedding vector(1536),
  query_text text,
  match_count int DEFAULT 10,
  semantic_weight float DEFAULT 0.7
)
RETURNS TABLE (
  id uuid,
  name text,
  brand text,
  category text,
  price decimal,
  summary text,
  image_url text,
  buy_link text,
  attributes text[],
  target_concerns text[],
  similarity float
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.name,
    p.brand,
    p.category,
    p.price,
    p.summary,
    p.image_url,
    p.buy_link,
    p.attributes,
    p.target_concerns,
    (
      -- Semantic similarity (cosine)
      CASE 
        WHEN p.embedding IS NOT NULL THEN
          semantic_weight * (1 - (p.embedding <=> query_embedding))
        ELSE 0
      END
      +
      -- Text relevance (ts_rank)
      CASE 
        WHEN query_text != '' AND p.search_vector IS NOT NULL THEN
          (1 - semantic_weight) * ts_rank(p.search_vector, plainto_tsquery('english', query_text))
        ELSE 0
      END
    )::float AS similarity
  FROM products p
  WHERE 
    p.embedding IS NOT NULL 
    OR (query_text != '' AND p.search_vector @@ plainto_tsquery('english', query_text))
  ORDER BY similarity DESC
  LIMIT match_count;
END;
$$ LANGUAGE plpgsql;

-- Simple semantic search function
CREATE OR REPLACE FUNCTION semantic_product_search(
  query_embedding vector(1536),
  match_count int DEFAULT 10,
  match_threshold float DEFAULT 0.5
)
RETURNS TABLE (
  id uuid,
  name text,
  brand text,
  category text,
  price decimal,
  summary text,
  image_url text,
  similarity float
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.name,
    p.brand,
    p.category,
    p.price,
    p.summary,
    p.image_url,
    (1 - (p.embedding <=> query_embedding))::float AS similarity
  FROM products p
  WHERE p.embedding IS NOT NULL
    AND (1 - (p.embedding <=> query_embedding)) > match_threshold
  ORDER BY p.embedding <=> query_embedding
  LIMIT match_count;
END;
$$ LANGUAGE plpgsql;





