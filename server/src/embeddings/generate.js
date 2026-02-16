/**
 * Generate embeddings for products using OpenAI
 * Run: OPENAI_API_KEY=xxx node src/embeddings/generate.js
 */

const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = 'https://ukhxwxmqjltfjugizbku.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVraHh3eG1xamx0Zmp1Z2l6Ymt1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk1NDA2NTUsImV4cCI6MjA4NTExNjY1NX0.x8sfd80Hmb6_wLtBG0Up9OqQZ49wjrhTE_wfdkVnPk4';

const supabase = createClient(supabaseUrl, supabaseKey);

const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const BATCH_SIZE = 20;

async function generateEmbedding(text) {
  const response = await fetch('https://api.openai.com/v1/embeddings', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${OPENAI_API_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      model: 'text-embedding-3-small',
      input: text
    })
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`OpenAI API error: ${error}`);
  }

  const data = await response.json();
  return data.data[0].embedding;
}

function createProductText(product) {
  // Create rich text representation for embedding
  const parts = [
    product.name,
    `by ${product.brand}`,
    product.category,
    product.subcategory,
    product.summary,
    product.moat,
    product.target_audience,
    ...(product.attributes || []),
    ...(product.target_concerns || []).map(c => `for ${c}`),
    ...(product.target_skin_type || []).map(t => `${t} skin`),
    ...(product.target_hair_type || []).map(t => `${t} hair`),
    product.tier ? `${product.tier} tier` : null,
    product.price ? `$${product.price}` : null
  ].filter(Boolean);

  return parts.join('. ');
}

async function generateBatchEmbeddings(products) {
  const texts = products.map(createProductText);
  
  const response = await fetch('https://api.openai.com/v1/embeddings', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${OPENAI_API_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      model: 'text-embedding-3-small',
      input: texts
    })
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`OpenAI API error: ${error}`);
  }

  const data = await response.json();
  return data.data.map(d => d.embedding);
}

async function main() {
  if (!OPENAI_API_KEY) {
    console.error('❌ OPENAI_API_KEY environment variable required');
    console.log('Usage: OPENAI_API_KEY=sk-xxx node src/embeddings/generate.js');
    process.exit(1);
  }

  console.log('🧠 Generating product embeddings...\n');

  // Get products without embeddings
  const { data: products, error } = await supabase
    .from('products')
    .select('id, name, brand, category, subcategory, summary, moat, attributes, target_concerns, target_skin_type, target_hair_type, target_audience, tier, price')
    .is('embedding', null)
    .limit(500);

  if (error) {
    console.error('❌ Error fetching products:', error.message);
    process.exit(1);
  }

  console.log(`📦 Found ${products.length} products without embeddings\n`);

  if (products.length === 0) {
    console.log('✅ All products already have embeddings!');
    return;
  }

  let processed = 0;
  let errors = 0;

  // Process in batches
  for (let i = 0; i < products.length; i += BATCH_SIZE) {
    const batch = products.slice(i, i + BATCH_SIZE);
    
    try {
      const embeddings = await generateBatchEmbeddings(batch);
      
      // Update each product with its embedding
      for (let j = 0; j < batch.length; j++) {
        const { error: updateError } = await supabase
          .from('products')
          .update({ embedding: embeddings[j] })
          .eq('id', batch[j].id);

        if (updateError) {
          console.warn(`⚠️ Failed to update ${batch[j].name}: ${updateError.message}`);
          errors++;
        } else {
          processed++;
        }
      }

      process.stdout.write(`\r  Processed ${Math.min(i + BATCH_SIZE, products.length)}/${products.length}...`);
      
      // Rate limiting
      await new Promise(r => setTimeout(r, 200));
      
    } catch (err) {
      console.warn(`\n⚠️ Batch error: ${err.message}`);
      errors += batch.length;
    }
  }

  console.log(`\n\n✅ Generated embeddings for ${processed} products`);
  if (errors > 0) {
    console.log(`⚠️ ${errors} errors occurred`);
  }

  // Verify
  const { count } = await supabase
    .from('products')
    .select('*', { count: 'exact', head: true })
    .not('embedding', 'is', null);

  console.log(`\n📊 Products with embeddings: ${count}`);
}

main();





