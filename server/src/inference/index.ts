import OpenAI from 'openai';
import { supabase } from '../db/supabase';

// Skincare product categories for filtering
const SKINCARE_CATEGORIES = ['cleanser', 'moisturizer', 'treatment', 'serum', 'sunscreen', 'toner', 'mask', 'exfoliant', 'face', 'eye'];

// Initialize OpenAI (only if API key is available)
let openai: OpenAI | null = null;
if (process.env.OPENAI_API_KEY) {
  openai = new OpenAI({
    apiKey: process.env.OPENAI_API_KEY
  });
  console.log('✅ OpenAI configured for LLM inference');
} else {
  console.log('⚠️ OPENAI_API_KEY not set - LLM inference disabled, using rule-based fallback');
}

export interface UserProfileForInference {
  skinType: string;
  skinTone?: number;
  skinGoals?: string[];
  skinConcerns?: string[];
  hairType?: string;
  hairConcerns?: string[];
  washFrequency?: string;
  sunscreenUsage?: string;
  budget?: string;
  fragranceFree?: boolean;
}

export interface ProductMatch {
  id: string;
  name: string;
  brand: string;
  price: number;
  category: string;
  description: string;
  image_url: string | null;
  rating: number;
  similarity: number;
  relevance_reason?: string;
  buy_link?: string | null;
}

export interface InferenceResult {
  products: ProductMatch[];
  routine: {
    morning: RoutineStep[];
    evening: RoutineStep[];
    weekly: RoutineStep[];
  };
  summary: string;
  personalized_tips: string[];
}

export interface RoutineStep {
  step: number;
  name: string;
  product?: ProductMatch;
  instructions: string;
  frequency: string;
}

/**
 * Generate an embedding for a text query using OpenAI
 */
async function generateEmbedding(text: string): Promise<number[] | null> {
  if (!openai) {
    console.log('⚠️ OpenAI not configured, skipping embedding generation');
    return null;
  }
  
  const response = await openai.embeddings.create({
    model: 'text-embedding-3-small',
    input: text,
    dimensions: 1536
  });
  return response.data[0].embedding;
}

/**
 * Build a natural language query from user profile for semantic search
 */
function buildProfileQuery(profile: UserProfileForInference): string {
  const parts: string[] = [];
  
  // Skin description
  parts.push(`Skincare products for ${profile.skinType} skin`);
  
  if (profile.skinGoals && profile.skinGoals.length > 0) {
    const goalDescriptions: Record<string, string> = {
      'glass_skin': 'achieving glass skin with hydration and glow',
      'clear_skin': 'clearing acne and preventing breakouts',
      'brightening': 'brightening dark spots and evening skin tone',
      'anti_aging': 'reducing fine lines and wrinkles with anti-aging',
      'barrier_repair': 'repairing damaged skin barrier'
    };
    const goals = profile.skinGoals.map(g => goalDescriptions[g] || g).join(', ');
    parts.push(`targeting ${goals}`);
  }
  
  if (profile.skinConcerns && profile.skinConcerns.length > 0) {
    parts.push(`for concerns: ${profile.skinConcerns.join(', ')}`);
  }
  
  // Skin tone considerations
  if (profile.skinTone !== undefined) {
    if (profile.skinTone >= 0.6) {
      parts.push('safe for melanin-rich skin, avoiding ingredients that cause hyperpigmentation');
    }
  }
  
  // Budget
  if (profile.budget === 'low') {
    parts.push('affordable drugstore options');
  } else if (profile.budget === 'high') {
    parts.push('premium luxury skincare');
  }
  
  // Fragrance preference
  if (profile.fragranceFree) {
    parts.push('fragrance-free and hypoallergenic');
  }
  
  return parts.join('. ');
}

/**
 * Build a query for hair products
 */
function buildHairQuery(profile: UserProfileForInference): string {
  const parts: string[] = [];
  
  if (profile.hairType) {
    parts.push(`Haircare for ${profile.hairType} hair`);
  }
  
  if (profile.hairConcerns && profile.hairConcerns.length > 0) {
    parts.push(`addressing ${profile.hairConcerns.join(', ')}`);
  }
  
  if (profile.washFrequency) {
    const freqMap: Record<string, string> = {
      'daily': 'for daily washing',
      '2_3_weekly': 'for washing 2-3 times per week',
      'weekly': 'for weekly wash routine',
      'biweekly': 'for protective styles and infrequent washing',
      'monthly': 'for protective styles with minimal washing'
    };
    parts.push(freqMap[profile.washFrequency] || '');
  }
  
  return parts.join('. ');
}

/**
 * Perform hybrid search: vector similarity + keyword matching
 */
async function hybridSearch(
  queryEmbedding: number[], 
  keywords: string[],
  category?: string,
  maxPrice?: number,
  limit: number = 10
): Promise<ProductMatch[]> {
  // Build the query
  let query = supabase.rpc('match_products', {
    query_embedding: queryEmbedding,
    match_threshold: 0.3,
    match_count: limit * 2 // Get more to filter
  });

  const { data: vectorResults, error: vectorError } = await query;
  
  if (vectorError) {
    console.error('Vector search error:', vectorError);
    // Fallback to basic text search
    return fallbackSearch(keywords, category, maxPrice, limit);
  }

  // Start with vector results
  let results = vectorResults || [];

  // Add text search results using search_vector for hybrid relevance
  if (keywords.length > 0) {
    const tsQuery = keywords.join(' | ');
    const { data: textResults } = await supabase
      .from('products')
      .select('*')
      .textSearch('search_vector', tsQuery)
      .limit(limit * 2);
    
    if (textResults && textResults.length > 0) {
      results = results.concat(textResults);
    }
  }

  // Dedupe by id before filtering
  const byId = new Map<string, any>();
  for (const p of results) {
    if (p?.id && !byId.has(p.id)) byId.set(p.id, p);
  }
  results = Array.from(byId.values());
  
  // Apply category filter if specified
  if (category) {
    results = results.filter((p: any) => p.category === category);
  }
  
  // Apply price filter
  if (maxPrice) {
    results = results.filter((p: any) => p.price <= maxPrice);
  }
  
  // Boost scores for keyword matches
  const boostedResults = results.map((p: any) => {
    let boost = 0;
    const searchText = `${p.name} ${p.brand} ${p.description}`.toLowerCase();
    
    for (const keyword of keywords) {
      if (searchText.includes(keyword.toLowerCase())) {
        boost += 0.1;
      }
    }
    
    return {
      ...p,
      similarity: Math.min((p.similarity || 0.5) + boost, 1.0)
    };
  });
  
  // Sort by boosted similarity
  boostedResults.sort((a: any, b: any) => b.similarity - a.similarity);
  
  return boostedResults.slice(0, limit).map((p: any) => ({
    id: p.id,
    name: p.name,
    brand: p.brand,
    price: p.price,
    category: p.category,
    description: p.description,
    image_url: p.image_url,
    rating: p.rating || 4.0,
    similarity: p.similarity
  }));
}

