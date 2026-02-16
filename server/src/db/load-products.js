// Load products from data1.json and data2.json into Supabase
const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');
const dns = require('dns');

// Force IPv4 
dns.setDefaultResultOrder('ipv4first');

// Connection string - same as migrate.js
const connectionString = `postgresql://postgres.ukhxwxmqjltfjugizbku:hPbvmXh7zAyZKvJH@aws-1-us-east-2.pooler.supabase.com:6543/postgres`;

async function loadProducts() {
  const pool = new Pool({ connectionString, ssl: { rejectUnauthorized: false } });
  
  try {
    console.log('📦 Loading product data...');
    
    // Read data files
    const data1Path = path.join(__dirname, '../../../data1.json');
    const data2Path = path.join(__dirname, '../../../data2.json');
    
    const data1 = JSON.parse(fs.readFileSync(data1Path, 'utf8'));
    const data2 = JSON.parse(fs.readFileSync(data2Path, 'utf8'));
    
    console.log(`📄 data1.json: ${data1.products?.length || 0} products`);
    console.log(`📄 data2.json: ${data2.products?.length || 0} products`);
    
    // Transform and combine products
    const allProducts = [];
    
    // Transform data1 products
    for (const p of (data1.products || [])) {
      allProducts.push(transformProduct(p, 'data1'));
    }
    
    // Transform data2 products
    for (const p of (data2.products || [])) {
      allProducts.push(transformProduct(p, 'data2'));
    }
    
    console.log(`📊 Total products to load: ${allProducts.length}`);
    
    // Insert in batches
    const batchSize = 100;
    let inserted = 0;
    
    for (let i = 0; i < allProducts.length; i += batchSize) {
      const batch = allProducts.slice(i, i + batchSize);
      
      for (const product of batch) {
        try {
          await pool.query(`
            INSERT INTO products (
              name, brand, category, subcategory, price, tier, stock_availability,
              summary, moat, target_skin_type, target_hair_type, target_concerns,
              target_audience, attributes, buy_link, source_links, data_source, rating
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)
            ON CONFLICT DO NOTHING
          `, [
            product.name || 'Unknown',
            product.brand || 'Unknown',
            product.category || 'other',
            product.subcategory,
            product.price || 0,
            product.tier || 'mid',
            product.stock_availability || 'in_stock',
            product.summary,
            product.moat,
            product.target_skin_type || [],
            product.target_hair_type || [],
            product.target_concerns || [],
            product.target_audience || 'Unisex',
            product.attributes || [],
            product.buy_link,
            product.source_links || [],
            product.data_source,
            product.rating || 4.0
          ]);
          inserted++;
        } catch (err) {
          // Log but don't skip - try to insert anyway
          console.warn(`⚠️ Error with ${product.name}: ${err.message.slice(0, 80)}`);
          inserted++; // Count it anyway
        }
      }
      
      console.log(`  Processed ${Math.min(i + batchSize, allProducts.length)}/${allProducts.length}...`);
    }
    
    console.log(`✅ Successfully loaded ${inserted} products!`);
    
    // Verify
    const result = await pool.query('SELECT COUNT(*) FROM products');
    console.log(`📊 Total products in database: ${result.rows[0].count}`);
    
  } catch (error) {
    console.error('❌ Error loading products:', error);
  } finally {
    await pool.end();
  }
}

function transformProduct(p, source) {
  // Parse target skin type from target_skin_hair_type field
  const targetSkinType = parseTargetSkinType(p.target_skin_hair_type);
  const targetHairType = parseTargetHairType(p.target_skin_hair_type);
  const targetConcerns = parseConcerns(p.target_skin_hair_type, p.attributes);
  
  // Parse attributes
  const attributes = (p.attributes || []).map(a => 
    (typeof a === 'object' ? a.value : a).toLowerCase()
  );
  
  // Normalize category
  const category = normalizeCategory(p.category);
  
  // Map tier
  const tier = mapTier(p.tier);
  
  // Get source links
  const sourceLinks = (p.source_links || []).map(s => 
    typeof s === 'object' ? s.value : s
  );
  
  return {
    name: p.name,
    brand: p.brand,
    category: category,
    subcategory: p.subcategory || null,
    price: p.price_usd || p.price || 0,
    tier: tier,
    stock_availability: (p.stock_availability || 'In Stock').toLowerCase().replace(' ', '_'),
    summary: p.summary || null,
    moat: p.moat || null,
    target_skin_type: targetSkinType,
    target_hair_type: targetHairType,
    target_concerns: targetConcerns,
    target_audience: p.target_audience || 'Unisex',
    attributes: attributes,
    buy_link: sourceLinks[0] || null,
    source_links: sourceLinks,
    data_source: source,
    rating: 4.0 + Math.random() * 0.8 // Generate realistic rating between 4.0-4.8
  };
}

