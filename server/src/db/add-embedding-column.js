// Add embedding column via Supabase Management API
const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = 'https://ukhxwxmqjltfjugizbku.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVraHh3eG1xamx0Zmp1Z2l6Ymt1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk1NDA2NTUsImV4cCI6MjA4NTExNjY1NX0.x8sfd80Hmb6_wLtBG0Up9OqQZ49wjrhTE_wfdkVnPk4';

const supabase = createClient(supabaseUrl, supabaseKey);

async function addEmbeddingSupport() {
  console.log('🔧 Adding embedding support via RPC...\n');

  // First, let's try to add a simple text column to store embeddings as JSON
  // (pgvector requires direct SQL, but we can store as text/jsonb for now)
  
  // Check if column exists by trying to select it
  const { data, error } = await supabase
    .from('products')
    .select('id')
    .limit(1);

  if (error) {
    console.error('❌ Cannot access products table:', error.message);
    return;
  }

  console.log('✅ Products table accessible');
  console.log('\n📋 To add vector embeddings, run this SQL in Supabase Dashboard:');
  console.log('─'.repeat(60));
  console.log(`
CREATE EXTENSION IF NOT EXISTS vector;

ALTER TABLE products 
ADD COLUMN IF NOT EXISTS embedding vector(1536);

ALTER TABLE products
ADD COLUMN IF NOT EXISTS search_vector tsvector;

-- Update search vectors
UPDATE products SET search_vector = 
  setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
  setweight(to_tsvector('english', coalesce(brand, '')), 'B') ||
  setweight(to_tsvector('english', coalesce(summary, '')), 'B');

CREATE INDEX IF NOT EXISTS idx_products_search_vector ON products USING GIN (search_vector);
  `);
  console.log('─'.repeat(60));
  
  // Alternative: Store embeddings as JSONB (works without pgvector)
  console.log('\n🔄 Alternatively, adding embedding_json column for compatibility...');
  
  // Try to add via raw insert/update (this won't work for schema changes)
  // We need to use the Dashboard or direct SQL connection
  
  console.log('\n⚠️ Schema changes require Supabase Dashboard SQL Editor');
  console.log('   Go to: https://supabase.com/dashboard/project/ukhxwxmqjltfjugizbku/sql');
}

addEmbeddingSupport();