/**
 * Smart search using target_skin_type, target_concerns, and full-text search
 * Uses the actual product schema columns
 */
async function fallbackSearch(
  keywords: string[],
  category?: string,
  maxPrice?: number,
  limit: number = 10
): Promise<ProductMatch[]> {
  console.log('🔍 Smart search with keywords:', keywords);
  
  // Map user inputs to product target values
  const skinTypeMap: Record<string, string[]> = {
    'oily': ['oily', 'all', 'combination'],
    'dry': ['dry', 'all', 'sensitive'],
    'combination': ['combination', 'all', 'oily', 'dry'],
    'sensitive': ['sensitive', 'all', 'dry'],
    'normal': ['normal', 'all'],
  };
  
  const concernMap: Record<string, string[]> = {
    'acne': ['acne', 'breakouts', 'blemishes', 'pores', 'oily'],
    'aging': ['aging', 'anti-aging', 'wrinkles', 'fine lines', 'firmness'],
    'pigmentation': ['pigmentation', 'dark spots', 'brightening', 'uneven tone'],
    'dark_spots': ['dark spots', 'pigmentation', 'brightening', 'hyperpigmentation'],
    'dryness': ['dryness', 'hydration', 'moisture', 'dehydration'],
    'redness': ['redness', 'sensitivity', 'calming', 'rosacea'],
    'texture': ['texture', 'smoothing', 'exfoliation', 'rough'],
    'glass_skin': ['hydration', 'glow', 'radiance', 'dewy'],
    'clear_skin': ['acne', 'breakouts', 'clarity', 'pores'],
    'brightening': ['brightening', 'radiance', 'glow', 'dull'],
    'anti_aging': ['aging', 'anti-aging', 'wrinkles', 'firmness'],
    'barrier_repair': ['barrier', 'repair', 'soothing', 'sensitive'],
    'frizz': ['frizz', 'smoothing', 'humidity'],
    'damage': ['damage', 'repair', 'strengthening'],
    'breakage': ['breakage', 'strengthening', 'repair'],
  };
  
  // Build search terms
  const skinTypes = keywords
    .filter(k => skinTypeMap[k.toLowerCase()])
    .flatMap(k => skinTypeMap[k.toLowerCase()]);
  
  const concerns = keywords
    .filter(k => concernMap[k.toLowerCase()])
    .flatMap(k => concernMap[k.toLowerCase()]);
  
  console.log('📦 Searching for skin types:', [...new Set(skinTypes)].slice(0, 5));
  console.log('📦 Searching for concerns:', [...new Set(concerns)].slice(0, 5));
  
  let allResults: any[] = [];
  
  // Search 1: By target_skin_type
  if (skinTypes.length > 0) {
    const { data: skinResults, error } = await supabase
      .from('products')
      .select('*')
      .overlaps('target_skin_type', [...new Set(skinTypes)])
      .lte('price', maxPrice || 200)
      .order('rating', { ascending: false })
      .limit(limit);
    
    if (!error && skinResults) {
      allResults.push(...skinResults);
    }
  }
  
  // Search 2: By target_concerns
  if (concerns.length > 0) {
    const { data: concernResults, error } = await supabase
      .from('products')
      .select('*')
      .overlaps('target_concerns', [...new Set(concerns)])
      .lte('price', maxPrice || 200)
      .order('rating', { ascending: false })
      .limit(limit);
    
    if (!error && concernResults) {
      allResults.push(...concernResults);
    }
  }
  
  // Search 3: Text search in name, summary, ingredients
  const searchTerms = keywords.slice(0, 3);
  for (const term of searchTerms) {
    const { data: textResults, error } = await supabase
      .from('products')
      .select('*')
      .or(`name.ilike.%${term}%,summary.ilike.%${term}%,ingredients.cs.{${term}}`)
      .lte('price', maxPrice || 200)
      .order('rating', { ascending: false })
      .limit(limit / 2);
    
    if (!error && textResults) {
      allResults.push(...textResults);
    }
  }

  // Search 4: Full-text search via search_vector
  if (keywords.length > 0) {
    const tsQuery = keywords.join(' | ');
    const { data: textResults, error } = await supabase
      .from('products')
      .select('*')
      .textSearch('search_vector', tsQuery)
      .lte('price', maxPrice || 200)
      .limit(limit);
    
    if (!error && textResults) {
      allResults.push(...textResults);
    }
  }
  
  // Dedupe results
  const seen = new Set<string>();
  const uniqueResults: any[] = [];
  for (const p of allResults) {
    if (!seen.has(p.id)) {
      seen.add(p.id);
      uniqueResults.push(p);
    }
  }
  
  // Score results based on matches
  const scoredResults = uniqueResults.map((p: any) => {
    let score = 0.6; // Base score
    
    const productSkinTypes = (p.target_skin_type || []).map((t: string) => t.toLowerCase());
    const productConcerns = (p.target_concerns || []).map((t: string) => t.toLowerCase());
    
    // Boost for skin type match
    for (const st of skinTypes) {
      if (productSkinTypes.includes(st.toLowerCase())) {
        score += 0.1;
        break;
      }
    }
    
    // Boost for concern match
    for (const c of concerns) {
      if (productConcerns.some((pc: string) => pc.includes(c.toLowerCase()))) {
        score += 0.08;
      }
    }
    
    // Boost for rating
    score += ((p.rating || 4.0) - 3.5) * 0.05;
    
    // Slight penalty for very expensive items in budget mode
    if (maxPrice && maxPrice < 30 && p.price > maxPrice * 0.8) {
      score -= 0.05;
    }
    
    return {
      ...p,
      similarity: Math.min(score, 0.98)
    };
  });
  
  // Sort by score
  scoredResults.sort((a: any, b: any) => b.similarity - a.similarity);
  
  console.log(`✅ Found ${scoredResults.length} products, returning top ${limit}`);
  
  return scoredResults.slice(0, limit).map((p: any) => ({
    id: p.id,
    name: p.name,
    brand: p.brand,
    price: p.price,
    category: p.category,
    description: p.summary || '',
    image_url: p.image_url,
    rating: p.rating || 4.0,
    similarity: p.similarity
  }));
}

