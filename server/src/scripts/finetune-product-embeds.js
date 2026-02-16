#!/usr/bin/env node
/**
 * Fine-tune Product Embedding Behavior
 * ═══════════════════════════════════════
 * 
 * Generates focused training examples to teach the fine-tuned model
 * to ALWAYS embed products when they're fetched via tool calls.
 * 
 * This fine-tunes on top of the existing fine-tuned model:
 * ft:gpt-4o-2024-08-06:dave:glowup-skincare-v2:D65Gdpr5
 * 
 * Usage:
 *   node src/scripts/finetune-product-embeds.js
 *   npm run upload-product-embeds
 */

require('dotenv').config({ path: require('path').join(__dirname, '../../.env') });
const fs = require('fs');
const path = require('path');
const OpenAI = require('openai').default;

const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
if (!OPENAI_API_KEY) {
  console.error('❌ OPENAI_API_KEY not set');
  process.exit(1);
}

const openai = new OpenAI({ apiKey: OPENAI_API_KEY });
const BASE_MODEL = 'ft:gpt-4o-2024-08-06:dave:glowup-skincare-v2:D65Gdpr5';
const OUTPUT_FILE = path.join(__dirname, '../../..', 'product_embeds_finetune.jsonl');

// ─── Tool definitions (same as server) ───────────────────────────────
const TOOLS = [
  {
    type: 'function',
    function: {
      name: 'get_user_skin_profile',
      description: "Fetch the user's complete skin profile",
      parameters: { type: 'object', properties: {}, required: [] }
    }
  },
  {
    type: 'function',
    function: {
      name: 'search_products',
      description: 'Search the GlowUp product database',
      parameters: {
        type: 'object',
        properties: {
          query: { type: 'string', description: 'Search query' },
          category: { type: 'string', description: 'Product category' },
          skin_type: { type: 'string', description: 'Target skin type' },
          concerns: { type: 'array', items: { type: 'string' }, description: 'Target concerns' },
          max_price: { type: 'number', description: 'Max price' },
          limit: { type: 'number', description: 'Max results' }
        },
        required: ['query']
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'get_product_details',
      description: 'Get full details for a specific product',
      parameters: {
        type: 'object',
        properties: {
          product_name: { type: 'string', description: 'Product name' },
          product_id: { type: 'string', description: 'Product UUID' }
        },
        required: []
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'compare_products',
      description: 'Compare two or more products',
      parameters: {
        type: 'object',
        properties: {
          product_names: { type: 'array', items: { type: 'string' }, description: 'Product names' }
        },
        required: ['product_names']
      }
    }
  }
];

// ─── Sample products with IDs ────────────────────────────────────────
const SAMPLE_PRODUCTS = [
  {
    id: 'prod-cerave-hydrating-cleanser',
    name: 'CeraVe Hydrating Cleanser',
    brand: 'CeraVe',
    price: 15.99,
    rating: 4.7,
    category: 'cleanser',
    summary: 'Gentle, non-foaming cleanser for normal to dry skin with ceramides and hyaluronic acid',
    target_skin_type: ['normal', 'dry', 'sensitive'],
    target_concerns: ['dryness', 'sensitivity'],
    ingredients: ['ceramides', 'hyaluronic acid', 'glycerin']
  },
  {
    id: 'prod-la-roche-posay-vitamin-c',
    name: 'Pure Vitamin C Face Serum',
    brand: 'La Roche-Posay',
    price: 39.99,
    rating: 4.6,
    category: 'serum',
    summary: 'Brightening vitamin C serum with salicylic acid and neurosensine for normal to combination skin',
    target_skin_type: ['normal', 'combination'],
    target_concerns: ['dark_spots', 'dullness', 'uneven_tone'],
    ingredients: ['vitamin C', 'salicylic acid', 'neurosensine']
  },
  {
    id: 'prod-cerave-pm-moisturizer',
    name: 'PM Facial Moisturizing Lotion',
    brand: 'CeraVe',
    price: 17.99,
    rating: 4.5,
    category: 'moisturizer',
    summary: 'Lightweight oil-free moisturizer with niacinamide and ceramides',
    target_skin_type: ['normal', 'oily', 'combination'],
    target_concerns: ['oiliness', 'texture'],
    ingredients: ['niacinamide', 'ceramides', 'hyaluronic acid']
  },
  {
    id: 'prod-elta-md-sunscreen',
    name: 'UV Clear Broad-Spectrum SPF 46',
    brand: 'EltaMD',
    price: 41.00,
    rating: 4.6,
    category: 'sunscreen',
    summary: 'Lightweight mineral sunscreen ideal for acne-prone and sensitive skin',
    target_skin_type: ['sensitive', 'acne-prone', 'normal'],
    target_concerns: ['acne', 'sensitivity'],
    ingredients: ['zinc oxide', 'niacinamide', 'hyaluronic acid']
  },
  {
    id: 'prod-paula-choice-bha',
    name: '2% BHA Liquid Exfoliant',
    brand: "Paula's Choice",
    price: 34.00,
    rating: 4.5,
    category: 'treatment',
    summary: 'Leave-on exfoliant that unclogs pores and smooths skin texture',
    target_skin_type: ['oily', 'combination', 'normal'],
    target_concerns: ['acne', 'clogged_pores', 'texture'],
    ingredients: ['salicylic acid', 'green tea extract']
  }
];

// ─── User queries that should trigger product recommendations ───────
const QUERIES = [
  'Best vitamin C serum?',
  'I need a gentle cleanser for dry skin',
  'What moisturizer should I use?',
  'Recommend a sunscreen for sensitive skin',
  'Best product for acne?',
  'I want something to fade dark spots',
  'What serum works for oily skin?',
  'Need a good exfoliant',
  'Best cleanser for combination skin?',
  'Recommend a vitamin C product',
  'What\'s good for anti-aging?',
  'I need hydration help',
  'Best product for texture issues?',
  'What works for redness?',
  'Recommend something for dark circles'
];

// ─── Generate training examples ──────────────────────────────────────
function generateExample(query, products, profile = null) {
  const profileCallId = 'call_profile_' + Math.random().toString(36).substring(2, 10);
  const searchCallId = 'call_search_' + Math.random().toString(36).substring(2, 10);
  
  // Determine search query and category from user query
  let searchQuery = query.toLowerCase();
  let category = null;
  if (query.includes('cleanser')) {
    category = 'cleanser';
    searchQuery = 'gentle cleanser';
  } else if (query.includes('moisturizer')) {
    category = 'moisturizer';
    searchQuery = 'moisturizer';
  } else if (query.includes('sunscreen') || query.includes('spf')) {
    category = 'sunscreen';
    searchQuery = 'sunscreen SPF';
  } else if (query.includes('vitamin c') || query.includes('vitamin C')) {
    category = 'serum';
    searchQuery = 'vitamin C serum';
  } else if (query.includes('acne')) {
    category = 'treatment';
    searchQuery = 'acne treatment';
  } else if (query.includes('dark spot') || query.includes('brighten')) {
    category = 'serum';
    searchQuery = 'brightening serum dark spots';
  } else {
    searchQuery = query.toLowerCase();
  }
  
  // Select matching products
  const matchingProducts = products.filter(p => {
    if (category && p.category !== category) return false;
    return true;
  }).slice(0, 3);
  
  if (matchingProducts.length === 0) {
    matchingProducts.push(products[0]); // Fallback
  }
  
  // Build tool result
  const toolResult = JSON.stringify({
    count: matchingProducts.length,
    products: matchingProducts.map(p => ({
      id: p.id,
      name: p.name,
      brand: p.brand,
      price: p.price,
      category: p.category,
      summary: p.summary,
      rating: p.rating,
      target_skin_type: p.target_skin_type,
      target_concerns: p.target_concerns,
      key_ingredients: p.ingredients
    }))
  });
  
  // Build profile result
  const profileResult = profile ? JSON.stringify({
    skin_type: profile.skinType || 'normal',
    skin_concerns: profile.concerns || [],
    skin_goals: profile.goals || [],
    budget: profile.budget || 'medium'
  }) : JSON.stringify({
    skin_type: 'normal',
    skin_concerns: [],
    skin_goals: [],
    budget: 'medium'
  });
  
  // Build response with EMBEDDED products
  let response = `For your ${profile?.skinType || 'normal'} skin, here are some excellent options:\n\n`;
  
  for (const product of matchingProducts) {
    response += `**${product.name}** by *${product.brand}* — $${product.price} ⭐ ${product.rating}\n\n`;
    response += `${product.summary}\n\n`;
    response += `[[PRODUCT:${product.id}]]\n\n`;
  }
  
  if (matchingProducts.length > 1) {
    response += `These products work well together and address your concerns. Start with the first one and add others as needed.`;
  }
  
  return {
    messages: [
      { role: 'system', content: 'You are GlowUp AI. When products are returned from tool calls, ALWAYS embed them using [[PRODUCT:<id>]] right after describing each product. Never mention a product without embedding it.' },
      { role: 'user', content: query },
      {
        role: 'assistant',
        tool_calls: [
          {
            id: profileCallId,
            type: 'function',
            function: { name: 'get_user_skin_profile', arguments: '{}' }
          },
          {
            id: searchCallId,
            type: 'function',
            function: {
              name: 'search_products',
              arguments: JSON.stringify({ query: searchQuery, category, limit: 5 })
            }
          }
        ]
      },
      { role: 'tool', tool_call_id: profileCallId, content: profileResult },
      { role: 'tool', tool_call_id: searchCallId, content: toolResult },
      { role: 'assistant', content: response }
    ],
    tools: TOOLS
  };
}

// ─── Main ────────────────────────────────────────────────────────────
async function main() {
  console.log(`
╔═══════════════════════════════════════════════════════════╗
║  🎯 Product Embed Fine-tuning Dataset Generator          ║
║  Base Model: ${BASE_MODEL.substring(0, 50)}...  ║
╚═══════════════════════════════════════════════════════════╝
`);

  const examples = [];
  
  // Generate 50 examples with different queries and products
  for (let i = 0; i < 50; i++) {
    const query = QUERIES[i % QUERIES.length];
    const profile = {
      skinType: ['normal', 'oily', 'dry', 'combination', 'sensitive'][i % 5],
      concerns: [['acne'], ['dark_spots'], ['dryness'], ['texture'], ['aging']][i % 5],
      goals: [['brightening'], ['hydration'], ['anti-aging'], ['clear_skin'], ['smooth_texture']][i % 5],
      budget: ['low', 'medium', 'high'][i % 3]
    };
    
    const example = generateExample(query, SAMPLE_PRODUCTS, profile);
    examples.push(example);
    
    if ((i + 1) % 10 === 0) {
      console.log(`  Generated ${i + 1}/50 examples...`);
    }
  }
  
  // Write to JSONL
  const lines = examples.map(ex => JSON.stringify(ex));
  fs.writeFileSync(OUTPUT_FILE, lines.join('\n'));
  
  console.log(`\n✅ Generated ${examples.length} examples`);
  console.log(`📄 Saved to: ${OUTPUT_FILE}`);
  console.log(`\n📤 Next step: npm run upload-product-embeds`);
}

main().catch(err => {
  console.error('❌ Error:', err.message);
  process.exit(1);
});




