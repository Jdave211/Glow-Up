#!/usr/bin/env node
/**
 * doc2dataset v2 — GlowUp Skincare Fine-tuning Pipeline
 * ═══════════════════════════════════════════════════════
 * Generates comprehensive OpenAI JSONL training data with:
 *   1. Multimodal inputs (image URLs + onboarding profile data)
 *   2. Tool-calling examples (search_products, get_product_details, etc.)
 *   3. Full routine generation (morning + evening)
 *   4. Best practices & lifestyle recommendations
 *   5. Diverse user profiles (skin types, tones, ages, concerns)
 *
 * Source: recommendation_training.txt (dermatology knowledge base)
 * Output: skincare_finetune.jsonl (OpenAI chat format with tools)
 */

require('dotenv').config();
const fs = require('fs');
const path = require('path');
const OpenAI = require('openai').default;

const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
if (!OPENAI_API_KEY) {
  console.error('❌ OPENAI_API_KEY not set in .env');
  process.exit(1);
}

const openai = new OpenAI({ apiKey: OPENAI_API_KEY });
const MODEL = 'gpt-4.1-mini';

// ═══════════════════════════════════════════════════════════════
// TOOL DEFINITIONS (mirrors server/src/index.ts exactly)
// ═══════════════════════════════════════════════════════════════