// ─── Fine-tuned model for all inference ──────────────────────────
const GLOWUP_MODEL = process.env.GLOWUP_CHAT_MODEL || 'ft:gpt-4o-2024-08-06:dave:glowup-product-embeds:D6KQn97D';

// Tool definitions for the fine-tuned model (same as chat endpoint)
const inferenceTools: OpenAI.Chat.Completions.ChatCompletionTool[] = [
  {
    type: 'function',
    function: {
      name: 'search_products',
      description: 'Search the GlowUp product database for skincare products. Uses semantic + keyword search.',
      parameters: {
        type: 'object',
        properties: {
          query: { type: 'string', description: 'Natural language search query' },
          category: { type: 'string', description: 'Product category filter', enum: ['cleanser', 'moisturizer', 'serum', 'sunscreen', 'treatment', 'toner', 'mask', 'exfoliant', 'eye', 'face'] },
          skin_type: { type: 'string', description: 'Filter by skin type', enum: ['oily', 'dry', 'combination', 'sensitive', 'normal', 'acne-prone'] },
          concerns: { type: 'array', items: { type: 'string' }, description: 'Filter by concerns' },
          max_price: { type: 'number', description: 'Maximum price in USD' },
          limit: { type: 'number', description: 'Max products to return (default 6)' }
        },
        required: ['query']
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'get_product_details',
      description: 'Get full details for a specific product by name or ID.',
      parameters: {
        type: 'object',
        properties: {
          product_name: { type: 'string', description: 'Product name to look up' },
          product_id: { type: 'string', description: 'Product UUID if known' }
        },
        required: []
      }
    }
  }
];

/**
 * Execute a tool call from the inference model
 */
async function executeInferenceTool(toolName: string, args: any): Promise<string> {
  try {
    switch (toolName) {
      case 'search_products': {
        const query = args.query || '';
        const category = args.category;
        const skinType = args.skin_type;
        const concerns = args.concerns || [];
        const maxPrice = args.max_price;
        const limit = Math.min(args.limit || 6, 15);

        const keywords = query.split(/\s+/).filter((w: string) => w.length > 2);
        if (skinType) keywords.push(skinType);
        if (concerns.length) keywords.push(...concerns);

        let results: any[] = [];

        // Try vector search first
        if (openai) {
          try {
            const embeddingResponse = await openai.embeddings.create({
              model: 'text-embedding-3-small',
              input: query
            });
            const queryEmbedding = embeddingResponse.data[0].embedding;
            const { data: vectorResults, error } = await supabase.rpc('match_products', {
              query_embedding: queryEmbedding,
              match_threshold: 0.25,
              match_count: limit * 3
            });
            if (!error && vectorResults) results = vectorResults;
          } catch {}
        }

        // Supplement with keyword search
        if (results.length < limit) {
          let q = supabase.from('products').select('*');
          if (category) q = q.eq('category', category);
          if (skinType) q = q.contains('target_skin_type', [skinType]);
          if (maxPrice) q = q.lte('price', maxPrice);
          q = q.order('rating', { ascending: false }).limit(limit * 2);
          const { data } = await q;
          if (data) {
            const existingIds = new Set(results.map((r: any) => r.id));
            for (const p of data) {
              if (!existingIds.has(p.id)) results.push(p);
            }
          }
        }

        // Apply filters
        if (category) results = results.filter((p: any) => p.category === category);
        if (maxPrice) results = results.filter((p: any) => p.price <= maxPrice);

        const cleaned = results.slice(0, limit).map((p: any) => ({
          id: p.id, name: p.name, brand: p.brand, price: p.price,
          category: p.category, summary: p.summary || p.description,
          rating: p.rating, image_url: p.image_url,
          target_skin_type: p.target_skin_type, target_concerns: p.target_concerns,
          ingredients: (p.ingredients || []).slice(0, 8),
          attributes: p.attributes, buy_link: p.buy_link,
          similarity: p.similarity
        }));

        return JSON.stringify({ count: cleaned.length, products: cleaned });
      }

      case 'get_product_details': {
        let product: any = null;
        if (args.product_id) {
          const { data } = await supabase.from('products').select('*').eq('id', args.product_id).single();
          product = data;
        } else if (args.product_name) {
          const { data } = await supabase.from('products').select('*').ilike('name', `%${args.product_name}%`).limit(1).single();
          product = data;
        }
        if (!product) return JSON.stringify({ error: 'Product not found' });
        return JSON.stringify({
          id: product.id, name: product.name, brand: product.brand, price: product.price,
          category: product.category, summary: product.summary, rating: product.rating,
          image_url: product.image_url, buy_link: product.buy_link,
          target_skin_type: product.target_skin_type, target_concerns: product.target_concerns,
          ingredients: product.ingredients, attributes: product.attributes, size: product.size,
          how_to_use: product.how_to_use,
        });
      }

      default:
        return JSON.stringify({ error: `Unknown tool: ${toolName}` });
    }
  } catch (err: any) {
    return JSON.stringify({ error: `Tool failed: ${err?.message}` });
  }
}

/**
 * Resolve a product name/brand against DB to get full product record.
 * Returns a ProductMatch with real id, image_url, buy_link, etc.
 */
async function resolveProductFromDB(
  productName: string,
  productBrand?: string
): Promise<ProductMatch | null> {
  try {
    // 1. Exact ilike match on name
    let query = supabase.from('products').select('*').ilike('name', `%${productName}%`);
    if (productBrand) query = query.ilike('brand', `%${productBrand}%`);
    const { data } = await query.limit(1).single();
    if (data) {
      return {
        id: data.id,
        name: data.name,
        brand: data.brand,
        price: data.price,
        category: data.category,
        description: data.summary || data.description || '',
        image_url: data.image_url,
        rating: data.rating || 4.0,
        similarity: 0.9,
        buy_link: data.buy_link,
      };
    }

    // 2. If exact failed and name is long, try first few words
    const shortName = productName.split(' ').slice(0, 3).join(' ');
    if (shortName !== productName) {
      const { data: d2 } = await supabase.from('products').select('*')
        .ilike('name', `%${shortName}%`)
        .limit(1).single();
      if (d2) {
        return {
          id: d2.id, name: d2.name, brand: d2.brand, price: d2.price,
          category: d2.category, description: d2.summary || '',
          image_url: d2.image_url, rating: d2.rating || 4.0,
          similarity: 0.85, buy_link: d2.buy_link,
        };
      }
    }

    return null;
  } catch {
    return null;
  }
}

type FocusTarget = {
  key: string;
  label: string;
  queryTerms: string[];
  preferredCategory: string;
  routineType: 'morning' | 'evening' | 'weekly';
  stepName: string;
  instruction: string;
};

function getFocusTargets(profile: UserProfileForInference): FocusTarget[] {
  const base: Record<string, FocusTarget> = {
    acne: {
      key: 'acne',
      label: 'acne + breakouts',
      queryTerms: ['acne', 'breakouts', profile.skinType || 'oily'],
      preferredCategory: 'treatment',
      routineType: 'evening',
      stepName: 'Acne Treatment',
      instruction: 'Apply a thin layer to breakout-prone areas to help reduce active acne and prevent new blemishes.'
    },
    dark_spots: {
      key: 'dark_spots',
      label: 'dark spots',
      queryTerms: ['dark spots', 'hyperpigmentation', 'brightening'],
      preferredCategory: 'serum',
      routineType: 'evening',
      stepName: 'Dark Spot Corrector',
      instruction: 'Use on dark spots and uneven tone zones to visibly improve pigmentation over time.'
    },
    pigmentation: {
      key: 'pigmentation',
      label: 'pigmentation',
      queryTerms: ['pigmentation', 'uneven tone', 'brightening'],
      preferredCategory: 'serum',
      routineType: 'evening',
      stepName: 'Tone-Correcting Serum',
      instruction: 'Apply nightly to support a more even skin tone and reduce discoloration.'
    },
    redness: {
      key: 'redness',
      label: 'redness',
      queryTerms: ['redness', 'soothing', 'sensitive'],
      preferredCategory: 'moisturizer',
      routineType: 'evening',
      stepName: 'Calming Moisturizer',
      instruction: 'Use as your final step to calm visible redness and support the skin barrier.'
    },
    sensitivity: {
      key: 'sensitivity',
      label: 'sensitivity',
      queryTerms: ['sensitive', 'barrier', 'fragrance free'],
      preferredCategory: 'moisturizer',
      routineType: 'evening',
      stepName: 'Barrier Support',
      instruction: 'Focus on barrier-repair ingredients and avoid harsh actives while skin is reactive.'
    },
    dryness: {
      key: 'dryness',
      label: 'dryness',
      queryTerms: ['dryness', 'hydration', 'moisture'],
      preferredCategory: 'moisturizer',
      routineType: 'evening',
      stepName: 'Deep Hydration',
      instruction: 'Seal hydration with this richer step to improve dryness and tightness.'
    },
    texture: {
      key: 'texture',
      label: 'texture',
      queryTerms: ['texture', 'smooth', 'exfoliant'],
      preferredCategory: 'exfoliant',
      routineType: 'weekly',
      stepName: 'Texture Reset',
      instruction: 'Use 1-2 times weekly to smooth rough texture and refine skin surface.'
    },
    aging: {
      key: 'aging',
      label: 'aging',
      queryTerms: ['anti aging', 'wrinkles', 'fine lines', 'retinol'],
      preferredCategory: 'treatment',
      routineType: 'evening',
      stepName: 'Line-Smoothing Treatment',
      instruction: 'Apply at night to target fine lines and improve long-term skin firmness.'
    },
    glass_skin: {
      key: 'glass_skin',
      label: 'glass skin glow',
      queryTerms: ['glass skin', 'dewy', 'hydrating serum'],
      preferredCategory: 'serum',
      routineType: 'morning',
      stepName: 'Glow Serum',
      instruction: 'Layer under moisturizer for a hydrated, dewy glass-skin finish.'
    },
    clear_skin: {
      key: 'clear_skin',
      label: 'clear skin',
      queryTerms: ['clear skin', 'pores', 'breakouts'],
      preferredCategory: 'treatment',
      routineType: 'evening',
      stepName: 'Clarifying Treatment',
      instruction: 'Use consistently to keep pores clear and support a clearer complexion.'
    },
    brightening: {
      key: 'brightening',
      label: 'brightening',
      queryTerms: ['brightening', 'radiance', 'dullness', 'vitamin c'],
      preferredCategory: 'serum',
      routineType: 'morning',
      stepName: 'Brightening Serum',
      instruction: 'Apply in the morning to boost radiance and support a brighter tone.'
    },
    anti_aging: {
      key: 'anti_aging',
      label: 'anti-aging',
      queryTerms: ['anti aging', 'retinol', 'firmness', 'wrinkles'],
      preferredCategory: 'treatment',
      routineType: 'evening',
      stepName: 'Anti-Aging Active',
      instruction: 'Use as your evening active to improve texture, tone, and visible lines.'
    },
    barrier_repair: {
      key: 'barrier_repair',
      label: 'barrier repair',
      queryTerms: ['barrier repair', 'ceramide', 'soothing'],
      preferredCategory: 'moisturizer',
      routineType: 'evening',
      stepName: 'Barrier Repair Cream',
      instruction: 'Apply nightly to strengthen barrier function and reduce irritation risk.'
    }
  };

  const desired = [...(profile.skinConcerns || []), ...(profile.skinGoals || [])]
    .map(v => v.toLowerCase())
    .filter(v => !!base[v]);

  const unique = Array.from(new Set(desired));
  return unique.slice(0, 3).map(k => base[k]);
}

function hasTargetCoverage(routine: InferenceResult['routine'], target: FocusTarget): boolean {
  const text = [
    ...routine.morning.map(s => `${s.name} ${s.instructions} ${s.product?.name || ''} ${s.product?.description || ''}`),
    ...routine.evening.map(s => `${s.name} ${s.instructions} ${s.product?.name || ''} ${s.product?.description || ''}`),
    ...routine.weekly.map(s => `${s.name} ${s.instructions} ${s.product?.name || ''} ${s.product?.description || ''}`),
  ].join(' ').toLowerCase();

  return target.queryTerms.some(term => text.includes(term.toLowerCase()));
}

async function findTargetedProductForFocus(
  target: FocusTarget,
  profile: UserProfileForInference,
  presearched: ProductMatch[]
): Promise<ProductMatch | null> {
  const budgetMax = profile.budget === 'low' ? 25 : profile.budget === 'high' ? 100 : 60;
  const q = target.queryTerms.map(t => t.toLowerCase());

  // 1) Try from pre-searched products first (fast path)
  const fromPre = presearched.find(p => {
    const text = `${p.name} ${p.category} ${p.description}`.toLowerCase();
    return q.some(term => text.includes(term)) || (p.category || '').toLowerCase().includes(target.preferredCategory);
  });
  if (fromPre) return fromPre;

  // 2) Query DB with fallback search using focus terms
  const fallback = await fallbackSearch(
    [profile.skinType, ...target.queryTerms].filter(Boolean) as string[],
    target.preferredCategory,
    budgetMax,
    5
  );

  if (fallback.length > 0) return fallback[0];
  return null;
}

async function ensureFocusCoverage(
  profile: UserProfileForInference,
  routine: InferenceResult['routine'],
  presearched: ProductMatch[]
): Promise<{ routine: InferenceResult['routine']; addedFocus: string[] }> {
  const focusTargets = getFocusTargets(profile);
  if (focusTargets.length === 0) return { routine, addedFocus: [] };

  const used = new Set(
    [...routine.morning, ...routine.evening, ...routine.weekly]
      .map(s => s.product?.id)
      .filter(Boolean) as string[]
  );

  const addedFocus: string[] = [];
  const nextRoutine = {
    morning: [...routine.morning],
    evening: [...routine.evening],
    weekly: [...routine.weekly],
  };

  for (const target of focusTargets) {
    if (hasTargetCoverage(nextRoutine, target)) continue;

    const match = await findTargetedProductForFocus(target, profile, presearched);
    if (!match) continue;
    if (used.has(match.id)) continue;

    const bucket = target.routineType;
    const arr = nextRoutine[bucket];

    // Keep routines compact
    if (bucket !== 'weekly' && arr.length >= 5) continue;
    if (bucket === 'weekly' && arr.length >= 3) continue;

    arr.push({
      step: arr.length + 1,
      name: target.stepName,
      product: match,
      instructions: target.instruction,
      frequency: bucket === 'weekly' ? 'weekly' : 'daily',
    });

    used.add(match.id);
    addedFocus.push(target.label);
  }

  return { routine: nextRoutine, addedFocus };
}

/**
 * Use fine-tuned model with tool calling to generate personalized routine.
 * Forces tool calls on the first round so every routine step has a real product.
 * Collects all products discovered during tool calls and resolves each
 * routine step to a real DB product (with id, image_url, buy_link).
 */
async function generatePersonalizedRoutine(
  profile: UserProfileForInference,
  products: ProductMatch[]
): Promise<{ routine: InferenceResult['routine']; summary: string; tips: string[] }> {
  
  // If no OpenAI, use rule-based fallback
  if (!openai) {
    return generateFallbackRoutine(profile, products);
  }

  const skinToneLabel = profile.skinTone !== undefined
    ? (profile.skinTone < 0.3 ? 'Fair' : profile.skinTone < 0.5 ? 'Medium' : profile.skinTone < 0.7 ? 'Medium-deep' : 'Deep')
    : 'not specified';
  const budgetMax = profile.budget === 'low' ? 25 : profile.budget === 'high' ? 100 : 60;

  const systemPrompt = `You are GlowUp AI, a skincare expert creating a personalized routine after onboarding.
You MUST use the search_products tool to find real products from our database for EVERY step. Do NOT invent or hallucinate product names.

WORKFLOW:
1. First, call search_products multiple times to find: a cleanser, treatment/serum, moisturizer, sunscreen (AM only), and exfoliant (weekly). Filter by the user's skin type, concerns, and budget.
2. After receiving product results, build the routine JSON using ONLY products found in tool results.
3. Every step MUST have a valid product_id, product_name, product_brand, and product_price copied directly from the tool results.

RESPOND with valid JSON in this exact format (no markdown wrapping):
{
  "morning": [{"step": 1, "name": "Cleanser", "product_id": "uuid-from-tool-result", "product_name": "Full Product Name", "product_brand": "Brand", "product_price": 12.99, "instructions": "How to use it", "frequency": "daily"}],
  "evening": [{"step": 1, "name": "Cleanser", "product_id": "uuid-from-tool-result", "product_name": "...", "product_brand": "...", "product_price": 0, "instructions": "...", "frequency": "daily"}],
  "weekly": [{"step": 1, "name": "Exfoliation", "product_id": "uuid-from-tool-result", "product_name": "...", "product_brand": "...", "product_price": 0, "instructions": "...", "frequency": "weekly"}],
  "summary": "2-sentence summary of the routine approach",
  "tips": ["tip 1", "tip 2", "tip 3"]
}

RULES:
- Morning routine: 3-5 steps (cleanser, serum/treatment, moisturizer, sunscreen).
- Evening routine: 3-5 steps (cleanser, treatment/active, moisturizer).
- Weekly reset: 1-3 steps (exfoliant, mask, or clarifying treatment).
- Include targeted treatment steps that directly address the user's top goals/concerns (e.g. acne, dark spots, barrier repair, brightening).
- Products can appear in multiple routines (e.g. same cleanser AM and PM).
- product_id MUST be a real UUID from tool results — NEVER make one up.`;

  const userMessage = `Build my complete skincare routine. Here is my profile:

- Skin type: ${profile.skinType}
- Skin tone: ${skinToneLabel}
- Goals: ${profile.skinGoals?.join(', ') || 'healthy skin'}
- Concerns: ${profile.skinConcerns?.join(', ') || 'none specified'}
- Sunscreen usage: ${profile.sunscreenUsage || 'sometimes'}
- Budget: ${profile.budget || 'medium'} (~$${budgetMax} max per product)
- Fragrance-free: ${profile.fragranceFree ? 'yes' : 'no'}

Search for products that match my profile, then build the full routine JSON.`;

  // ── Seed product maps with pre-searched products ──
  const toolProductsById = new Map<string, any>();
  const toolProductsByName = new Map<string, any>();
  for (const p of products) {
    if (p.id) toolProductsById.set(p.id, p);
    if (p.name) toolProductsByName.set(p.name.toLowerCase(), p);
  }

  try {
    let messages: OpenAI.Chat.Completions.ChatCompletionMessageParam[] = [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: userMessage }
    ];

    let finalContent = '';
    const MAX_ROUNDS = 6;

    for (let round = 0; round < MAX_ROUNDS; round++) {
      const response = await openai.chat.completions.create({
        model: GLOWUP_MODEL,
        messages,
        tools: inferenceTools,
        // Force tool calling on the first round so the model MUST search products
        tool_choice: round === 0 ? 'required' : 'auto',
        temperature: 0.5,
        max_tokens: 2500,
      });

      const choice = response.choices[0];
      const assistantMsg = choice.message;

      if (assistantMsg.tool_calls && assistantMsg.tool_calls.length > 0) {
        console.log(`  🔧 Inference round ${round + 1}: ${assistantMsg.tool_calls.length} tool call(s)`);
        messages.push(assistantMsg as any);

        const toolResults = await Promise.all(
          assistantMsg.tool_calls.map(async (tc: any) => {
            const fnName = tc.function?.name || tc.name;
            const fnArgs = JSON.parse(tc.function?.arguments || tc.arguments || '{}');
            console.log(`    🛠️  ${fnName}(${JSON.stringify(fnArgs).substring(0, 100)})`);
            const result = await executeInferenceTool(fnName, fnArgs);

            // ── Capture products from tool results ──
            try {
              const parsed = JSON.parse(result);
              if (parsed.products && Array.isArray(parsed.products)) {
                for (const p of parsed.products) {
                  if (p.id) toolProductsById.set(p.id, p);
                  if (p.name) toolProductsByName.set(p.name.toLowerCase(), p);
                }
              } else if (parsed.id) {
                toolProductsById.set(parsed.id, parsed);
                if (parsed.name) toolProductsByName.set(parsed.name.toLowerCase(), parsed);
              }
            } catch {}

            return { role: 'tool' as const, tool_call_id: tc.id, content: result };
          })
        );

        messages.push(...toolResults as any[]);
        continue;
      }

      finalContent = assistantMsg.content || '';
      break;
    }

    if (!finalContent) {
      console.log('⚠️ Fine-tuned model returned no final content, falling back');
      return generateFallbackRoutine(profile, products);
    }

    console.log(`  📦 Tool calls discovered ${toolProductsById.size} unique products`);

    // Extract JSON from the response (it might be wrapped in markdown)
    let jsonStr = finalContent;
    const jsonMatch = finalContent.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (jsonMatch) jsonStr = jsonMatch[1].trim();
    const rawJsonMatch = jsonStr.match(/\{[\s\S]*\}/);
    if (rawJsonMatch) jsonStr = rawJsonMatch[0];

    const parsed = JSON.parse(jsonStr);

    // ── Resolve each step to a real DB product ──
    const resolveStep = async (s: any): Promise<RoutineStep> => {
      let product: ProductMatch | undefined;

      // Priority 1: Model provided product_id directly
      if (s.product_id && toolProductsById.has(s.product_id)) {
        const p = toolProductsById.get(s.product_id)!;
        product = {
          id: p.id, name: p.name, brand: p.brand, price: p.price,
          category: p.category || s.name?.toLowerCase() || '',
          description: p.summary || p.description || '',
          image_url: p.image_url || null, rating: p.rating || 4.0,
          similarity: 0.95, buy_link: p.buy_link,
        };
      }

      // Priority 2: Match by name in tool-discovered products
      if (!product && s.product_name) {
        const lowerName = s.product_name.toLowerCase();
        const toolMatch = toolProductsByName.get(lowerName)
          || [...toolProductsByName.values()].find((p: any) =>
            p.name.toLowerCase().includes(lowerName) || lowerName.includes(p.name.toLowerCase())
          );
        if (toolMatch) {
          product = {
            id: toolMatch.id, name: toolMatch.name, brand: toolMatch.brand,
            price: toolMatch.price, category: toolMatch.category || '',
            description: toolMatch.summary || '', image_url: toolMatch.image_url || null,
            rating: toolMatch.rating || 4.0, similarity: 0.9, buy_link: toolMatch.buy_link,
          };
        }
      }

      // Priority 3: Match in pre-searched products array
      if (!product && s.product_name) {
        const preMatch = products.find(p =>
          p.name.toLowerCase().includes(s.product_name.toLowerCase()) ||
          s.product_name.toLowerCase().includes(p.name.toLowerCase())
        );
        if (preMatch) product = preMatch;
      }

      // Priority 4: Direct DB lookup by name + brand
      if (!product && s.product_name) {
        const dbProduct = await resolveProductFromDB(s.product_name, s.product_brand);
        if (dbProduct) product = dbProduct;
      }

      // Priority 5: Model gave product_id but we didn't find it in tool map — fetch from DB
      if (!product && s.product_id) {
        try {
          const { data } = await supabase.from('products').select('*').eq('id', s.product_id).single();
          if (data) {
            product = {
              id: data.id, name: data.name, brand: data.brand, price: data.price,
              category: data.category, description: data.summary || '',
              image_url: data.image_url, rating: data.rating || 4.0,
              similarity: 0.9, buy_link: data.buy_link,
            };
          }
        } catch {}
      }

      // Priority 6: LAST RESORT — find a top-rated product by step category in DB
      if (!product) {
        const stepName = (s.name || '').toLowerCase();
        const categoryGuess = stepName.includes('cleanser') || stepName.includes('clean') ? 'cleanser'
          : stepName.includes('moistur') ? 'moisturizer'
          : stepName.includes('sunscreen') || stepName.includes('spf') ? 'sunscreen'
          : stepName.includes('serum') || stepName.includes('vitamin') ? 'serum'
          : stepName.includes('toner') ? 'toner'
          : stepName.includes('exfoli') || stepName.includes('scrub') || stepName.includes('peel') ? 'exfoliant'
          : stepName.includes('mask') ? 'mask'
          : stepName.includes('treatment') || stepName.includes('retinol') ? 'treatment'
          : null;

        if (categoryGuess) {
          console.log(`    ⚡ Last-resort DB lookup for category: ${categoryGuess}`);
          let q = supabase.from('products').select('*')
            .eq('category', categoryGuess)
            .lte('price', budgetMax)
            .order('rating', { ascending: false })
            .limit(3);
          const { data: catProducts } = await q;
          if (catProducts && catProducts.length > 0) {
            // Pick one not already used
            const usedIds = new Set([...toolProductsById.keys()]);
            const pick = catProducts.find((cp: any) => !usedIds.has(cp.id)) || catProducts[0];
            product = {
              id: pick.id, name: pick.name, brand: pick.brand, price: pick.price,
              category: pick.category, description: pick.summary || '',
              image_url: pick.image_url, rating: pick.rating || 4.0,
              similarity: 0.8, buy_link: pick.buy_link,
            };
            // Track so we don't repeat
            toolProductsById.set(pick.id, pick);
          }
        }
      }

      return {
        step: s.step,
        name: s.name || `Step ${s.step}`,
        product,
        instructions: s.instructions || '',
        frequency: s.frequency || 'daily'
      };
    };

    const [morningSteps, eveningSteps, weeklySteps] = await Promise.all([
      Promise.all((parsed.morning || []).map(resolveStep)),
      Promise.all((parsed.evening || []).map(resolveStep)),
      Promise.all((parsed.weekly || []).map(resolveStep)),
    ]);

    let routine = { morning: morningSteps, evening: eveningSteps, weekly: weeklySteps };
    const allCandidates = [
      ...products,
      ...Array.from(toolProductsById.values()).map((p: any) => ({
        id: p.id,
        name: p.name,
        brand: p.brand,
        price: p.price,
        category: p.category || '',
        description: p.summary || p.description || '',
        image_url: p.image_url || null,
        rating: p.rating || 4.0,
        similarity: 0.85,
        buy_link: p.buy_link || null,
      } as ProductMatch)),
    ];
    const dedupCandidates = Array.from(new Map(allCandidates.map(p => [p.id, p])).values());
    const coverage = await ensureFocusCoverage(profile, routine, dedupCandidates);
    routine = coverage.routine;
    if (coverage.addedFocus.length > 0) {
      console.log(`🎯 Added focused routine products for: ${coverage.addedFocus.join(', ')}`);
    }

    const resolvedCount = [...routine.morning, ...routine.evening, ...routine.weekly]
      .filter(s => s.product && s.product.id).length;
    const totalSteps = routine.morning.length + routine.evening.length + routine.weekly.length;
    console.log(`✅ Routine generated: ${totalSteps} steps, ${resolvedCount} with real products`);

    return {
      routine,
      summary: parsed.summary || 'A personalized routine for your skin type.',
      tips: parsed.tips || []
    };

  } catch (error: any) {
    console.error('Fine-tuned model routine generation error:', error?.message);
    return generateFallbackRoutine(profile, products);
  }
}