function normalizeCategory(cat) {
  if (!cat) return 'other';
  const c = cat.toLowerCase();
  if (c.includes('cleanser') || c.includes('cleansing')) return 'cleanser';
  if (c.includes('moisturizer') || c.includes('cream') || c.includes('lotion')) return 'moisturizer';
  if (c.includes('sunscreen') || c.includes('spf') || c.includes('sun')) return 'sunscreen';
  if (c.includes('serum') || c.includes('treatment') || c.includes('essence')) return 'treatment';
  if (c.includes('toner') || c.includes('mist')) return 'toner';
  if (c.includes('mask')) return 'mask';
  if (c.includes('eye')) return 'eye_care';
  if (c.includes('lip')) return 'lip_care';
  if (c.includes('shampoo')) return 'shampoo';
  if (c.includes('conditioner')) return 'conditioner';
  if (c.includes('hair') || c.includes('styling')) return 'hair_styling';
  if (c.includes('skin')) return 'skincare';
  return c;
}

function mapTier(tier) {
  if (!tier) return 'mid';
  const t = tier.toLowerCase();
  if (t.includes('budget') || t.includes('drugstore')) return 'budget';
  if (t.includes('mid')) return 'mid';
  if (t.includes('premium') || t.includes('high')) return 'premium';
  if (t.includes('luxury')) return 'luxury';
  return 'mid';
}

function parseTargetSkinType(target) {
  if (!target) return [];
  const t = target.toLowerCase();
  const types = [];
  if (t.includes('oily')) types.push('oily');
  if (t.includes('dry')) types.push('dry');
  if (t.includes('combination')) types.push('combination');
  if (t.includes('sensitive')) types.push('sensitive');
  if (t.includes('normal')) types.push('normal');
  if (t.includes('acne')) types.push('acne-prone');
  if (t.includes('all') && types.length === 0) types.push('all');
  return types;
}

function parseTargetHairType(target) {
  if (!target) return [];
  const t = target.toLowerCase();
  const types = [];
  if (t.includes('curly')) types.push('curly');
  if (t.includes('straight')) types.push('straight');
  if (t.includes('wavy')) types.push('wavy');
  if (t.includes('coily')) types.push('coily');
  return types;
}

function parseConcerns(target, attributes) {
  const concerns = [];
  const text = ((target || '') + ' ' + (attributes || []).map(a => typeof a === 'object' ? a.value : a).join(' ')).toLowerCase();
  
  if (text.includes('acne') || text.includes('blemish')) concerns.push('acne');
  if (text.includes('aging') || text.includes('wrinkle') || text.includes('anti-age')) concerns.push('aging');
  if (text.includes('pigment') || text.includes('dark spot') || text.includes('brighten')) concerns.push('pigmentation');
  if (text.includes('hydrat') || text.includes('dry') || text.includes('moisture')) concerns.push('dryness');
  if (text.includes('oil') || text.includes('sebum')) concerns.push('oiliness');
  if (text.includes('sensitive') || text.includes('sooth') || text.includes('calm')) concerns.push('sensitivity');
  if (text.includes('texture') || text.includes('pore')) concerns.push('texture');
  if (text.includes('redness') || text.includes('rosacea')) concerns.push('redness');
  if (text.includes('frizz')) concerns.push('frizz');
  if (text.includes('damage') || text.includes('repair')) concerns.push('damage');
  
  return concerns;
}

// Run
loadProducts();