const TOOLS = [
  {
    type: 'function',
    function: {
      name: 'get_user_skin_profile',
      description: "Fetch the current user's complete skin profile — includes skin type, tone, goals, concerns, hair info, sunscreen usage, budget, fragrance preference, and any image analysis results. Call this whenever you need to personalize a recommendation.",
      parameters: {
        type: 'object',
        properties: {},
        required: []
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'get_user_routine',
      description: "Fetch the user's current skincare routine (morning and evening steps). Call this when the user asks about their routine or you need routine context.",
      parameters: {
        type: 'object',
        properties: {},
        required: []
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'search_products',
      description: 'Search the GlowUp product database for skincare products. Uses semantic + keyword search. Call this when recommending products or finding alternatives.',
      parameters: {
        type: 'object',
        properties: {
          query: { type: 'string', description: 'Natural language search query' },
          skin_type: { type: 'string', description: 'Filter: oily, dry, combination, sensitive, normal' },
          concern: { type: 'string', description: 'Filter: acne, aging, dark_spots, dryness, redness, texture' },
          category: { type: 'string', description: 'Filter: cleanser, moisturizer, serum, sunscreen, treatment, toner, mask, eye_cream' },
          max_results: { type: 'number', description: 'Max products to return (default 5)' }
        },
        required: ['query']
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'get_product_details',
      description: 'Get full details for a specific product by name — includes ingredients, attributes, buy link, price, rating.',
      parameters: {
        type: 'object',
        properties: {
          product_name: { type: 'string', description: 'Product name to look up' }
        },
        required: ['product_name']
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'compare_products',
      description: 'Compare two or more products side-by-side on ingredients, price, rating, and suitability.',
      parameters: {
        type: 'object',
        properties: {
          product_names: { type: 'array', items: { type: 'string' }, description: 'Product names to compare' }
        },
        required: ['product_names']
      }
    }
  }
];

// ═══════════════════════════════════════════════════════════════
// SYSTEM PROMPT (mirrors server)
// ═══════════════════════════════════════════════════════════════

const SYSTEM_PROMPT = `You are GlowUp AI, a friendly and expert skincare assistant inside the GlowUp app. You have access to the user's skin profile, their routine, and a full product database — use the tools provided to look up real data before answering.

## Behavior

- ALWAYS call get_user_skin_profile before giving personalized advice (if you haven't already in this conversation)
- When recommending products, ALWAYS call search_products to find real products from our database — never make up product names
- When the user asks about a specific product, call get_product_details to get real ingredient data
- When asked to compare products, use compare_products
- If the user asks about their routine, call get_user_routine to get the real data
- You may call multiple tools in one turn if needed

## Tone & Style

- Warm, encouraging, approachable — like a knowledgeable friend who genuinely cares
- Use emojis sparingly but naturally (✨, 💕, 🧴, 🌸)
- Evidence-based advice backed by the real products and profile data from tools
- Reference specific product names, prices, and ingredients from tool results

## Formatting (Markdown)

- Use **bold** for product names, key terms, emphasis
- Use *italic* for caveats or nuance
- Use ## headings to break up longer answers
- Use bullet points (- item) for lists
- Use numbered lists (1. 2. 3.) for ordered steps
- Keep paragraphs concise but rich

## Product Recommendations

When recommending products, present them like this:

**Product Name** by *Brand* — $XX.XX ⭐ X.X
Brief reason why it's good for this user's specific needs.`;

// ═══════════════════════════════════════════════════════════════
// ONBOARDING PROFILES — diverse user archetypes
// ═══════════════════════════════════════════════════════════════

const USER_PROFILES = [
  {
    skinType: 'oily', skinTone: 0.4, skinToneLabel: 'Medium warm', ageGroup: '18-25',
    concerns: ['acne', 'oiliness'], skinGoals: ['clear_skin', 'glass_skin'],
    hairType: 'straight', washFrequency: '2_3_weekly', sunscreenUsage: 'sometimes',
    budget: 'medium', fragranceFree: false,
    imageDescription: 'forehead acne, oily T-zone shine, some dark spots on cheeks'
  },
  {
    skinType: 'dry', skinTone: 0.2, skinToneLabel: 'Light neutral', ageGroup: '30-40',
    concerns: ['dryness', 'aging'], skinGoals: ['glass_skin', 'brightening'],
    hairType: 'wavy', washFrequency: '2_3_weekly', sunscreenUsage: 'daily',
    budget: 'high', fragranceFree: true,
    imageDescription: 'flaky patches on cheeks, dull texture, fine lines around eyes'
  },
  {
    skinType: 'sensitive', skinTone: 0.15, skinToneLabel: 'Light cool', ageGroup: '25-35',
    concerns: ['redness', 'sensitivity'], skinGoals: ['clear_skin'],
    hairType: 'curly', washFrequency: 'weekly', sunscreenUsage: 'daily',
    budget: 'medium', fragranceFree: true,
    imageDescription: 'redness on cheeks, visible capillaries, slight bumps'
  },
  {
    skinType: 'normal', skinTone: 0.25, skinToneLabel: 'Light warm', ageGroup: '45-55',
    concerns: ['aging', 'dark_spots'], skinGoals: ['brightening'],
    hairType: 'straight', washFrequency: 'daily', sunscreenUsage: 'daily',
    budget: 'high', fragranceFree: false,
    imageDescription: "crow's feet, forehead wrinkles, sun spots on temples"
  },
  {
    skinType: 'combination', skinTone: 0.6, skinToneLabel: 'Medium neutral', ageGroup: '20-30',
    concerns: ['acne', 'dark_spots', 'texture'], skinGoals: ['clear_skin', 'glass_skin'],
    hairType: 'coily', washFrequency: 'weekly', sunscreenUsage: 'rarely',
    budget: 'low', fragranceFree: false,
    imageDescription: 'acne scars on cheeks, uneven skin surface, oily T-zone with dry patches'
  },
  {
    skinType: 'oily', skinTone: 0.7, skinToneLabel: 'Deep warm', ageGroup: '18-25',
    concerns: ['acne', 'pigmentation', 'oiliness'], skinGoals: ['clear_skin', 'brightening'],
    hairType: 'coily', washFrequency: 'weekly', sunscreenUsage: 'sometimes',
    budget: 'low', fragranceFree: false,
    imageDescription: 'cystic acne on jawline, dark hyperpigmentation marks, enlarged pores on nose'
  },
  {
    skinType: 'dry', skinTone: 0.5, skinToneLabel: 'Medium olive', ageGroup: '35-45',
    concerns: ['dryness', 'aging', 'dark_spots'], skinGoals: ['glass_skin', 'brightening'],
    hairType: 'wavy', washFrequency: '2_3_weekly', sunscreenUsage: 'sometimes',
    budget: 'medium', fragranceFree: true,
    imageDescription: 'dry patches around nose, melasma on upper lip and forehead, early wrinkles'
  },
  {
    skinType: 'normal', skinTone: 0.3, skinToneLabel: 'Light neutral', ageGroup: '20-30',
    concerns: ['dryness'], skinGoals: ['glass_skin'],
    hairType: 'straight', washFrequency: 'daily', sunscreenUsage: 'daily',
    budget: 'medium', fragranceFree: false,
    imageDescription: 'generally clear skin, mild dullness, slight dehydration lines'
  },
  {
    skinType: 'combination', skinTone: 0.8, skinToneLabel: 'Deep cool', ageGroup: '25-35',
    concerns: ['pigmentation', 'texture', 'oiliness'], skinGoals: ['brightening', 'clear_skin'],
    hairType: 'curly', washFrequency: '2_3_weekly', sunscreenUsage: 'rarely',
    budget: 'medium', fragranceFree: false,
    imageDescription: 'uneven skin tone, post-acne marks, textured areas on forehead, oily nose'
  },
  {
    skinType: 'sensitive', skinTone: 0.35, skinToneLabel: 'Medium cool', ageGroup: '30-40',
    concerns: ['redness', 'dryness', 'sensitivity'], skinGoals: ['clear_skin'],
    hairType: 'wavy', washFrequency: '2_3_weekly', sunscreenUsage: 'daily',
    budget: 'high', fragranceFree: true,
    imageDescription: 'eczema patches on cheeks, general redness, reactive skin with dry flakes'
  },
  {
    skinType: 'oily', skinTone: 0.45, skinToneLabel: 'Medium warm', ageGroup: '16-20',
    concerns: ['acne', 'oiliness'], skinGoals: ['clear_skin'],
    hairType: 'straight', washFrequency: 'daily', sunscreenUsage: 'rarely',
    budget: 'low', fragranceFree: false,
    imageDescription: 'teenage acne on forehead and chin, blackheads on nose, very shiny skin'
  },
  {
    skinType: 'normal', skinTone: 0.55, skinToneLabel: 'Medium neutral', ageGroup: '50-60',
    concerns: ['aging', 'dark_spots', 'dryness'], skinGoals: ['brightening'],
    hairType: 'straight', washFrequency: '2_3_weekly', sunscreenUsage: 'daily',
    budget: 'high', fragranceFree: false,
    imageDescription: 'deep wrinkles on forehead, sagging jawline, prominent age spots, thinning skin'
  }
];

// ═══════════════════════════════════════════════════════════════
// USER QUERY TEMPLATES — diverse question types
// ═══════════════════════════════════════════════════════════════

const QUERY_TEMPLATES = {
  routine_request: [
    "Build me a complete skincare routine based on my profile and photos.",
    "What should my morning and evening skincare routine look like?",
    "I just finished onboarding — can you create my personalized routine?",
    "Based on my skin analysis, what products should I use daily?",
    "Set up my full skincare routine please!",
  ],
  product_recommendation: [
    "What cleanser should I use for my skin type?",
    "Recommend a good moisturizer for me.",
    "What sunscreen would work best for my skin?",
    "I need a serum for my concerns — what do you suggest?",
    "What's the best acne treatment product for me?",
    "Can you find me a good retinol product?",
    "I need an affordable option for dark spots.",
    "What eye cream should I use?",
  ],
  compare: [
    "Compare CeraVe and La Roche-Posay moisturizers for me.",
    "Which is better for oily skin — niacinamide or salicylic acid serums?",
    "Should I get the $15 or $30 sunscreen?",
  ],
  best_practices: [
    "What are the best practices for my skin type?",
    "How should I layer my skincare products?",
    "What ingredients should I avoid with my concerns?",
    "When should I apply retinol vs vitamin C?",
    "How often should I exfoliate?",
  ],
  lifestyle: [
    "What lifestyle changes will help my skin?",
    "What foods are good for acne-prone skin?",
    "How does sleep affect my skin?",
    "Will drinking more water help my dryness?",
  ],
  specific_concern: [
    "How do I get rid of these dark spots?",
    "My acne keeps coming back — what should I do differently?",
    "How can I reduce the redness on my cheeks?",
    "What can I do about these fine lines?",
    "My skin barrier feels damaged — help!",
    "I have hormonal acne on my jawline. What works?",
  ],
  edge_cases: [
    "I'm pregnant — what skincare is safe?",
    "I'm on a $20/month budget. What routine can I build?",
    "I've been using the same routine for months with no results. What now?",
    "I just started retinol and my skin is peeling — is that normal?",
    "Can I use vitamin C and niacinamide together?",
  ]
};

// ═══════════════════════════════════════════════════════════════
// SIMULATED TOOL RESULTS (realistic product data)
// ═══════════════════════════════════════════════════════════════

const SAMPLE_PRODUCTS = {
  cleanser_oily: [
    { name: 'CeraVe Acne Foaming Cream Cleanser', brand: 'CeraVe', price: 17.99, rating: 4.3, ingredients: ['benzoyl peroxide', 'ceramides', 'hyaluronic acid'], summary: 'Medicated foaming cleanser with 4% benzoyl peroxide for acne-prone skin' },
    { name: 'CeraVe Renewing SA Cleanser', brand: 'CeraVe', price: 15.99, rating: 4.2, ingredients: ['salicylic acid', 'ceramides', 'niacinamide'], summary: 'Exfoliating cleanser with salicylic acid for oily/acne skin' },
    { name: 'La Roche-Posay Effaclar Purifying Foaming Gel', brand: 'La Roche-Posay', price: 14.99, rating: 4.4, ingredients: ['zinc pidolate', 'glycerin'], summary: 'Oil-free foaming gel cleanser for oily sensitive skin' },
  ],
  cleanser_dry: [
    { name: 'CeraVe Hydrating Cream-to-Foam Cleanser', brand: 'CeraVe', price: 16.49, rating: 4.5, ingredients: ['ceramides', 'hyaluronic acid', 'amino acids'], summary: 'Gentle cream-to-foam cleanser that hydrates while cleansing' },
    { name: 'La Roche-Posay Toleriane Hydrating Gentle Cleanser', brand: 'La Roche-Posay', price: 15.99, rating: 4.6, ingredients: ['ceramide-3', 'niacinamide', 'glycerin'], summary: 'Ultra-gentle hydrating cleanser for dry sensitive skin' },
  ],
  cleanser_sensitive: [
    { name: 'Vanicream Gentle Facial Cleanser', brand: 'Vanicream', price: 8.99, rating: 4.7, ingredients: ['glycerin'], summary: 'Free of dyes, fragrance, and common irritants. For sensitive skin.' },
    { name: 'La Roche-Posay Toleriane Hydrating Gentle Cleanser', brand: 'La Roche-Posay', price: 15.99, rating: 4.6, ingredients: ['ceramide-3', 'niacinamide', 'glycerin'], summary: 'Ultra-gentle hydrating cleanser' },
  ],
  moisturizer_oily: [
    { name: 'CeraVe PM Facial Moisturizing Lotion', brand: 'CeraVe', price: 17.99, rating: 4.5, ingredients: ['niacinamide', 'ceramides', 'hyaluronic acid'], summary: 'Lightweight oil-free moisturizer with niacinamide' },
    { name: 'Neutrogena Hydro Boost Water Gel', brand: 'Neutrogena', price: 19.99, rating: 4.3, ingredients: ['hyaluronic acid', 'glycerin'], summary: 'Oil-free water gel moisturizer' },
  ],
  moisturizer_dry: [
    { name: 'CeraVe Moisturizing Cream', brand: 'CeraVe', price: 18.99, rating: 4.7, ingredients: ['ceramides', 'hyaluronic acid', 'petrolatum'], summary: 'Rich moisturizing cream with 3 essential ceramides for dry skin' },
    { name: 'La Roche-Posay Cicaplast Baume B5+', brand: 'La Roche-Posay', price: 16.99, rating: 4.6, ingredients: ['panthenol', 'madecassoside', 'shea butter'], summary: 'Soothing multi-purpose balm for dry/irritated skin' },
  ],
  sunscreen: [
    { name: 'EltaMD UV Clear Broad-Spectrum SPF 46', brand: 'EltaMD', price: 41.00, rating: 4.6, ingredients: ['zinc oxide', 'niacinamide', 'hyaluronic acid'], summary: 'Lightweight mineral sunscreen ideal for acne-prone and sensitive skin' },
    { name: 'La Roche-Posay Anthelios Melt-in Milk SPF 60', brand: 'La Roche-Posay', price: 35.99, rating: 4.5, ingredients: ['avobenzone', 'homosalate'], summary: 'High-protection water-resistant sunscreen' },
    { name: 'CeraVe Hydrating Mineral Sunscreen SPF 30', brand: 'CeraVe', price: 15.99, rating: 4.1, ingredients: ['zinc oxide', 'titanium dioxide', 'ceramides'], summary: 'Mineral sunscreen with ceramides for sensitive skin' },
  ],
  serum_acne: [
    { name: 'Paula\'s Choice 2% BHA Liquid Exfoliant', brand: "Paula's Choice", price: 34.00, rating: 4.5, ingredients: ['salicylic acid', 'green tea extract'], summary: 'Leave-on exfoliant that unclogs pores and smooths skin' },
    { name: 'The Ordinary Niacinamide 10% + Zinc 1%', brand: 'The Ordinary', price: 5.90, rating: 4.2, ingredients: ['niacinamide', 'zinc PCA'], summary: 'Oil control and pore-minimizing serum' },
  ],
  serum_brightening: [
    { name: 'TruSkin Vitamin C Serum', brand: 'TruSkin', price: 19.99, rating: 4.3, ingredients: ['vitamin C', 'vitamin E', 'hyaluronic acid'], summary: 'Brightening vitamin C serum for dark spots and radiance' },
    { name: 'The Ordinary Alpha Arbutin 2% + HA', brand: 'The Ordinary', price: 8.90, rating: 4.3, ingredients: ['alpha arbutin', 'hyaluronic acid'], summary: 'Targets dark spots and uneven skin tone' },
  ],
  serum_antiaging: [
    { name: 'The Ordinary Retinol 0.5% in Squalane', brand: 'The Ordinary', price: 5.80, rating: 4.1, ingredients: ['retinol', 'squalane'], summary: 'Moderate-strength retinol for fine lines and texture' },
    { name: 'CeraVe Skin Renewing Retinol Serum', brand: 'CeraVe', price: 18.99, rating: 4.2, ingredients: ['retinol', 'ceramides', 'niacinamide'], summary: 'Encapsulated retinol serum for anti-aging' },
  ],
  treatment_redness: [
    { name: 'The Ordinary Azelaic Acid Suspension 10%', brand: 'The Ordinary', price: 7.90, rating: 4.1, ingredients: ['azelaic acid'], summary: 'Brightening cream-gel that targets redness and uneven tone' },
    { name: 'La Roche-Posay Rosaliac AR Intense', brand: 'La Roche-Posay', price: 38.99, rating: 4.3, ingredients: ['ambophenol', 'neurosensine'], summary: 'Visible redness-reducing serum' },
  ],
  eye_cream: [
    { name: 'CeraVe Eye Repair Cream', brand: 'CeraVe', price: 15.97, rating: 4.2, ingredients: ['ceramides', 'hyaluronic acid', 'niacinamide'], summary: 'Under-eye cream for dark circles and puffiness' },
  ]
};

// ═══════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════════════

function randomFrom(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function formatProfileForUser(profile) {
  return `My skin analysis from onboarding:
- Skin type: ${profile.skinType}
- Skin tone: ${profile.skinToneLabel} (${profile.skinTone})
- Age group: ${profile.ageGroup}
- Concerns: ${profile.concerns.join(', ')}
- Skin goals: ${profile.skinGoals.join(', ')}
- Sunscreen usage: ${profile.sunscreenUsage}
- Hair type: ${profile.hairType}
- Wash frequency: ${profile.washFrequency}
- Budget: ${profile.budget}
- Fragrance-free: ${profile.fragranceFree ? 'yes' : 'no'}
- Visible in photos: ${profile.imageDescription}`;
}

function formatProfileForToolResult(profile) {
  return JSON.stringify({
    skin_type: profile.skinType,
    skin_tone: profile.skinTone,
    skin_tone_label: profile.skinToneLabel,
    age_group: profile.ageGroup,
    skin_concerns: profile.concerns,
    skin_goals: profile.skinGoals,
    sunscreen_usage: profile.sunscreenUsage,
    hair_type: profile.hairType,
    wash_frequency: profile.washFrequency,
    budget: profile.budget,
    fragrance_free: profile.fragranceFree,
    photo_analysis: profile.imageDescription
  });
}

// Helper: Add deterministic IDs to products (for embedding)
function addProductIds(products) {
  return products.map(p => ({
    ...p,
    id: p.id || `prod-${Buffer.from(`${p.brand}-${p.name}`).toString('base64').substring(0, 8).replace(/[^a-z0-9]/gi, '')}`
  }));
}

function getProductsForProfile(profile) {
  const products = {};
  // Cleanser
  if (['oily', 'combination'].includes(profile.skinType)) products.cleanser = addProductIds(SAMPLE_PRODUCTS.cleanser_oily);
  else if (profile.skinType === 'sensitive') products.cleanser = addProductIds(SAMPLE_PRODUCTS.cleanser_sensitive);
  else products.cleanser = addProductIds(SAMPLE_PRODUCTS.cleanser_dry);
  // Moisturizer
  if (['oily', 'combination'].includes(profile.skinType)) products.moisturizer = addProductIds(SAMPLE_PRODUCTS.moisturizer_oily);
  else products.moisturizer = addProductIds(SAMPLE_PRODUCTS.moisturizer_dry);
  // Sunscreen
  products.sunscreen = addProductIds(SAMPLE_PRODUCTS.sunscreen);
  // Serums based on concerns
  if (profile.concerns.includes('acne') || profile.concerns.includes('oiliness')) {
    products.treatment = addProductIds(SAMPLE_PRODUCTS.serum_acne);
  }
  if (profile.concerns.includes('dark_spots') || profile.concerns.includes('pigmentation') || profile.skinGoals.includes('brightening')) {
    products.brightening = addProductIds(SAMPLE_PRODUCTS.serum_brightening);
  }
  if (profile.concerns.includes('aging')) {
    products.antiaging = addProductIds(SAMPLE_PRODUCTS.serum_antiaging);
  }
  if (profile.concerns.includes('redness') || profile.concerns.includes('sensitivity')) {
    products.redness = addProductIds(SAMPLE_PRODUCTS.treatment_redness);
  }
  return products;
}

function makeToolCallId() {
  return 'call_' + Math.random().toString(36).substring(2, 12);
}

// ═══════════════════════════════════════════════════════════════
// EXAMPLE GENERATORS
// ═══════════════════════════════════════════════════════════════

/**
 * Generate a full routine request example with tool calls
 * User provides onboarding data + photo description → 
 * Model calls get_user_skin_profile + search_products → 
 * Model returns full morning + evening routine with real products
 */
async function generateRoutineExample(profile) {
  const query = randomFrom(QUERY_TEMPLATES.routine_request);
  const userMessage = `${query}\n\n${formatProfileForUser(profile)}`;
  const profileResult = formatProfileForToolResult(profile);
  const products = getProductsForProfile(profile);
  
  // Simulate the tool-calling flow
  const profileCallId = makeToolCallId();
  const cleanserCallId = makeToolCallId();
  const moisturizerCallId = makeToolCallId();
  const sunscreenCallId = makeToolCallId();
  const treatmentCallId = makeToolCallId();
  
  // Build tool call sequence
  const toolCalls = [
    { id: profileCallId, type: 'function', function: { name: 'get_user_skin_profile', arguments: '{}' } },
  ];
  
  // Add product searches based on profile
  const searchCalls = [];
  
  searchCalls.push({
    id: cleanserCallId,
    type: 'function',
    function: {
      name: 'search_products',
      arguments: JSON.stringify({ query: `gentle cleanser for ${profile.skinType} skin`, skin_type: profile.skinType, category: 'cleanser', max_results: 3 })
    }
  });
  searchCalls.push({
    id: moisturizerCallId,
    type: 'function',
    function: {
      name: 'search_products',
      arguments: JSON.stringify({ query: `moisturizer for ${profile.skinType} skin`, skin_type: profile.skinType, category: 'moisturizer', max_results: 3 })
    }
  });
  searchCalls.push({
    id: sunscreenCallId,
    type: 'function',
    function: {
      name: 'search_products',
      arguments: JSON.stringify({ query: 'broad spectrum sunscreen SPF 30+', category: 'sunscreen', max_results: 3 })
    }
  });
  
  // Treatment search based on concerns
  const primaryConcern = profile.concerns[0];
  searchCalls.push({
    id: treatmentCallId,
    type: 'function',
    function: {
      name: 'search_products',
      arguments: JSON.stringify({ query: `${primaryConcern} treatment serum`, concern: primaryConcern, category: 'serum', max_results: 3 })
    }
  });

  // Tool results
  const toolResults = [
    { role: 'tool', tool_call_id: profileCallId, content: profileResult },
    { role: 'tool', tool_call_id: cleanserCallId, content: JSON.stringify({ products: products.cleanser || SAMPLE_PRODUCTS.cleanser_oily }) },
    { role: 'tool', tool_call_id: moisturizerCallId, content: JSON.stringify({ products: products.moisturizer || SAMPLE_PRODUCTS.moisturizer_oily }) },
    { role: 'tool', tool_call_id: sunscreenCallId, content: JSON.stringify({ products: products.sunscreen }) },
    { role: 'tool', tool_call_id: treatmentCallId, content: JSON.stringify({ products: Object.values(products).flat().slice(0, 3) }) },
  ];

  // Use LLM to generate the final response
  const finalResponse = await openai.chat.completions.create({
    model: MODEL,
    messages: [
      { role: 'system', content: `You are generating a training example for GlowUp AI. Given the user's onboarding profile and the product search results below, write a complete, personalized skincare routine response.

## REQUIREMENTS:
- Include a brief skin analysis based on their photo description and profile
- Create a full **Morning Routine** (numbered steps with specific products from the search results)
- Create a full **Evening Routine** (numbered steps with specific products)
- Include product names, brands, prices, and ratings from the search results
- Add 3-4 **Lifestyle Tips** specific to their concerns
- End with a motivating **Goal Alignment** statement connecting the routine to their goals
- Use markdown formatting: ## headings, **bold** product names, numbered lists, bullet points
- Be warm, encouraging, personalized — reference their specific skin type, concerns, and goals
- Ensure proper spacing (blank lines before/after headings, lists, etc.)

PROFILE DATA:
${profileResult}

PRODUCT RESULTS:
Cleansers: ${JSON.stringify(products.cleanser || [])}
Moisturizers: ${JSON.stringify(products.moisturizer || [])}
Sunscreens: ${JSON.stringify(products.sunscreen)}
Treatments: ${JSON.stringify(Object.values(products).flat().slice(0, 5))}` },
      { role: 'user', content: userMessage }
    ],
    max_tokens: 1500,
    temperature: 0.7,
  });

  const responseText = finalResponse.choices[0]?.message?.content || '';
  if (!responseText || responseText.length < 100) return null;

  // Build the complete training example
  return {
    messages: [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: [
        { type: 'text', text: userMessage },
        { type: 'image_url', image_url: { url: 'https://example.com/user_skin_photo.jpg', detail: 'low' } }
      ]},
      { role: 'assistant', tool_calls: toolCalls },
      toolResults[0],
      { role: 'assistant', tool_calls: searchCalls },
      ...toolResults.slice(1),
      { role: 'assistant', content: responseText }
    ],
    tools: TOOLS
  };
}

/**
 * Generate a product recommendation example with tool calls
 */
async function generateProductRecommendationExample(profile) {
  const query = randomFrom(QUERY_TEMPLATES.product_recommendation);
  const products = getProductsForProfile(profile);
  
  const profileCallId = makeToolCallId();
  const searchCallId = makeToolCallId();
  
  // Determine what kind of product to search for based on the query
  let searchQuery, category, productResults;
  if (query.includes('cleanser')) {
    searchQuery = `cleanser for ${profile.skinType} skin`;
    category = 'cleanser';
    productResults = products.cleanser || SAMPLE_PRODUCTS.cleanser_oily;
  } else if (query.includes('moisturizer')) {
    searchQuery = `moisturizer for ${profile.skinType} skin`;
    category = 'moisturizer';
    productResults = products.moisturizer || SAMPLE_PRODUCTS.moisturizer_oily;
  } else if (query.includes('sunscreen')) {
    searchQuery = 'broad spectrum sunscreen SPF 30+';
    category = 'sunscreen';
    productResults = SAMPLE_PRODUCTS.sunscreen;
  } else if (query.includes('retinol')) {
    searchQuery = 'retinol serum anti-aging';
    category = 'serum';
    productResults = SAMPLE_PRODUCTS.serum_antiaging;
  } else if (query.includes('eye cream')) {
    searchQuery = 'eye cream dark circles';
    category = 'eye_cream';
    productResults = SAMPLE_PRODUCTS.eye_cream;
  } else {
    searchQuery = `${profile.concerns[0]} treatment for ${profile.skinType} skin`;
    category = 'serum';
    productResults = products.treatment || products.brightening || addProductIds(SAMPLE_PRODUCTS.serum_acne);
  }
  
  // Ensure all products have IDs
  productResults = addProductIds(productResults);

  const resp = await openai.chat.completions.create({
    model: MODEL,
    messages: [
      { role: 'system', content: `Generate a helpful product recommendation response for GlowUp AI. Given the user profile and products, recommend 2-3 products with clear reasoning for each. Use markdown, include prices and ratings. Be warm and personalized.

CRITICAL: After mentioning each product by name, you MUST embed it using [[PRODUCT:<product_id>]] on its own line. For example:

**CeraVe Hydrating Cleanser** by *CeraVe* — $15.99 ⭐ 4.7

[[PRODUCT:abc-123-def-456]]

PROFILE: ${formatProfileForToolResult(profile)}
PRODUCTS FOUND: ${JSON.stringify(productResults.map(p => ({ id: p.id, name: p.name, brand: p.brand })))}

Reference the user's specific skin type, concerns, and budget in your reasoning.` },
      { role: 'user', content: query }
    ],
    max_tokens: 1000,
    temperature: 0.7,
  });

  let responseText = resp.choices[0]?.message?.content || '';
  if (!responseText || responseText.length < 80) return null;

  // Post-process: Inject product embeds if model forgot
  const productMap = new Map(productResults.map(p => [p.name.toLowerCase(), p.id]));
  const embeddedIds = new Set();
  
  // Check if embeds already exist
  const hasEmbeds = /\[\[PRODUCT:[a-f0-9-]+\]\]/.test(responseText);
  
  if (!hasEmbeds && productResults.length > 0) {
    // Try to inject embeds after product mentions
    for (const product of productResults) {
      const nameLower = product.name.toLowerCase();
      const brandLower = product.brand.toLowerCase();
      
      // Look for product name or brand + name
      const patterns = [
        new RegExp(`\\b${product.name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'gi'),
        new RegExp(`\\*\\*${product.name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\*\\*`, 'gi'),
      ];
      
      for (const pattern of patterns) {
        const matches = [...responseText.matchAll(pattern)];
        if (matches.length > 0 && !embeddedIds.has(product.id)) {
          const lastMatch = matches[matches.length - 1];
          const insertPos = lastMatch.index + lastMatch[0].length;
          
          // Check if embed already nearby
          const nearby = responseText.substring(Math.max(0, insertPos - 50), Math.min(responseText.length, insertPos + 50));
          if (!nearby.includes(`[[PRODUCT:${product.id}]]`)) {
            responseText = responseText.slice(0, insertPos) + 
              `\n\n[[PRODUCT:${product.id}]]\n\n` + 
              responseText.slice(insertPos);
            embeddedIds.add(product.id);
            break;
          }
        }
      }
    }
    
    // If still no embeds, append at end
    if (embeddedIds.size === 0) {
      responseText += '\n\n' + productResults.slice(0, 3).map(p => `[[PRODUCT:${p.id}]]`).join('\n\n');
    }
  }

  return {
    messages: [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: [
        { type: 'text', text: `${query}\n\n${formatProfileForUser(profile)}` },
        { type: 'image_url', image_url: { url: 'https://example.com/user_skin_photo.jpg', detail: 'low' } }
      ]},
      { role: 'assistant', tool_calls: [
        { id: profileCallId, type: 'function', function: { name: 'get_user_skin_profile', arguments: '{}' } },
        { id: searchCallId, type: 'function', function: { name: 'search_products', arguments: JSON.stringify({ query: searchQuery, skin_type: profile.skinType, category, max_results: 5 }) } },
      ]},
      { role: 'tool', tool_call_id: profileCallId, content: formatProfileForToolResult(profile) },
      { role: 'tool', tool_call_id: searchCallId, content: JSON.stringify({ products: productResults }) },
      { role: 'assistant', content: responseText }
    ],
    tools: TOOLS
  };
}

/**
 * Generate a best-practices / lifestyle example with tool call
 */
async function generateBestPracticesExample(profile) {
  const queries = [...QUERY_TEMPLATES.best_practices, ...QUERY_TEMPLATES.lifestyle];
  const query = randomFrom(queries);
  
  const profileCallId = makeToolCallId();
  
  const resp = await openai.chat.completions.create({
    model: MODEL,
    messages: [
      { role: 'system', content: `Generate expert skincare best practices / lifestyle advice from GlowUp AI. The response should be personalized to the user's profile. Use markdown. Be thorough but friendly. Include evidence-based tips.

PROFILE: ${formatProfileForToolResult(profile)}

Give actionable, specific advice personalized to their skin type (${profile.skinType}), concerns (${profile.concerns.join(', ')}), and goals (${profile.skinGoals.join(', ')}).` },
      { role: 'user', content: query }
    ],
    max_tokens: 800,
    temperature: 0.7,
  });

  const responseText = resp.choices[0]?.message?.content || '';
  if (!responseText || responseText.length < 80) return null;

  return {
    messages: [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: query },
      { role: 'assistant', tool_calls: [
        { id: profileCallId, type: 'function', function: { name: 'get_user_skin_profile', arguments: '{}' } }
      ]},
      { role: 'tool', tool_call_id: profileCallId, content: formatProfileForToolResult(profile) },
      { role: 'assistant', content: responseText }
    ],
    tools: TOOLS
  };
}

/**
 * Generate a specific concern example with tool calls
 */
async function generateConcernExample(profile) {
  const query = randomFrom(QUERY_TEMPLATES.specific_concern);
  const products = getProductsForProfile(profile);
  const relevantProducts = Object.values(products).flat().slice(0, 5);
  
  const profileCallId = makeToolCallId();
  const searchCallId = makeToolCallId();
  
  const resp = await openai.chat.completions.create({
    model: MODEL,
    messages: [
      { role: 'system', content: `Generate a detailed response to a specific skin concern from GlowUp AI. Address the concern directly, explain the science briefly, then recommend specific products and practices. Use markdown.

PROFILE: ${formatProfileForToolResult(profile)}
PRODUCTS: ${JSON.stringify(relevantProducts)}

Be thorough — explain WHY each product/ingredient helps this specific concern, reference the user's profile for personalization.` },
      { role: 'user', content: query }
    ],
    max_tokens: 1000,
    temperature: 0.7,
  });

  const responseText = resp.choices[0]?.message?.content || '';
  if (!responseText || responseText.length < 80) return null;

  return {
    messages: [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: [
        { type: 'text', text: `${query}\n\n${formatProfileForUser(profile)}` },
        { type: 'image_url', image_url: { url: 'https://example.com/user_skin_photo.jpg', detail: 'low' } }
      ]},
      { role: 'assistant', tool_calls: [
        { id: profileCallId, type: 'function', function: { name: 'get_user_skin_profile', arguments: '{}' } },
        { id: searchCallId, type: 'function', function: { name: 'search_products', arguments: JSON.stringify({ query: query.toLowerCase(), concern: profile.concerns[0], max_results: 5 }) } }
      ]},
      { role: 'tool', tool_call_id: profileCallId, content: formatProfileForToolResult(profile) },
      { role: 'tool', tool_call_id: searchCallId, content: JSON.stringify({ products: relevantProducts }) },
      { role: 'assistant', content: responseText }
    ],
    tools: TOOLS
  };
}

/**
 * Generate comparison example with tool calls
 */
async function generateCompareExample(profile) {
  const query = randomFrom(QUERY_TEMPLATES.compare);
  const products = getProductsForProfile(profile);
  const allProducts = Object.values(products).flat();
  const compareProducts = allProducts.slice(0, 2);
  
  if (compareProducts.length < 2) return null;
  
  const compareCallId = makeToolCallId();
  
  const resp = await openai.chat.completions.create({
    model: MODEL,
    messages: [
      { role: 'system', content: `Generate a product comparison response from GlowUp AI. Compare the products fairly, noting pros/cons of each for this user's specific profile. Use markdown with a clear format. Make a recommendation at the end.

PROFILE: ${formatProfileForToolResult(profile)}
PRODUCTS: ${JSON.stringify(compareProducts)}` },
      { role: 'user', content: query }
    ],
    max_tokens: 800,
    temperature: 0.7,
  });

  const responseText = resp.choices[0]?.message?.content || '';
  if (!responseText || responseText.length < 80) return null;

  return {
    messages: [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: query },
      { role: 'assistant', tool_calls: [
        { id: compareCallId, type: 'function', function: { name: 'compare_products', arguments: JSON.stringify({ product_names: compareProducts.map(p => p.name) }) } }
      ]},
      { role: 'tool', tool_call_id: compareCallId, content: JSON.stringify({ products: compareProducts }) },
      { role: 'assistant', content: responseText }
    ],
    tools: TOOLS
  };
}

/**
 * Generate edge case example
 */
async function generateEdgeCaseExample(profile) {
  const query = randomFrom(QUERY_TEMPLATES.edge_cases);
  const profileCallId = makeToolCallId();

  const resp = await openai.chat.completions.create({
    model: MODEL,
    messages: [
      { role: 'system', content: `Generate a careful, evidence-based response from GlowUp AI to an edge-case skincare question. Be thorough, honest, and safe. Use markdown. If it's a medical concern, recommend consulting a dermatologist while still providing general advice.

PROFILE: ${formatProfileForToolResult(profile)}` },
      { role: 'user', content: query }
    ],
    max_tokens: 800,
    temperature: 0.7,
  });

  const responseText = resp.choices[0]?.message?.content || '';
  if (!responseText || responseText.length < 80) return null;

  return {
    messages: [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: query },
      { role: 'assistant', tool_calls: [
        { id: profileCallId, type: 'function', function: { name: 'get_user_skin_profile', arguments: '{}' } }
      ]},
      { role: 'tool', tool_call_id: profileCallId, content: formatProfileForToolResult(profile) },
      { role: 'assistant', content: responseText }
    ],
    tools: TOOLS
  };
}


// ═══════════════════════════════════════════════════════════════
// MAIN PIPELINE
// ═══════════════════════════════════════════════════════════════

async function main() {
  console.log(`
╔═══════════════════════════════════════════════════════════╗
║  📚 doc2dataset v2 — GlowUp Comprehensive Fine-tuning    ║
║  Features: Multimodal + Onboarding + Tool-calling         ║
║            + Routines + Best Practices + Products          ║
╚═══════════════════════════════════════════════════════════╝
`);

  const examples = [];
  let failed = 0;

  // ── 1. Full Routine Examples (one per profile) ──
  console.log('🧴 Generating full routine examples (with tool calls)...');
  for (const profile of USER_PROFILES) {
    process.stdout.write(`   ${profile.skinType}/${profile.skinToneLabel}/${profile.ageGroup}... `);
    try {
      const ex = await generateRoutineExample(profile);
      if (ex) { examples.push(ex); console.log('✅'); }
      else { console.log('⚠️ skip'); failed++; }
    } catch (e) { console.log(`❌ ${e.message?.substring(0, 50)}`); failed++; }
  }

  // ── 2. Product Recommendation Examples ──
  console.log('\n🛍️  Generating product recommendation examples...');
  for (let i = 0; i < 15; i++) {
    const profile = USER_PROFILES[i % USER_PROFILES.length];
    process.stdout.write(`   ${i + 1}/15... `);
    try {
      const ex = await generateProductRecommendationExample(profile);
      if (ex) { examples.push(ex); console.log('✅'); }
      else { console.log('⚠️ skip'); failed++; }
    } catch (e) { console.log(`❌ ${e.message?.substring(0, 50)}`); failed++; }
  }

  // ── 3. Best Practices / Lifestyle Examples ──
  console.log('\n🌿 Generating best practices & lifestyle examples...');
  for (let i = 0; i < 12; i++) {
    const profile = USER_PROFILES[i % USER_PROFILES.length];
    process.stdout.write(`   ${i + 1}/12... `);
    try {
      const ex = await generateBestPracticesExample(profile);
      if (ex) { examples.push(ex); console.log('✅'); }
      else { console.log('⚠️ skip'); failed++; }
    } catch (e) { console.log(`❌ ${e.message?.substring(0, 50)}`); failed++; }
  }

  // ── 4. Specific Concern Examples ──
  console.log('\n🎯 Generating specific concern examples...');
  for (let i = 0; i < 12; i++) {
    const profile = USER_PROFILES[i % USER_PROFILES.length];
    process.stdout.write(`   ${i + 1}/12... `);
    try {
      const ex = await generateConcernExample(profile);
      if (ex) { examples.push(ex); console.log('✅'); }
      else { console.log('⚠️ skip'); failed++; }
    } catch (e) { console.log(`❌ ${e.message?.substring(0, 50)}`); failed++; }
  }

  // ── 5. Product Comparison Examples ──
  console.log('\n⚖️  Generating comparison examples...');
  for (let i = 0; i < 6; i++) {
    const profile = USER_PROFILES[i % USER_PROFILES.length];
    process.stdout.write(`   ${i + 1}/6... `);
    try {
      const ex = await generateCompareExample(profile);
      if (ex) { examples.push(ex); console.log('✅'); }
      else { console.log('⚠️ skip'); failed++; }
    } catch (e) { console.log(`❌ ${e.message?.substring(0, 50)}`); failed++; }
  }

  // ── 6. Edge Case Examples ──
  console.log('\n⚠️  Generating edge case examples...');
  for (let i = 0; i < 8; i++) {
    const profile = USER_PROFILES[i % USER_PROFILES.length];
    process.stdout.write(`   ${i + 1}/8... `);
    try {
      const ex = await generateEdgeCaseExample(profile);
      if (ex) { examples.push(ex); console.log('✅'); }
      else { console.log('⚠️ skip'); failed++; }
    } catch (e) { console.log(`❌ ${e.message?.substring(0, 50)}`); failed++; }
  }

  // ═══ EXPORT ═══
  console.log(`\n📊 Total: ${examples.length} examples (${failed} failed)\n`);

  const outPath = path.resolve(__dirname, '../../../skincare_finetune.jsonl');
  const lines = examples.map(e => JSON.stringify(e));
  fs.writeFileSync(outPath, lines.join('\n') + '\n');

  const fileSize = fs.statSync(outPath).size;
  const tokenEstimate = Math.round(lines.join('').length / 4);

  console.log(`✅ Exported ${examples.length} examples to ${outPath}`);
  console.log(`   File size: ${(fileSize / 1024).toFixed(1)} KB`);
  console.log(`   Estimated tokens: ~${tokenEstimate.toLocaleString()}`);

  // Summary
  const withToolCalls = examples.filter(e => e.messages.some(m => m.tool_calls));
  const withImages = examples.filter(e => e.messages.some(m => Array.isArray(m.content)));
  const withTools = examples.filter(e => e.tools);

  console.log(`\n   📋 Breakdown:`);
  console.log(`      With tool calls: ${withToolCalls.length}`);
  console.log(`      With image inputs: ${withImages.length}`);
  console.log(`      With tool definitions: ${withTools.length}`);

  console.log(`
╔═══════════════════════════════════════════════════════════╗
║  ✅ Pipeline complete!                                    ║
║  Output: skincare_finetune.jsonl                          ║
║  Valid examples: ${String(examples.length).padEnd(5)}                                 ║
║                                                           ║
║  Review the file, then run:                               ║
║    npm run upload-finetune                                 ║
║  Model: gpt-5-mini-2025-08-07                             ║
╚═══════════════════════════════════════════════════════════╝
`);
}

main().catch(e => {
  console.error('❌ Pipeline failed:', e);
  process.exit(1);
});