/**
 * Generate a rule-based routine when LLM is unavailable
 */
function generateFallbackRoutine(
  profile: UserProfileForInference,
  products: ProductMatch[]
): { routine: InferenceResult['routine']; summary: string; tips: string[] } {
  // Find products by category
  const cleanser = products.find(p => p.category?.toLowerCase().includes('cleanser') || p.category?.toLowerCase().includes('wash'));
  const moisturizer = products.find(p => p.category?.toLowerCase().includes('moisturizer') || p.category?.toLowerCase().includes('cream'));
  const sunscreen = products.find(p => p.category?.toLowerCase().includes('sunscreen') || p.category?.toLowerCase().includes('spf'));
  const serum = products.find(p => p.category?.toLowerCase().includes('serum') || p.category?.toLowerCase().includes('treatment'));
  const toner = products.find(p => p.category?.toLowerCase().includes('toner') || p.category?.toLowerCase().includes('essence'));
  
  // Build personalized tips based on profile
  const tips: string[] = [];
  
  if (profile.skinType === 'oily') {
    tips.push('Use gel-based products and mattifying ingredients like niacinamide');
  } else if (profile.skinType === 'dry') {
    tips.push('Layer hydrating products and seal with an occlusive moisturizer');
  }
  
  if (profile.skinGoals?.includes('clear_skin')) {
    tips.push('Incorporate salicylic acid or benzoyl peroxide to help control breakouts');
  }
  
  if (profile.skinGoals?.includes('anti_aging')) {
    tips.push('Retinol is your best friend - start slow, 2-3x per week');
  }
  
  if (profile.skinTone && profile.skinTone >= 0.6) {
    tips.push('Be gentle with actives to avoid post-inflammatory hyperpigmentation');
  }
  
  if (profile.sunscreenUsage !== 'daily') {
    tips.push('Daily SPF is the #1 anti-aging product - make it non-negotiable!');
  }
  
  // Ensure we have at least 3 tips
  while (tips.length < 3) {
    const genericTips = [
      'Always patch test new products before full application',
      'Give products 2-4 weeks to show results',
      'Consistency is more important than complexity',
      'Apply products from thinnest to thickest consistency',
      'Don\'t forget your neck and décolletage!'
    ];
    tips.push(genericTips[tips.length] || genericTips[0]);
  }
  
  return {
    routine: {
      morning: [
        { step: 1, name: 'Cleanser', product: cleanser, instructions: profile.skinType === 'oily' ? 'Gently cleanse with lukewarm water to remove overnight oils' : 'Quick rinse or skip if skin feels balanced', frequency: 'daily' },
        ...(toner ? [{ step: 2, name: 'Toner/Essence', product: toner, instructions: 'Pat onto skin while still damp', frequency: 'daily' }] : []),
        { step: toner ? 3 : 2, name: 'Moisturizer', product: moisturizer, instructions: 'Apply to damp skin for better absorption', frequency: 'daily' },
        { step: toner ? 4 : 3, name: 'Sunscreen', product: sunscreen, instructions: 'Apply generously (2 finger lengths) as final step - wait 15 min before sun exposure', frequency: 'daily' }
      ],
      evening: [
        { step: 1, name: 'Cleanser', product: cleanser, instructions: 'Double cleanse if wearing makeup/sunscreen - oil cleanser first, then regular', frequency: 'daily' },
        ...(serum ? [{ step: 2, name: 'Treatment/Serum', product: serum, instructions: 'Apply to clean, dry skin - less is more!', frequency: 'daily' }] : []),
        { step: serum ? 3 : 2, name: 'Moisturizer', product: moisturizer, instructions: 'Seal in actives and hydration', frequency: 'daily' }
      ],
      weekly: [
        { step: 1, name: 'Exfoliation', product: serum, instructions: 'Use a gentle exfoliant once a week to reset your skin', frequency: 'weekly' },
        { step: 2, name: 'Mask', product: moisturizer, instructions: 'Apply a hydrating or clarifying mask for 10–15 minutes', frequency: 'weekly' }
      ]
    },
    summary: `A ${profile.skinType} skin routine tailored to your ${profile.skinGoals?.[0]?.replace(/_/g, ' ') || 'skincare'} goals. ${profile.budget === 'low' ? 'Budget-friendly picks that deliver results.' : 'Quality products selected for maximum efficacy.'}`,
    tips: tips.slice(0, 3)
  };
}

