-- Create the match_products function for vector similarity search
-- This enables RAG-based product recommendations
-- Note: Uses 'summary' column instead of 'description' (actual schema)

CREATE OR REPLACE FUNCTION match_products(
  query_embedding vector(1536),
  match_threshold float DEFAULT 0.3,
  match_count int DEFAULT 10
)
RETURNS TABLE (
  id uuid,
  name text,
  brand text,
  price numeric,
  category text,
  description text,
  image_url text,
  rating numeric,
  similarity float
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id,
    p.name,
    p.brand,
    p.price,
    p.category,
    p.summary as description,
    p.image_url,
    p.rating,
    (1 - (p.embedding <=> query_embedding))::float as similarity
  FROM products p
  WHERE p.embedding IS NOT NULL
    AND (1 - (p.embedding <=> query_embedding)) > match_threshold
  ORDER BY similarity DESC
  LIMIT match_count;
END;
$$;

-- Grant execute permission to authenticated and anon roles
GRANT EXECUTE ON FUNCTION match_products(vector(1536), float, int) TO authenticated;
GRANT EXECUTE ON FUNCTION match_products(vector(1536), float, int) TO anon;