/**
 * Use existing product embeddings to find similar products
 * This is a smart fallback when we can't generate new embeddings
 */
async function semanticSearchWithSeedProducts(
  keywords: string[],
  maxPrice: number,
  limit: number = 12
): Promise<ProductMatch[]> {
  console.log('🌱 Using seed-based semantic search...');
  
  // Map keywords to skin types and concerns
  const skinTypeMap: Record<string, string> = {
    'oily': 'oily', 'dry': 'dry', 'combination': 'combination',
    'sensitive': 'sensitive', 'normal': 'normal'
  };
  
  const concernTerms = ['acne', 'aging', 'pigmentation', 'dryness', 'hydration', 
    'brightening', 'texture', 'redness', 'wrinkles'];
  
  // Find matching skin type
  const matchingSkinType = keywords.find(k => skinTypeMap[k.toLowerCase()]);
  const matchingConcerns = keywords.filter(k => 
    concernTerms.some(c => k.toLowerCase().includes(c))
  );
  
  // Step 1: Find seed products that match user's profile
  // Only search skincare categories, not hair products
  let seedQuery = supabase
    .from('products')
    .select('id, embedding, name, category')
    .not('embedding', 'is', null)
    .in('category', SKINCARE_CATEGORIES)
    .order('rating', { ascending: false })
    .limit(5);
  
  // Filter by skin type if provided
  if (matchingSkinType) {
    seedQuery = seedQuery.contains('target_skin_type', [matchingSkinType]);
  }
  
  const { data: seedProducts, error: seedError } = await seedQuery;
  
  if (seedError) {
    console.error('Seed search error:', seedError);
    return [];
  }
  
  if (!seedProducts || seedProducts.length === 0) {
    console.log('⚠️ No seed products found');
    return [];
  }
  
  console.log(`🌱 Found ${seedProducts.length} seed products:`, seedProducts.map(p => p.name).slice(0, 3));
  
  // Step 2: Use the first seed product's embedding to find similar products
  const seedEmbedding = seedProducts[0].embedding;
  
  if (!seedEmbedding) {
    console.log('⚠️ Seed product has no embedding');
    return [];
  }
  
  // Step 3: Call match_products with the seed embedding
  const { data: similarProducts, error: matchError } = await supabase.rpc('match_products', {
    query_embedding: seedEmbedding,
    match_threshold: 0.4,
    match_count: limit * 3
  });
  
  if (matchError) {
    console.error('Match products error:', matchError);
    return [];
  }
  
  // Filter by price, category, and exclude the seed products
  const seedIds = new Set(seedProducts.map(p => p.id));
  
  const filteredProducts = (similarProducts || [])
    .filter((p: any) => {
      // Exclude seed products
      if (seedIds.has(p.id)) return false;
      // Apply price filter
      if (p.price > maxPrice) return false;
      // Only include skincare categories
      if (p.category && !SKINCARE_CATEGORIES.some(cat => p.category.toLowerCase().includes(cat))) return false;
      return true;
    });
  
  console.log(`✅ Semantic search found ${filteredProducts.length} skincare products (filtered from ${similarProducts?.length || 0})`);
  
  return filteredProducts.slice(0, limit).map((p: any) => ({
    id: p.id,
    name: p.name,
    brand: p.brand,
    price: p.price,
    category: p.category,
    description: p.description || '',
    image_url: p.image_url,
    rating: p.rating || 4.0,
    similarity: p.similarity
  }));
}

/**
 * Main inference function - takes user profile and returns personalized recommendations
 */
export async function runInference(profile: UserProfileForInference): Promise<InferenceResult> {
  console.log(`🧠 Starting inference for profile: ${profile.skinType} (model: ${GLOWUP_MODEL})`);
  
  // Determine max price from budget
  const maxPrice = profile.budget === 'low' ? 25 : profile.budget === 'medium' ? 60 : 200;
  
  // Build search queries
  const skinQuery = buildProfileQuery(profile);
  
  console.log('🔍 Skin query:', skinQuery);
  
  // Extract keywords for hybrid search
  const keywords: string[] = [
    profile.skinType,
    ...(profile.skinConcerns || []),
    ...(profile.skinGoals || []),
    profile.fragranceFree ? 'fragrance-free' : ''
  ].filter(Boolean);
  
  let skincareProducts: ProductMatch[] = [];
  
  // Strategy 1: Try to generate embedding for semantic search (requires OpenAI)
  const skinEmbedding = await generateEmbedding(skinQuery);
  
  if (skinEmbedding) {
    console.log('📦 Searching with OpenAI-generated embeddings...');
    skincareProducts = await hybridSearch(
      skinEmbedding, 
      keywords,
      undefined,
      maxPrice,
      12
    );
  }
  
  // Strategy 2: Use existing product embeddings for semantic search
  if (skincareProducts.length < 6) {
    console.log('📦 Trying seed-based semantic search...');
    const semanticResults = await semanticSearchWithSeedProducts(keywords, maxPrice, 12);
    
    // Merge results, avoiding duplicates
    const existingIds = new Set(skincareProducts.map(p => p.id));
    for (const p of semanticResults) {
      if (!existingIds.has(p.id)) {
        skincareProducts.push(p);
      }
    }
  }
  
  // Strategy 3: Smart keyword/tag-based search
  if (skincareProducts.length < 6) {
    console.log('📦 Using smart tag-based search...');
    const tagResults = await fallbackSearch(keywords, undefined, maxPrice, 12);
    
    // Merge results, avoiding duplicates
    const existingIds = new Set(skincareProducts.map(p => p.id));
    for (const p of tagResults) {
      if (!existingIds.has(p.id)) {
        skincareProducts.push(p);
      }
    }
  }
  
  // Ensure we have products across key categories
  const categories = new Set(skincareProducts.map(p => p.category));
  const essentialCategories = ['cleanser', 'moisturizer', 'sunscreen', 'treatment', 'serum'];
  
  for (const cat of essentialCategories) {
    if (!categories.has(cat) && skincareProducts.length < 15) {
      // Fetch a top-rated product from this category
      const { data: catProducts } = await supabase
        .from('products')
        .select('*')
        .eq('category', cat)
        .lte('price', maxPrice)
        .order('rating', { ascending: false })
        .limit(2);
      
      if (catProducts && catProducts.length > 0) {
        for (const p of catProducts) {
          if (!skincareProducts.find(sp => sp.id === p.id)) {
            skincareProducts.push({
              id: p.id,
              name: p.name,
              brand: p.brand,
              price: p.price,
              category: p.category,
              description: p.summary || '',
              image_url: p.image_url,
              rating: p.rating || 4.0,
              similarity: 0.7,
              buy_link: p.buy_link,
            });
            break;
          }
        }
      }
    }
  }
  
  console.log(`✅ Found ${skincareProducts.length} matching products`);
  
  // Generate personalized routine
  console.log('🤖 Generating personalized routine...');
  const { routine, summary, tips } = await generatePersonalizedRoutine(profile, skincareProducts);
  
  return {
    products: skincareProducts,
    routine,
    summary,
    personalized_tips: tips
  };
}

/**
 * Check if LLM inference is available
 */
export function isLLMAvailable(): boolean {
  return openai !== null;
}

/**
 * Create the Postgres function for vector similarity search
 * Run this once to set up the function
 */
export const MATCH_PRODUCTS_FUNCTION = `
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
    p.description,
    p.image_url,
    p.rating,
    1 - (p.embedding <=> query_embedding) as similarity
  FROM products p
  WHERE p.embedding IS NOT NULL
    AND 1 - (p.embedding <=> query_embedding) > match_threshold
  ORDER BY similarity DESC
  LIMIT match_count;
END;
$$;
`;

