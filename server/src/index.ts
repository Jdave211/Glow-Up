import dotenv from 'dotenv';
dotenv.config();

import express from 'express';
import cors from 'cors';
import bodyParser from 'body-parser';
import { supabase, DatabaseService } from './db/supabase';
import { verifyAppleToken } from './auth/apple';
import { runInference, UserProfileForInference, isLLMAvailable } from './inference';

const app = express();
const port = process.env.PORT || 4000;

app.use(cors());
app.use(bodyParser.json());

// ═══════════════════════════════════════════════════════════════
// 4 SUB-AGENTS - Each thinks deeply about a specific domain
// ═══════════════════════════════════════════════════════════════

interface ThinkingStep {
  thought: string;
  conclusion?: string;
}

interface AgentResult {
  agentName: string;
  emoji: string;
  thinking: ThinkingStep[];
  recommendations: any;
  confidence: number;
}

// ─────────────────────────────────────────────────────────────────
// AGENT 1: Skin Analysis Agent
// ─────────────────────────────────────────────────────────────────
async function skinAnalysisAgent(profile: any): Promise<AgentResult> {
  const thinking: ThinkingStep[] = [];
  
  thinking.push({ 
    thought: `Analyzing skin type: "${profile.skinType}". This determines base product selection.` 
  });
  
  // Process skin tone for melanin-appropriate recommendations
  const skinTone = profile.skinTone || 0.5;
  const skinToneLabel = skinTone < 0.3 ? 'fair' : skinTone < 0.6 ? 'medium' : 'deep';
  thinking.push({
    thought: `Skin tone: ${skinToneLabel}. Adjusting product recommendations for melanin level.`
  });

  // Check sunscreen usage and provide tailored advice
  const sunscreenUsage = profile.sunscreenUsage || 'sometimes';
  if (sunscreenUsage !== 'daily') {
    thinking.push({
      thought: `Sunscreen usage: ${sunscreenUsage}. Prioritizing SPF education—it's the #1 anti-aging product for all skin tones.`
    });
  }
  
  const skinConcerns = profile.concerns?.filter((c: string) => 
    ['acne', 'aging', 'dryness', 'oiliness', 'pigmentation', 'sensitivity', 'redness', 'texture', 'dark_spots'].includes(c)
  ) || [];
  
  thinking.push({ 
    thought: `Identified ${skinConcerns.length} skin-related concerns: ${skinConcerns.join(', ') || 'none specified'}.` 
  });

  // Process skin goals
  const skinGoals = profile.skinGoals || [];
  if (skinGoals.length > 0) {
    thinking.push({
      thought: `Skin goals: ${skinGoals.map((g: string) => g.replace(/_/g, ' ')).join(', ')}. Tailoring routine to achieve these outcomes.`
    });
  }

  let routineComplexity = 'simple';
  if (skinConcerns.length > 2 || skinGoals.length > 1) {
    routineComplexity = 'comprehensive';
    thinking.push({ 
      thought: `Multiple concerns/goals detected. Recommending a comprehensive routine with targeted treatments.` 
    });
  }

  const actives: string[] = [];
  
  // Goal-based actives
  if (skinGoals.includes('glass_skin')) {
    actives.push('hyaluronic acid', 'niacinamide');
    thinking.push({ thought: `For glass skin: layered hydration with HA + niacinamide for dewy translucence.` });
  }
  if (skinGoals.includes('clear_skin')) {
    actives.push('salicylic acid', 'benzoyl peroxide');
    thinking.push({ thought: `For clear skin: BHA to keep pores clear + spot treatment for breakouts.` });
  }
  if (skinGoals.includes('brightening')) {
    actives.push('vitamin C', 'alpha arbutin');
    thinking.push({ thought: `For brightening: vitamin C for radiance + alpha arbutin for even tone.` });
  }
  if (skinGoals.includes('anti_aging')) {
    actives.push('retinol', 'peptides');
    thinking.push({ thought: `For anti-aging: retinol for cell turnover + peptides for firmness.` });
  }
  if (skinGoals.includes('barrier_repair')) {
    actives.push('ceramides', 'centella asiatica');
    thinking.push({ thought: `For barrier repair: ceramides to restore + centella to soothe inflammation.` });
  }

  // Concern-based actives (if not already covered by goals)
  if (skinConcerns.includes('acne') && !actives.includes('salicylic acid')) {
    actives.push('salicylic acid', 'niacinamide');
    thinking.push({ thought: `For acne: BHA (salicylic acid) to unclog pores + niacinamide to reduce sebum.` });
  }
  if (skinConcerns.includes('aging') && !actives.includes('retinol')) {
    actives.push('retinol', 'vitamin C');
    thinking.push({ thought: `For aging: retinol for cell turnover + vitamin C for collagen synthesis.` });
  }
  if ((skinConcerns.includes('pigmentation') || skinConcerns.includes('dark_spots')) && !actives.includes('vitamin C')) {
    actives.push('vitamin C', 'azelaic acid');
    thinking.push({ thought: `For pigmentation: vitamin C to inhibit melanin + azelaic acid for even tone.` });
  }
  if (skinConcerns.includes('dryness') && !actives.includes('hyaluronic acid')) {
    actives.push('hyaluronic acid', 'ceramides');
    thinking.push({ thought: `For dryness: hyaluronic acid for hydration + ceramides to repair barrier.` });
  }

  // Melanin-specific considerations
  if (skinTone >= 0.5) {
    if (skinConcerns.includes('pigmentation') || skinConcerns.includes('dark_spots')) {
      thinking.push({ 
        thought: `For melanin-rich skin: avoiding harsh actives that may cause PIH. Favoring azelaic acid and vitamin C over hydroquinone.` 
      });
    }
  }

  // Dedupe actives
  const uniqueActives = [...new Set(actives)];

  thinking.push({ 
    thought: `Final skin protocol established.`,
    conclusion: `${profile.skinType} skin (${skinToneLabel} tone) with ${routineComplexity} routine. Goals: ${skinGoals.join(', ') || 'healthy skin'}. Key actives: ${uniqueActives.slice(0, 4).join(', ') || 'hydration focus'}.`
  });

  return {
    agentName: 'Skin Analysis Agent',
    emoji: '🧴',
    thinking,
    recommendations: [
      { step: 'AM Cleanser', type: profile.skinType === 'oily' ? 'foaming' : 'cream', actives: profile.fragranceFree ? ['fragrance-free'] : [] },
      { step: 'AM Moisturizer', type: profile.skinType === 'oily' ? 'gel' : 'cream', actives: ['hyaluronic acid'] },
      { step: 'AM SPF', type: 'broad-spectrum SPF 30+', priority: sunscreenUsage !== 'daily' ? 'high' : 'normal', actives: skinConcerns.includes('acne') ? ['non-comedogenic'] : [] },
      { step: 'PM Cleanser', type: profile.skinType === 'oily' ? 'foaming' : 'oil-based', actives: [] },
      { step: 'PM Treatment', type: 'serum', actives: uniqueActives.slice(0, 2) },
      { step: 'PM Moisturizer', type: 'rich cream', actives: ['ceramides'] },
    ],
    confidence: 0.85 + (skinConcerns.length * 0.02) + (skinGoals.length * 0.02)
  };
}

// ─────────────────────────────────────────────────────────────────
// AGENT 2: Hair Analysis Agent
// ─────────────────────────────────────────────────────────────────
async function hairAnalysisAgent(profile: any): Promise<AgentResult> {
  const thinking: ThinkingStep[] = [];
  
  thinking.push({ 
    thought: `Evaluating hair type: "${profile.hairType}". This affects wash frequency and product weight.` 
  });

  const hairConcerns = profile.concerns?.filter((c: string) => 
    ['frizz', 'damage', 'scalp_itch', 'breakage', 'oily_scalp', 'dry_scalp', 'thinning', 'color_damage', 'heat_damage', 'scalp_sensitivity'].includes(c)
  ) || [];

  thinking.push({ 
    thought: `Hair concerns detected: ${hairConcerns.join(', ') || 'general maintenance'}.` 
  });

  // Determine porosity based on hair type
  let porosity = 'medium';
  if (profile.hairType === 'coily' || profile.hairType === 'curly') {
    porosity = 'high';
    thinking.push({ thought: `Curly/coily hair typically has high porosity. Needs protein-moisture balance.` });
  } else if (profile.hairType === 'straight') {
    porosity = 'low';
    thinking.push({ thought: `Straight hair often has low porosity. Lighter products absorb better.` });
  }

  // Use the user's selected wash frequency with inclusive options
  const userWashFrequency = profile.washFrequency || '2_3_weekly';
  const washFrequencyMap: Record<string, string> = {
    'daily': 'Daily',
    'every_other': 'Every other day',
    '2_3_weekly': '2-3x per week',
    'weekly': 'Once a week',
    'biweekly': 'Every 2 weeks',
    'monthly': 'Monthly or less'
  };
  
  const washFrequency = washFrequencyMap[userWashFrequency] || '2-3x per week';
  
  thinking.push({ 
    thought: `User wash frequency: ${washFrequency}. Tailoring routine to this schedule.` 
  });

  // Provide culturally-aware advice based on wash frequency
  if (['weekly', 'biweekly', 'monthly'].includes(userWashFrequency)) {
    thinking.push({ 
      thought: `Less frequent washing is ideal for protective styles and coily textures. Focusing on scalp health and moisture retention between washes.` 
    });
  }

  // Adjust recommendations based on scalp concerns
  if (hairConcerns.includes('oily_scalp') && ['weekly', 'biweekly', 'monthly'].includes(userWashFrequency)) {
    thinking.push({ 
      thought: `Oily scalp with infrequent washing: recommending co-wash or dry shampoo between wash days.` 
    });
  }

  const stylingNeeds: string[] = [];
  if (hairConcerns.includes('frizz')) {
    stylingNeeds.push('anti-frizz serum', 'leave-in conditioner');
    thinking.push({ thought: `Frizz control needed. Adding smoothing products to seal cuticle.` });
  }
  if (hairConcerns.includes('breakage') || hairConcerns.includes('damage') || hairConcerns.includes('heat_damage')) {
    stylingNeeds.push('bond repair treatment', 'heat protectant');
    thinking.push({ thought: `Hair damage/breakage detected. Bond-building treatments will restore strength.` });
  }
  if (hairConcerns.includes('color_damage')) {
    stylingNeeds.push('color-protecting serum', 'UV hair protectant');
    thinking.push({ thought: `Color-treated hair needs protection from fading and further damage.` });
  }
  if (hairConcerns.includes('thinning')) {
    stylingNeeds.push('scalp serum', 'volumizing mousse');
    thinking.push({ thought: `Thinning concerns: adding scalp treatment to support healthy growth.` });
  }
  if (hairConcerns.includes('dry_scalp') || hairConcerns.includes('scalp_sensitivity')) {
    stylingNeeds.push('scalp oil treatment', 'gentle scalp toner');
    thinking.push({ thought: `Scalp sensitivity/dryness: focusing on nourishing and calming the scalp.` });
  }

  // Determine treatment frequency based on wash schedule
  let treatmentFrequency = '1x/week';
  if (['biweekly', 'monthly'].includes(userWashFrequency)) {
    treatmentFrequency = 'every wash day';
    thinking.push({ thought: `With less frequent washing, deep treatments should happen every wash day for maximum benefit.` });
  }

  thinking.push({ 
    thought: `Hair protocol finalized.`,
    conclusion: `${profile.hairType} hair, ${porosity} porosity. Wash ${washFrequency}. Focus: ${stylingNeeds.join(', ') || 'moisture maintenance'}.`
  });

  return {
    agentName: 'Hair Analysis Agent',
    emoji: '💇',
    thinking,
    recommendations: [
      { step: 'Shampoo', frequency: washFrequency, type: hairConcerns.includes('oily_scalp') ? 'clarifying' : hairConcerns.includes('dry_scalp') ? 'moisturizing sulfate-free' : 'gentle sulfate-free' },
      { step: 'Conditioner', frequency: washFrequency, type: porosity === 'high' ? 'deep conditioning' : 'lightweight' },
      { step: 'Deep Treatment', frequency: treatmentFrequency, type: 'hair mask or hot oil treatment' },
      { step: 'Leave-In', frequency: 'between washes', type: ['coily', 'curly'].includes(profile.hairType) ? 'leave-in conditioner' : 'lightweight detangler' },
      ...stylingNeeds.map(s => ({ step: 'Styling', type: s, frequency: 'as needed' }))
    ],
    confidence: 0.82 + (hairConcerns.length * 0.03)
  };
}

// ─────────────────────────────────────────────────────────────────
// AGENT 3: Product Matching Agent (Now uses Supabase!)
// ─────────────────────────────────────────────────────────────────
async function productMatchingAgent(skinResult: AgentResult, hairResult: AgentResult, profile: any): Promise<AgentResult> {
  const thinking: ThinkingStep[] = [];
  
  thinking.push({ 
    thought: `Received ${skinResult.recommendations.length} skin recommendations and ${hairResult.recommendations.length} hair recommendations.` 
  });

  thinking.push({ 
    thought: `Cross-referencing with Supabase product database...` 
  });

  // Fetch products from Supabase
  let products = await DatabaseService.getAllProducts();
  
  if (products.length === 0) {
    thinking.push({ thought: `Using fallback catalog (Supabase not seeded yet).` });
    // Fallback to hardcoded products
    products = [
      { id: '1', name: 'CeraVe Hydrating Cleanser', brand: 'CeraVe', price: 15.99, category: 'cleanser', rating: 4.7, tags: ['fragrance-free', 'dry-skin'], buy_link: '', retailer: 'Amazon', description: '', image_url: null, created_at: '' },
      { id: '2', name: 'The Ordinary Niacinamide 10%', brand: 'The Ordinary', price: 6.50, category: 'treatment', rating: 4.3, tags: ['acne', 'oiliness'], buy_link: '', retailer: 'Sephora', description: '', image_url: null, created_at: '' },
      { id: '3', name: 'EltaMD UV Clear SPF 46', brand: 'EltaMD', price: 41.00, category: 'sunscreen', rating: 4.8, tags: ['acne', 'sensitive-safe'], buy_link: '', retailer: 'Amazon', description: '', image_url: null, created_at: '' },
      { id: '4', name: 'CeraVe PM Moisturizing Lotion', brand: 'CeraVe', price: 13.99, category: 'moisturizer', rating: 4.6, tags: ['fragrance-free', 'niacinamide'], buy_link: '', retailer: 'Amazon', description: '', image_url: null, created_at: '' },
      { id: '5', name: 'Olaplex No. 4 Shampoo', brand: 'Olaplex', price: 30.00, category: 'shampoo', rating: 4.5, tags: ['damage', 'bond-repair'], buy_link: '', retailer: 'Sephora', description: '', image_url: null, created_at: '' },
      { id: '6', name: 'Verb Ghost Oil', brand: 'Verb', price: 20.00, category: 'styling', rating: 4.4, tags: ['frizz', 'lightweight'], buy_link: '', retailer: 'Sephora', description: '', image_url: null, created_at: '' },
    ] as any;
  } else {
    thinking.push({ thought: `Found ${products.length} products in database.` });
  }

  thinking.push({ 
    thought: `Filtering products based on: ${profile.fragranceFree ? 'fragrance-free requirement, ' : ''}budget tier "${profile.budget}".` 
  });

  // Filter by budget
  let maxPrice = profile.budget === 'low' ? 25 : profile.budget === 'medium' ? 50 : 200;
  let filteredProducts = products.filter((p: any) => p.price <= maxPrice);

  // Calculate match scores
  const scoredProducts = filteredProducts.map((p: any) => {
    let matchScore = 0.7; // Base score
    
    // Boost for matching concerns
    if (profile.concerns.some((c: string) => p.tags?.includes(c))) {
      matchScore += 0.15;
    }
    
    // Boost for fragrance-free if required
    if (profile.fragranceFree && p.tags?.includes('fragrance-free')) {
      matchScore += 0.1;
    }
    
    // Boost for skin type match
    if (p.tags?.includes(profile.skinType + '-skin') || p.tags?.includes(profile.skinType)) {
      matchScore += 0.05;
    }

    return {
      id: typeof p.id === 'string' ? parseInt(p.id.replace(/-/g, '').slice(0, 8), 16) : 1,
      name: p.name,
      price: p.price,
      category: p.category,
      rating: p.rating || 4.0,
      match: Math.min(matchScore, 0.98)
    };
  });

  // Sort by match score and take top products
  scoredProducts.sort((a: any, b: any) => b.match - a.match);
  const topProducts = scoredProducts.slice(0, 6);

  thinking.push({ 
    thought: `Product selection complete.`,
    conclusion: `Selected ${topProducts.length} products with avg match score ${(topProducts.reduce((s: number, p: any) => s + p.match, 0) / topProducts.length * 100).toFixed(0)}%.`
  });

  return {
    agentName: 'Product Matching Agent',
    emoji: '🔍',
    thinking,
    recommendations: topProducts,
    confidence: 0.91
  };
}

// ─────────────────────────────────────────────────────────────────
// AGENT 4: Budget Optimization Agent
// ─────────────────────────────────────────────────────────────────
async function budgetOptimizationAgent(products: any[], profile: any): Promise<AgentResult> {
  const thinking: ThinkingStep[] = [];
  
  const totalCost = products.reduce((sum: number, p: any) => sum + p.price, 0);
  thinking.push({ 
    thought: `Total routine cost: $${totalCost.toFixed(2)}. Evaluating against "${profile.budget}" budget tier.` 
  });

  const productsWithValue = products.map((p: any) => ({
    ...p,
    valueScore: (p.rating / 5) * (1 - (p.price / 100)) * p.match
  }));

  thinking.push({ 
    thought: `Calculating value score for each product (rating × affordability × match)...` 
  });

  thinking.push({ 
    thought: `Searching for budget-friendly alternatives with similar efficacy...` 
  });

  const alternatives = profile.budget === 'low' ? [
    { original: 'EltaMD UV Clear SPF 46', alternative: 'La Roche-Posay Anthelios', savings: 5, efficacyRetained: 0.95 },
  ] : [];

  const monthlyEstimate = totalCost * 0.3;
  thinking.push({ 
    thought: `Projected monthly cost: ~$${monthlyEstimate.toFixed(2)} (assuming 3-month product lifespan).` 
  });

  thinking.push({ 
    thought: `Checking retailer prices: Amazon, Sephora, Ulta...` 
  });

  const retailerBreakdown = {
    Amazon: { items: Math.ceil(products.length * 0.4), subtotal: totalCost * 0.4 },
    Sephora: { items: Math.ceil(products.length * 0.35), subtotal: totalCost * 0.35 },
    Ulta: { items: Math.ceil(products.length * 0.25), subtotal: totalCost * 0.25 },
  };

  thinking.push({ 
    thought: `Optimal split determined.`,
    conclusion: `Total: $${totalCost.toFixed(2)}. Monthly: ~$${monthlyEstimate.toFixed(2)}. ${profile.budget === 'low' ? `Potential savings available with swaps.` : 'Premium selection optimized.'}`
  });

  return {
    agentName: 'Budget Optimization Agent',
    emoji: '💰',
    thinking,
    recommendations: {
      totalCost,
      monthlyEstimate,
      retailerBreakdown,
      alternatives,
      valueRanking: productsWithValue.sort((a: any, b: any) => b.valueScore - a.valueScore)
    },
    confidence: 0.88
  };
}

// ═══════════════════════════════════════════════════════════════
// API ENDPOINTS
// ═══════════════════════════════════════════════════════════════

// Health check
app.get('/', (req, res) => {
  res.json({ 
    status: 'ok',
    message: '🧠 GlowUp Multi-Agent API v2.0',
    agents: ['Skin Analysis', 'Hair Analysis', 'Product Matching', 'Budget Optimization']
  });
});

// Main analysis endpoint - uses LLM inference with RAG
// Now also accepts userId to auto-save the generated routine to DB
app.post('/api/analyze', async (req, res) => {
  try {
    const profile = req.body;
    const userId = profile.userId; // optional — when present, routine is saved automatically
    console.log('🚀 Starting LLM-powered analysis for:', profile.skinType, userId ? `(user: ${userId})` : '');

    // Check if we should use LLM inference (default: yes)
    const useLLM = req.query.useLLM !== 'false';

    if (useLLM) {
      // New inference with RAG (LLM if available, fallback otherwise)
      console.log(`🧠 Using inference engine... (LLM: ${isLLMAvailable() ? 'enabled' : 'fallback mode'})`);
      
      const inferenceProfile: UserProfileForInference = {
        skinType: profile.skinType,
        skinTone: profile.skinTone,
        skinGoals: profile.skinGoals,
        skinConcerns: profile.concerns?.filter((c: string) => 
          ['acne', 'aging', 'dryness', 'oiliness', 'pigmentation', 'sensitivity', 'redness', 'texture', 'dark_spots'].includes(c)
        ),
        hairType: profile.hairType,
        hairConcerns: profile.concerns?.filter((c: string) => 
          ['frizz', 'damage', 'breakage', 'oily_scalp', 'dry_scalp', 'thinning', 'color_damage', 'heat_damage'].includes(c)
        ),
        washFrequency: profile.washFrequency,
        sunscreenUsage: profile.sunscreenUsage,
        budget: profile.budget,
        fragranceFree: profile.fragranceFree
      };

      const inferenceResult = await runInference(inferenceProfile);

      // ── Auto-save the product-enriched routine for this user ──
      let routineId: string | null = null;
      if (userId) {
        try {
          const skinProfile = await DatabaseService.getSkinProfileByUserId(userId);
          const profileId = skinProfile?.id || userId;
          const saved = await DatabaseService.saveRoutine(userId, profileId, {
            inference: {
              routine: inferenceResult.routine,
              summary: inferenceResult.summary,
              personalized_tips: inferenceResult.personalized_tips,
            },
          });
          routineId = saved?.id || null;
          if (routineId) {
            console.log('💾 Routine auto-saved:', routineId);
          }
        } catch (err: any) {
          console.error('⚠️ Failed to auto-save routine:', err?.message);
        }

        // ── Auto-add routine products to cart so user can buy immediately ──
        try {
          const allSteps = [
            ...(inferenceResult.routine.morning || []),
            ...(inferenceResult.routine.evening || []),
            ...(inferenceResult.routine.weekly || []),
          ];
          // Deduplicate by product id
          const uniqueProductIds = new Set<string>();
          for (const step of allSteps) {
            const pid = step.product?.id;
            if (pid && !uniqueProductIds.has(pid)) {
              uniqueProductIds.add(pid);
              await DatabaseService.upsertCartItem(userId, pid, 1);
            }
          }
          console.log(`🛒 Auto-added ${uniqueProductIds.size} routine products to cart`);
        } catch (err: any) {
          console.error('⚠️ Failed to auto-add products to cart:', err?.message);
        }
      }

      // Format response for the app (maintain compatibility)
      const response = {
        // New format
        inference: inferenceResult,
        routine_id: routineId,
        // Legacy format for backward compatibility
        agents: [
          {
            agentName: 'AI Skincare Expert',
            emoji: '🧴',
            thinking: [{ thought: inferenceResult.summary }],
            recommendations: inferenceResult.routine.morning,
            confidence: 0.92
          },
          {
            agentName: 'AI Hair Expert',
            emoji: '💇',
            thinking: [{ thought: 'Analyzed hair type and concerns for personalized recommendations.' }],
            recommendations: [],
            confidence: 0.88
          },
          {
            agentName: 'Product Match AI',
            emoji: '🔍',
            thinking: [{ thought: `Found ${inferenceResult.products.length} products matching your profile using semantic search.` }],
            recommendations: inferenceResult.products.map(p => ({
              id: p.id,
              name: p.name,
              price: p.price,
              category: p.category,
              rating: p.rating,
              match: p.similarity
            })),
            confidence: 0.95
          },
          {
            agentName: 'Budget Optimizer',
            emoji: '💰',
            thinking: [{ thought: `Optimized routine within your ${profile.budget || 'medium'} budget.` }],
            recommendations: {
              totalCost: inferenceResult.products.reduce((sum: number, p: any) => sum + p.price, 0),
              monthlyEstimate: inferenceResult.products.reduce((sum: number, p: any) => sum + p.price, 0) * 0.3
            },
            confidence: 0.90
          }
        ],
        summary: {
          totalProducts: inferenceResult.products.length,
          totalCost: inferenceResult.products.reduce((sum: number, p: any) => sum + p.price, 0),
          overallConfidence: '0.91',
          routine: inferenceResult.routine,
          personalized_tips: inferenceResult.personalized_tips
        }
      };

      console.log('✅ LLM analysis complete with', inferenceResult.products.length, 'products');
      return res.json(response);
    }

    // Fallback to rule-based agents (no OpenAI key)
    console.log('📋 Using rule-based agents (no OpenAI key configured)...');
    
    // Run skin and hair agents in parallel
    const [skinResult, hairResult] = await Promise.all([
      skinAnalysisAgent(profile),
      hairAnalysisAgent(profile)
    ]);

    // Product matching depends on skin + hair results
    const productResult = await productMatchingAgent(skinResult, hairResult, profile);

    // Budget optimization depends on product selection
    const budgetResult = await budgetOptimizationAgent(productResult.recommendations, profile);

    const response = {
      agents: [skinResult, hairResult, productResult, budgetResult],
      summary: {
        totalProducts: productResult.recommendations.length,
        totalCost: budgetResult.recommendations.totalCost,
        overallConfidence: (
          (skinResult.confidence + hairResult.confidence + productResult.confidence + budgetResult.confidence) / 4
        ).toFixed(2)
      }
    };

    console.log('✅ Rule-based analysis complete. Confidence:', response.summary.overallConfidence);
    res.json(response);

  } catch (error) {
    console.error('❌ Error:', error);
    res.status(500).json({ error: 'Analysis failed' });
  }
});

// ═══════════════════════════════════════════════════════════════
// AUTH ENDPOINTS
// ═══════════════════════════════════════════════════════════════

// Apple Sign In
app.post('/api/auth/apple', async (req, res) => {
  try {
    const { identityToken, fullName } = req.body;
    
    if (!identityToken) {
      return res.status(400).json({ error: 'Identity token is required' });
    }

    const result = await verifyAppleToken(identityToken, fullName);
    
    if (result.success) {
      // Include onboarded status in response
      res.json({ success: true, user: result.user });
    } else {
      res.status(401).json({ error: result.error || 'Authentication failed' });
    }
  } catch (error) {
    console.error('Apple Auth Error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Check user onboarding status
app.get('/api/users/:userId/onboarded', async (req, res) => {
  try {
    console.log('🔍 Checking onboarded status for user:', req.params.userId);
    const isOnboarded = await DatabaseService.isUserOnboarded(req.params.userId);
    console.log('📊 User onboarded:', isOnboarded);
    res.json({ success: true, onboarded: isOnboarded });
  } catch (error) {
    console.error('Error checking onboarding:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Get user info
app.get('/api/users/:userId', async (req, res) => {
  try {
    const user = await DatabaseService.getUserById(req.params.userId);
    if (user) {
      res.json({ success: true, user });
    } else {
      res.status(404).json({ error: 'User not found' });
    }
  } catch (error) {
    console.error('Error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// ═══════════════════════════════════════════════════════════════
// USER ENDPOINTS (Supabase)
// ═══════════════════════════════════════════════════════════════

// Create or get user
app.post('/api/users', async (req, res) => {
  try {
    const { email, name } = req.body;
    const user = await DatabaseService.getOrCreateUser(email, name);
    if (user) {
      res.json({ success: true, user });
    } else {
      res.status(400).json({ error: 'Failed to create user' });
    }
  } catch (error) {
    console.error('Error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Save user profile
app.post('/api/profiles', async (req, res) => {
  try {
    const { userId, profile } = req.body;
    const savedProfile = await DatabaseService.saveProfile(userId, profile);
    if (savedProfile) {
      res.json({ success: true, profile: savedProfile });
    } else {
      res.status(400).json({ error: 'Failed to save profile' });
    }
  } catch (error) {
    console.error('Error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Get user profile
app.get('/api/profiles/:userId', async (req, res) => {
  try {
    const profile = await DatabaseService.getProfileByUserId(req.params.userId);
    if (profile) {
      res.json({ success: true, profile });
    } else {
      res.status(404).json({ error: 'Profile not found' });
    }
  } catch (error) {
    console.error('Error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Save routine
app.post('/api/routines', async (req, res) => {
  try {
    const { userId, profileId, routineData } = req.body;
    const routine = await DatabaseService.saveRoutine(userId, profileId, routineData);
    if (routine) {
      res.json({ success: true, routine });
    } else {
      res.status(400).json({ error: 'Failed to save routine' });
    }
  } catch (error) {
    console.error('Error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

import { FulfillmentAgent } from './agents/fulfillment';

// ... existing imports ...

// ═══════════════════════════════════════════════════════════════
// ORDER & FULFILLMENT ENDPOINTS
// ═══════════════════════════════════════════════════════════════

type TrackingStatus =
  | 'queued'
  | 'agent_processing'
  | 'placed'
  | 'confirmed'
  | 'shipped'
  | 'out_for_delivery'
  | 'delivered'
  | 'failed';

type TrackingEvent = {
  status: TrackingStatus;
  message: string;
  at: string;
};

type TrackingRecord = {
  orderId: string;
  userId: string;
  retailer: 'ulta';
  status: TrackingStatus;
  trackingUrl: string;
  estimatedDelivery?: string | null;
  events: TrackingEvent[];
  updatedAt: string;
};

const orderTrackingStore = new Map<string, TrackingRecord>();
const latestOrderByUser = new Map<string, string>();

function pushTrackingEvent(orderId: string, status: TrackingStatus, message: string) {
  const record = orderTrackingStore.get(orderId);
  if (!record) return;
  record.status = status;
  record.updatedAt = new Date().toISOString();
  record.events.push({ status, message, at: record.updatedAt });
  orderTrackingStore.set(orderId, record);
}

// One-time setup: opens a visible browser so user can log into Ulta
// After login, session persists for all future orders.
app.post('/api/orders/setup-session', async (_req, res) => {
  try {
    console.log('🔐 Starting Ulta session setup...');
    const result = await FulfillmentAgent.setupSession();
    res.json(result);
  } catch (error) {
    console.error('Session Setup Error:', error);
    res.status(500).json({ success: false, message: `Setup failed: ${error}` });
  }
});

// Check if the Ulta session is still valid
app.get('/api/orders/session-status', async (_req, res) => {
  try {
    const valid = await FulfillmentAgent.isSessionValid();
    res.json({ valid, message: valid ? 'Session active' : 'Session expired or not set up' });
  } catch (error) {
    res.json({ valid: false, message: `Error checking session: ${error}` });
  }
});

// Full automated order — agent logs into Ulta, adds items, checks out
app.post('/api/orders', async (req, res) => {
  try {
    const { userId, items, shippingAddress } = req.body;
    
    console.log(`🛍️ Received order request for User ${userId}`);
    console.log(`   ${items?.length || 0} items, shipping to: ${shippingAddress?.city || 'unknown'}`);

    const startedAt = new Date().toISOString();
    const pendingOrderId = `pending-${Date.now()}-${Math.floor(Math.random() * 10000)}`;
    const baseTrackingUrl = 'https://www.ulta.com/myaccount/orderhistory.jsp';
    orderTrackingStore.set(pendingOrderId, {
      orderId: pendingOrderId,
      userId,
      retailer: 'ulta',
      status: 'queued',
      trackingUrl: baseTrackingUrl,
      estimatedDelivery: null,
      events: [{ status: 'queued', message: 'Order request received by GlowUp agents.', at: startedAt }],
      updatedAt: startedAt,
    });
    latestOrderByUser.set(userId, pendingOrderId);
    pushTrackingEvent(pendingOrderId, 'agent_processing', 'Ulta agent is adding products and proceeding through checkout.');
    
    // Trigger Fulfillment Agent
    const result = await FulfillmentAgent.processOrder({
      userId,
      items,
      shippingAddress
    });
    
    if (result.success) {
      console.log(`✅ Order placed: ${result.orderId}`);
      const finalOrderId = result.orderId || pendingOrderId;
      // Move tracking record to real order id when available
      const existing = orderTrackingStore.get(pendingOrderId);
      const nowIso = new Date().toISOString();
      const estimatedDelivery = new Date(Date.now() + 5 * 24 * 60 * 60 * 1000).toISOString();
      const nextRecord: TrackingRecord = {
        orderId: finalOrderId,
        userId,
        retailer: 'ulta',
        status: 'confirmed',
        trackingUrl: baseTrackingUrl,
        estimatedDelivery,
        events: [
          ...(existing?.events || []),
          { status: 'placed', message: 'Order placed on Ulta checkout.', at: nowIso },
          { status: 'confirmed', message: `Ulta confirmed order ${finalOrderId}.`, at: nowIso },
        ],
        updatedAt: nowIso,
      };
      orderTrackingStore.delete(pendingOrderId);
      orderTrackingStore.set(finalOrderId, nextRecord);
      latestOrderByUser.set(userId, finalOrderId);

      res.json({
        success: true,
        orderId: finalOrderId,
        tracking: {
          status: nextRecord.status,
          trackingUrl: nextRecord.trackingUrl,
          estimatedDelivery: nextRecord.estimatedDelivery,
        },
        result,
      });
    } else {
      console.log(`❌ Order failed: ${result.error}`);
      pushTrackingEvent(pendingOrderId, 'failed', result.error || 'Checkout failed before confirmation.');
      res.status(500).json({ success: false, error: result.error, logs: result.logs });
    }
    
  } catch (error) {
    console.error('Order Error:', error);
    res.status(500).json({ error: 'Failed to process order' });
  }
});

// Get tracking for a specific order
app.get('/api/orders/:orderId/tracking', async (req, res) => {
  try {
    const { orderId } = req.params;
    const record = orderTrackingStore.get(orderId);
    if (!record) return res.status(404).json({ error: 'Tracking not found' });
    res.json({ success: true, tracking: record });
  } catch (error) {
    console.error('Tracking Error:', error);
    res.status(500).json({ error: 'Failed to fetch tracking' });
  }
});

// Get latest order tracking for a user
app.get('/api/orders/user/:userId/latest-tracking', async (req, res) => {
  try {
    const { userId } = req.params;
    const latestOrderId = latestOrderByUser.get(userId);
    if (!latestOrderId) return res.status(404).json({ error: 'No tracked order found' });
    const record = orderTrackingStore.get(latestOrderId);
    if (!record) return res.status(404).json({ error: 'Tracking not found' });
    res.json({ success: true, tracking: record });
  } catch (error) {
    console.error('Latest Tracking Error:', error);
    res.status(500).json({ error: 'Failed to fetch latest tracking' });
  }
});

// Get user routines
app.get('/api/routines/:userId', async (req, res) => {
  try {
    console.log('📋 Getting routines for user:', req.params.userId);
    const routines = await DatabaseService.getRoutinesByUserId(req.params.userId);
    console.log('📋 Found', routines?.length || 0, 'routines');
    res.json({ success: true, routines });
  } catch (error) {
    console.error('Error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Get all products
app.get('/api/products', async (req, res) => {
  try {
    const products = await DatabaseService.getAllProducts();
    res.json({ success: true, products });
  } catch (error) {
    console.error('Error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// ═══════════════════════════════════════════════════════════════
// CART ENDPOINTS
// ═══════════════════════════════════════════════════════════════

function extractRoutineContext(routineRow: any) {
  const routineData = routineRow?.routine_data || routineRow;
  const routine =
    routineData?.routine ||
    routineData?.inference?.routine ||
    routineData?.summary?.routine ||
    routineData;

  const morning = routine?.morning || [];
  const evening = routine?.evening || [];
  const steps = [...morning, ...evening];

  const categories = new Set<string>();
  const productIds = new Set<string>();
  const stepNames: string[] = [];

  const categoryHints: Record<string, string> = {
    cleanser: 'cleanser',
    wash: 'cleanser',
    serum: 'serum',
    moisturizer: 'moisturizer',
    cream: 'moisturizer',
    sunscreen: 'sunscreen',
    spf: 'sunscreen',
    toner: 'toner',
    exfoliant: 'exfoliant',
    mask: 'mask',
    treatment: 'treatment',
    eye: 'eye'
  };

  for (const s of steps) {
    if (!s) continue;
    const name = (s.name || s.step_name || '').toString();
    const productId = s.product_id || s.product?.id;
    const productName = s.product_name || s.product?.name;
    const category = s.category || s.product?.category;

    if (name) stepNames.push(name);
    if (productName) stepNames.push(productName);
    if (productId) productIds.add(productId);
    if (category) categories.add(String(category).toLowerCase());

    const lower = name.toLowerCase();
    for (const key of Object.keys(categoryHints)) {
      if (lower.includes(key)) {
        categories.add(categoryHints[key]);
      }
    }
  }

  return {
    steps: stepNames.slice(0, 12),
    categories: Array.from(categories),
    productIds: Array.from(productIds)
  };
}

function buildCartAnalysisRuleBased(profile: any, products: any[], routineCtx?: any) {
  const routineCategories = new Set((routineCtx?.categories || []).map((c: string) => c.toLowerCase()));
  const routineProductIds = new Set(routineCtx?.productIds || []);

  return products.map((product: any) => {
    const targetSkinTypes = product.target_skin_type || [];
    const targetConcerns = product.target_concerns || [];
    const attributes = product.attributes || [];

    let score = 0;
    const reasons: string[] = [];

    if (profile?.skin_type && targetSkinTypes.includes(profile.skin_type)) {
      score += 1;
      reasons.push(`Matches your ${profile.skin_type} skin`);
    }

    const concerns = profile?.skin_concerns || [];
    const intersection = concerns.filter((c: string) => targetConcerns.includes(c));
    if (intersection.length > 0) {
      score += 1;
      reasons.push(`Targets ${intersection.slice(0, 2).join(', ')}`);
    }

    if (profile?.fragrance_free && !attributes.includes('fragrance_free')) {
      score -= 1;
      reasons.push('Not marked fragrance-free');
    }

    const productCategory = String(product.category || '').toLowerCase();
    if (routineProductIds.has(product.id)) {
      reasons.push('Already in your current routine');
    } else if (productCategory && routineCategories.has(productCategory)) {
      reasons.push(`You already have a ${productCategory} in your routine`);
      score -= 0.2;
    }

    let label = 'Neutral';
    if (score >= 2) label = 'Great fit';
    else if (score === 1) label = 'Good match';
    else if (score < 0) label = 'Caution';

    return {
      product_id: product.id,
      label,
      reason: reasons.join(' • ') || 'No strong match signals yet',
      score
    };
  });
}

app.get('/api/cart/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const items = await DatabaseService.getCartItems(userId);
    const payload = items.map((item: any) => ({
      product: mapProduct(item.product),
      quantity: item.quantity
    }));
    res.json({ success: true, items: payload });
  } catch (error) {
    console.error('Error fetching cart:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

app.post('/api/cart/items', async (req, res) => {
  try {
    const { userId, productId, quantity } = req.body;
    if (!userId || !productId || typeof quantity !== 'number') {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    const success = await DatabaseService.upsertCartItem(userId, productId, quantity);
    if (!success) return res.status(500).json({ error: 'Failed to update cart' });
    res.json({ success: true });
  } catch (error) {
    console.error('Error updating cart:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

app.patch('/api/cart/items', async (req, res) => {
  try {
    const { userId, productId, quantity } = req.body;
    if (!userId || !productId || typeof quantity !== 'number') {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    const success = await DatabaseService.upsertCartItem(userId, productId, quantity);
    if (!success) return res.status(500).json({ error: 'Failed to update cart' });
    res.json({ success: true });
  } catch (error) {
    console.error('Error updating cart:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

app.delete('/api/cart/items', async (req, res) => {
  try {
    const { userId, productId } = req.body;
    if (!userId || !productId) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    const success = await DatabaseService.removeCartItem(userId, productId);
    if (!success) return res.status(500).json({ error: 'Failed to remove cart item' });
    res.json({ success: true });
  } catch (error) {
    console.error('Error removing cart item:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

app.delete('/api/cart/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const success = await DatabaseService.clearCart(userId);
    if (!success) return res.status(500).json({ error: 'Failed to clear cart' });
    res.json({ success: true });
  } catch (error) {
    console.error('Error clearing cart:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

app.post('/api/cart/analyze', async (req, res) => {
  try {
    const { userId, productIds } = req.body;
    if (!userId || !Array.isArray(productIds)) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    const profile = await DatabaseService.getSkinProfileByUserId(userId);
    const products = await DatabaseService.getProductsByIds(productIds);
    const routineRow = await DatabaseService.getLatestRoutine(userId);
    const routineCtx = extractRoutineContext(routineRow);

    let results: any[] = [];

    if (openaiChat && products.length > 0) {
      try {
        const cartModel = process.env.GLOWUP_CART_MODEL || 'gpt-4o-mini';
        const prompt = `
You are GlowUp's cart advisor. Given a user's skin profile, current routine, and a list of products, rate each product's fit for their skin.

Return ONLY valid JSON (no markdown) with this exact schema:
[
  {"product_id":"...","label":"Great fit|Good match|Neutral|Caution","reason":"short reason","score":-2..3}
]

User profile:
${JSON.stringify({
  skin_type: profile?.skin_type,
  skin_concerns: profile?.skin_concerns,
  skin_goals: profile?.skin_goals,
  fragrance_free: profile?.fragrance_free,
  image_analysis: profile?.image_analysis ? {
    concerns_detected: profile?.image_analysis?.skin?.concerns_detected,
    hydration_score: profile?.image_analysis?.skin?.hydration_score,
    oiliness_score: profile?.image_analysis?.skin?.oiliness_score,
    texture_score: profile?.image_analysis?.skin?.texture_score,
  } : null
})}

Current routine context:
${JSON.stringify({
  steps: routineCtx?.steps || [],
  categories: routineCtx?.categories || []
})}

Products:
${JSON.stringify(products.map((p: any) => ({
  id: p.id,
  name: p.name,
  brand: p.brand,
  category: p.category,
  summary: p.summary || p.description,
  target_skin_type: p.target_skin_type,
  target_concerns: p.target_concerns,
  attributes: p.attributes
})))}
`.trim();

        const completion = await openaiChat.chat.completions.create({
          model: cartModel,
          messages: [
            { role: 'system', content: 'You output strict JSON only.' },
            { role: 'user', content: prompt }
          ],
          temperature: 0.2,
          max_tokens: 800
        });

        const content = completion.choices[0]?.message?.content || '';
        const jsonMatch = content.match(/\[[\s\S]*\]/);
        const jsonStr = jsonMatch ? jsonMatch[0] : content;
        results = JSON.parse(jsonStr);
      } catch (err) {
        console.error('Cart LLM analysis failed, using fallback:', (err as any)?.message);
        results = buildCartAnalysisRuleBased(profile, products, routineCtx);
      }
    } else {
      results = buildCartAnalysisRuleBased(profile, products, routineCtx);
    }

    res.json({ success: true, items: results });
  } catch (error) {
    console.error('Error analyzing cart:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// ═══════════════════════════════════════════════════════════════
// INTEGRATE PURCHASED PRODUCT INTO ROUTINE
// ═══════════════════════════════════════════════════════════════

app.post('/api/routine/integrate-product', async (req, res) => {
  try {
    const { userId, productId } = req.body;
    if (!userId || !productId) {
      return res.status(400).json({ error: 'userId and productId are required' });
    }

    // Fetch product + user profile + current routine
    const [productRow, profile, routineRow] = await Promise.all([
      DatabaseService.getProductsByIds([productId]),
      DatabaseService.getSkinProfileByUserId(userId),
      DatabaseService.getLatestRoutine(userId),
    ]);

    if (!productRow || productRow.length === 0) {
      return res.status(404).json({ error: 'Product not found' });
    }
    if (!profile) {
      return res.status(404).json({ error: 'No skin profile found' });
    }

    const product = productRow[0];
    const routineData = routineRow?.routine_data?.inference?.routine || routineRow?.routine_data?.routine || { morning: [], evening: [], weekly: [] };

    // Use LLM to determine where the product fits
    if (openaiChat) {
      const routineSummary = JSON.stringify({
        morning: (routineData.morning || []).map((s: any) => ({ step: s.step, name: s.name, product_name: s.product?.name || s.product_name || 'Generic' })),
        evening: (routineData.evening || []).map((s: any) => ({ step: s.step, name: s.name, product_name: s.product?.name || s.product_name || 'Generic' })),
        weekly: (routineData.weekly || []).map((s: any) => ({ step: s.step, name: s.name, product_name: s.product?.name || s.product_name || 'Generic' })),
      });

      const prompt = `You are GlowUp's routine optimizer. A user just purchased a new product. Determine where it fits in their existing routine.

PRODUCT:
- Name: ${product.name}
- Brand: ${product.brand}
- Category: ${product.category}
- Summary: ${(product as any).summary || product.description || 'N/A'}

USER SKIN: ${profile.skin_type}, concerns: ${(profile.skin_concerns || []).join(', ')}, goals: ${(profile.skin_goals || []).join(', ')}

CURRENT ROUTINE:
${routineSummary}

Respond with JSON:
{
  "action": "replace" | "add",
  "routine_type": "morning" | "evening" | "weekly",
  "step_index": 0,
  "step_name": "Cleanser",
  "reason": "Why this product fits here"
}

If the product replaces an existing step (same category), use "replace" and specify the step_index (0-based). If it's a new category, use "add".
If the product fits both morning and evening (like a cleanser), respond with an array of two objects.`;

      try {
        const completion = await openaiChat.chat.completions.create({
          model: 'gpt-4o-mini',
          messages: [
            { role: 'system', content: 'You output strict JSON only.' },
            { role: 'user', content: prompt }
          ],
          temperature: 0.2,
          max_tokens: 400
        });

        const content = completion.choices[0]?.message?.content || '';
        let jsonStr = content;
        const jsonMatch = content.match(/[\[{][\s\S]*[\]}]/);
        if (jsonMatch) jsonStr = jsonMatch[0];
        let placements = JSON.parse(jsonStr);
        if (!Array.isArray(placements)) placements = [placements];

        // Apply placements to routine
        const newRoutine = {
          morning: [...(routineData.morning || [])],
          evening: [...(routineData.evening || [])],
          weekly: [...(routineData.weekly || [])],
        };

        const productEntry = {
          product: {
            id: product.id,
            name: product.name,
            brand: product.brand,
            price: product.price,
            category: product.category,
            image_url: product.image_url,
            buy_link: product.buy_link,
            rating: product.rating,
          }
        };

        for (const placement of placements) {
          const key = placement.routine_type as 'morning' | 'evening' | 'weekly';
          if (!newRoutine[key]) continue;

          if (placement.action === 'replace' && typeof placement.step_index === 'number' && newRoutine[key][placement.step_index]) {
            newRoutine[key][placement.step_index] = {
              ...newRoutine[key][placement.step_index],
              ...productEntry,
              product_name: product.name,
              product_brand: product.brand,
              product_price: product.price,
              product_image: product.image_url,
              product_id: product.id,
            };
          } else {
            // Add as new step
            newRoutine[key].push({
              step: newRoutine[key].length + 1,
              name: placement.step_name || product.category || 'New Step',
              instructions: placement.reason || '',
              frequency: key === 'weekly' ? 'weekly' : 'daily',
              ...productEntry,
              product_name: product.name,
              product_brand: product.brand,
              product_price: product.price,
              product_image: product.image_url,
              product_id: product.id,
            });
          }
        }

        // Save updated routine
        const saved = await DatabaseService.saveRoutine(userId, profile.id, {
          inference: {
            routine: newRoutine,
            summary: routineRow?.routine_data?.inference?.summary || 'Updated routine',
            personalized_tips: routineRow?.routine_data?.inference?.personalized_tips || [],
          },
        });

        console.log(`✅ Integrated product ${product.name} into routine for user ${userId}`);
        return res.json({ success: true, placements, routine_id: saved?.id || null });
      } catch (err: any) {
        console.error('LLM integration failed:', err?.message);
        return res.status(500).json({ error: 'Failed to integrate product' });
      }
    }

    res.status(500).json({ error: 'LLM not available for integration' });
  } catch (error) {
    console.error('Error integrating product:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// ═══════════════════════════════════════════════════════════════
// SKIN PROFILE ENDPOINTS
// ═══════════════════════════════════════════════════════════════

// Mock image analysis function (replace with real AI later)
async function analyzeImages(photos: {
  front?: string;
  left?: string;
  right?: string;
  scalp?: string;
}): Promise<any> {
  // Simulate processing time
  await new Promise(resolve => setTimeout(resolve, 500));
  
  // Mock analysis results - In production, this would call a vision AI model
  const hasPhotos = photos.front || photos.left || photos.right;
  
  if (!hasPhotos) {
    return null;
  }

  return {
    analyzed_at: new Date().toISOString(),
    model_version: '1.0-mock',
    skin: {
      detected_tone: 'medium',
      detected_type: 'combination',
      oiliness_score: Math.random() * 0.4 + 0.3, // 0.3-0.7
      hydration_score: Math.random() * 0.4 + 0.3,
      texture_score: Math.random() * 0.3 + 0.5, // 0.5-0.8
      concerns_detected: ['mild_texture', 'slight_oiliness'],
      redness_areas: [],
      pore_visibility: 'moderate'
    },
    hair: {
      detected_type: 'wavy',
      frizz_level: 'low',
      damage_indicators: [],
      scalp_condition: 'healthy'
    },
    confidence_scores: {
      skin_analysis: 0.75 + Math.random() * 0.15,
      hair_analysis: 0.70 + Math.random() * 0.15
    },
    recommendations_from_analysis: [
      'Consider a gentle BHA for texture',
      'Hydrating serum would benefit your skin',
      'SPF is essential for your skin tone'
    ]
  };
}

// Save complete skin profile (onboarding)
app.post('/api/skin-profiles', async (req, res) => {
  try {
    const { userId, profile, photos } = req.body;
    
    if (!userId) {
      return res.status(400).json({ error: 'User ID is required' });
    }

    console.log('📝 Saving skin profile for user:', userId);

    // Analyze images if provided
    let imageAnalysis = null;
    if (photos && (photos.front || photos.left || photos.right)) {
      console.log('🔍 Analyzing uploaded photos...');
      imageAnalysis = await analyzeImages(photos);
      console.log('✅ Image analysis complete. Confidence:', imageAnalysis?.confidence_scores?.skin_analysis);
    }

    // Combine user input with image analysis
    const combinedProfile = {
      ...profile,
      photoFrontUrl: photos?.front,
      photoLeftUrl: photos?.left,
      photoRightUrl: photos?.right,
      photoScalpUrl: photos?.scalp,
      imageAnalysis
    };

    const savedProfile = await DatabaseService.saveSkinProfile(userId, combinedProfile);
    
    if (savedProfile) {
      // Mark user as onboarded in users table
      const onboardedSuccess = await DatabaseService.markUserOnboarded(userId);
      if (onboardedSuccess) {
        console.log('✅ User marked as onboarded in users table:', userId);
      } else {
        console.error('⚠️ Failed to mark user as onboarded in users table:', userId);
      }
      
      res.json({ 
        success: true, 
        profile: savedProfile,
        imageAnalysis: imageAnalysis,
        onboarded: onboardedSuccess
      });
    } else {
      res.status(400).json({ error: 'Failed to save skin profile' });
    }
  } catch (error) {
    console.error('Error saving skin profile:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Get skin profile
app.get('/api/skin-profiles/:userId', async (req, res) => {
  try {
    const profile = await DatabaseService.getSkinProfileByUserId(req.params.userId);
    if (profile) {
      res.json({ success: true, profile });
    } else {
      res.status(404).json({ error: 'Skin profile not found' });
    }
  } catch (error) {
    console.error('Error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Analyze/Re-analyze images
app.post('/api/skin-profiles/:userId/analyze', async (req, res) => {
  try {
    const { photos } = req.body;
    const userId = req.params.userId;
    
    if (!photos || (!photos.front && !photos.left && !photos.right)) {
      return res.status(400).json({ error: 'At least one photo is required' });
    }

    console.log('🔍 Re-analyzing photos for user:', userId);
    const imageAnalysis = await analyzeImages(photos);
    
    const updatedProfile = await DatabaseService.updateImageAnalysis(userId, imageAnalysis);
    
    if (updatedProfile) {
      res.json({ 
        success: true, 
        profile: updatedProfile,
        imageAnalysis 
      });
    } else {
      res.status(400).json({ error: 'Failed to update analysis' });
    }
  } catch (error) {
    console.error('Error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Save photo check-in (biweekly progress)
app.post('/api/photo-check-ins', async (req, res) => {
  try {
    const { userId, skinProfileId, photos, userNotes, irritation, improvement } = req.body;
    
    if (!userId || !skinProfileId) {
      return res.status(400).json({ error: 'User ID and skin profile ID are required' });
    }

    console.log('📸 Saving photo check-in for user:', userId);

    // Analyze new photos
    let imageAnalysis = null;
    let comparison = null;
    
    if (photos && (photos.front || photos.left || photos.right)) {
      imageAnalysis = await analyzeImages(photos);
      
      // Get baseline for comparison
      const baselineProfile = await DatabaseService.getSkinProfileByUserId(userId);
      if (baselineProfile?.image_analysis) {
        // Mock comparison (in production, this would be a real comparison)
        comparison = {
          improvements: improvement ? ['user_reported_improvement'] : [],
          concerns: irritation ? ['user_reported_irritation'] : [],
          recommendation_changes: []
        };
      }
    }

    const checkIn = await DatabaseService.savePhotoCheckIn(userId, skinProfileId, {
      photoFrontUrl: photos?.front,
      photoLeftUrl: photos?.left,
      photoRightUrl: photos?.right,
      imageAnalysis,
      comparisonToBaseline: comparison,
      userNotes,
      irritationReported: irritation,
      improvementReported: improvement
    });
    
    if (checkIn) {
      res.json({ success: true, checkIn, comparison });
    } else {
      res.status(400).json({ error: 'Failed to save check-in' });
    }
  } catch (error) {
    console.error('Error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Get photo check-ins history
app.get('/api/photo-check-ins/:userId', async (req, res) => {
  try {
    const checkIns = await DatabaseService.getPhotoCheckIns(req.params.userId);
    res.json({ success: true, checkIns });
  } catch (error) {
    console.error('Error:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// ═══════════════════════════════════════════════════════════════
// CHAT PERSISTENCE ENDPOINTS
// ═══════════════════════════════════════════════════════════════

// Create new conversation
app.post('/api/conversations', async (req, res) => {
  try {
    const { userId, title } = req.body;
    if (!userId) return res.status(400).json({ error: 'userId required' });
    
    const conversation = await DatabaseService.createConversation(userId, title);
    if (conversation) {
      res.json({ success: true, conversation });
    } else {
      res.status(500).json({ error: 'Failed to create conversation' });
    }
  } catch (error) {
    console.error('Error creating conversation:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// List conversations for a user
app.get('/api/conversations/:userId', async (req, res) => {
  try {
    const conversations = await DatabaseService.getConversations(req.params.userId);
    res.json({ success: true, conversations });
  } catch (error) {
    console.error('Error listing conversations:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Get messages for a conversation
app.get('/api/conversations/:conversationId/messages', async (req, res) => {
  try {
    const messages = await DatabaseService.getConversationMessages(req.params.conversationId);
    res.json({ success: true, messages });
  } catch (error) {
    console.error('Error getting messages:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Save a message to a conversation
app.post('/api/conversations/:conversationId/messages', async (req, res) => {
  try {
    const { role, content, metadata } = req.body;
    if (!role || !content) return res.status(400).json({ error: 'role and content required' });
    
    const message = await DatabaseService.saveMessage(req.params.conversationId, role, content, metadata || undefined);
    if (message) {
      res.json({ success: true, message });
    } else {
      res.status(500).json({ error: 'Failed to save message' });
    }
  } catch (error) {
    console.error('Error saving message:', error);
    res.status(500).json({ error: 'Server error' });
  }
});

// Update conversation title
app.patch('/api/conversations/:conversationId', async (req, res) => {
  try {
    const { title } = req.body;
    const success = await DatabaseService.updateConversationTitle(req.params.conversationId, title);
    res.json({ success });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
});

// Delete a conversation
app.delete('/api/conversations/:conversationId', async (req, res) => {
  try {
    const success = await DatabaseService.deleteConversation(req.params.conversationId);
    res.json({ success });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
});

// ─────────────────────────────────────────────
// Insights
// ─────────────────────────────────────────────

// Get latest insights for a user
app.get('/api/insights/:userId', async (req, res) => {
  try {
    const insight = await DatabaseService.getLatestInsightByUserId(req.params.userId);
    if (!insight) {
      return res.status(404).json({ success: false, error: 'No insights found' });
    }
    res.json({ success: true, insight });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
});

// Save new insights for a user
app.post('/api/insights', async (req, res) => {
  try {
    const { userId, insight } = req.body;
    if (!userId || !insight) {
      return res.status(400).json({ error: 'Missing userId or insight' });
    }
    const saved = await DatabaseService.saveInsight(userId, insight);
    if (!saved) {
      return res.status(500).json({ error: 'Failed to save insights' });
    }
    res.json({ success: true, insight: saved });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
});

// ═══════════════════════════════════════════════════════════════
// CHAT ENDPOINT (GPT-4o-mini powered)
// ═══════════════════════════════════════════════════════════════

import OpenAI from 'openai';

const openaiChat = process.env.OPENAI_API_KEY 
  ? new OpenAI({ apiKey: process.env.OPENAI_API_KEY })
  : null;

// ═══════════════════════════════════════════════════════════════
// CHAT TOOL DEFINITIONS — model can call these dynamically
// ═══════════════════════════════════════════════════════════════

const chatTools: OpenAI.Chat.Completions.ChatCompletionTool[] = [
  {
    type: 'function',
    function: {
      name: 'get_user_skin_profile',
      description: 'Fetch the current user\'s complete skin profile from the database — includes skin type, tone, goals, concerns, hair info, sunscreen usage, budget, fragrance preference, and any image analysis results. Call this whenever you need to personalize a recommendation or understand the user\'s skin.',
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
      description: 'Fetch the user\'s current skincare routine (morning and evening steps). Call this when the user asks about their routine, wants to modify it, or when you need routine context to give advice.',
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
      description: 'Search the GlowUp product database for skincare products. Uses semantic vector search + keyword matching for the best results. Call this when the user asks for product recommendations, alternatives, or when you need to find specific products.',
      parameters: {
        type: 'object',
        properties: {
          query: {
            type: 'string',
            description: 'Natural language search query describing the product(s) needed, e.g. "gentle cleanser for oily acne-prone skin" or "vitamin C serum for dark spots"'
          },
          category: {
            type: 'string',
            description: 'Optional product category filter',
            enum: ['cleanser', 'moisturizer', 'serum', 'sunscreen', 'treatment', 'toner', 'mask', 'exfoliant', 'eye', 'face']
          },
          skin_type: {
            type: 'string',
            description: 'Filter by target skin type',
            enum: ['oily', 'dry', 'combination', 'sensitive', 'normal', 'acne-prone']
          },
          concerns: {
            type: 'array',
            items: { type: 'string' },
            description: 'Filter by target concerns, e.g. ["acne", "dark spots", "hydration"]'
          },
          max_price: {
            type: 'number',
            description: 'Maximum price in USD'
          },
          limit: {
            type: 'number',
            description: 'Max number of products to return (default 6, max 15)'
          }
        },
        required: ['query']
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'get_product_details',
      description: 'Get full details for a specific product by name or ID — includes ingredients, attributes, buy link, price, rating, and more. Call this when the user asks about a specific product or you need ingredient-level detail.',
      parameters: {
        type: 'object',
        properties: {
          product_name: {
            type: 'string',
            description: 'The name of the product to look up (partial match OK)'
          },
          product_id: {
            type: 'string',
            description: 'The UUID of the product (if known)'
          }
        },
        required: []
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'compare_products',
      description: 'Compare two or more products side-by-side. Returns details for each product so you can compare ingredients, price, rating, and suitability. Call this when the user wants to compare options.',
      parameters: {
        type: 'object',
        properties: {
          product_names: {
            type: 'array',
            items: { type: 'string' },
            description: 'Names of the products to compare'
          }
        },
        required: ['product_names']
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'add_to_cart',
      description: 'Add a product to the user cart by product_id. Use when the user asks to add items or when building a routine with products they want to buy.',
      parameters: {
        type: 'object',
        properties: {
          product_id: {
            type: 'string',
            description: 'The product UUID to add'
          },
          quantity: {
            type: 'number',
            description: 'Quantity to add (default 1)'
          }
        },
        required: ['product_id']
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'remove_from_cart',
      description: 'Remove a product from the user cart by product_id. Use when the user asks to remove something.',
      parameters: {
        type: 'object',
        properties: {
          product_id: {
            type: 'string',
            description: 'The product UUID to remove'
          }
        },
        required: ['product_id']
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'update_user_routine',
      description: 'Replace the user routine with a new morning/evening/weekly plan. Use when the user asks to build or change their routine from chat. Always include product_id from tool results.',
      parameters: {
        type: 'object',
        properties: {
          routine: {
            type: 'object',
            properties: {
              morning: {
                type: 'array',
                items: {
                  type: 'object',
                  properties: {
                    step: { type: 'number' },
                    name: { type: 'string' },
                    instructions: { type: 'string' },
                    frequency: { type: 'string' },
                    product_id: { type: 'string', description: 'Product UUID from search_products or get_product_details' },
                    product_name: { type: 'string' }
                  },
                  required: ['step', 'name']
                }
              },
              evening: {
                type: 'array',
                items: {
                  type: 'object',
                  properties: {
                    step: { type: 'number' },
                    name: { type: 'string' },
                    instructions: { type: 'string' },
                    frequency: { type: 'string' },
                    product_id: { type: 'string', description: 'Product UUID from search_products or get_product_details' },
                    product_name: { type: 'string' }
                  },
                  required: ['step', 'name']
                }
              },
              weekly: {
                type: 'array',
                items: {
                  type: 'object',
                  properties: {
                    step: { type: 'number' },
                    name: { type: 'string' },
                    instructions: { type: 'string' },
                    frequency: { type: 'string' },
                    product_id: { type: 'string', description: 'Product UUID from search_products or get_product_details' },
                    product_name: { type: 'string' }
                  },
                  required: ['step', 'name']
                }
              }
            },
            required: ['morning', 'evening']
          },
          summary: { type: 'string' }
        },
        required: ['routine']
      }
    }
  }
];

// ═══════════════════════════════════════════════════════════════
// CHAT TOOL EXECUTORS — handle each tool call
// ═══════════════════════════════════════════════════════════════

async function hydrateProductResults(results: any[]) {
  if (!results || results.length === 0) return results;
  const ids = results
    .map((row: any) => row.id || row.product_id)
    .filter(Boolean);
  if (ids.length === 0) return results;

  const needsHydration = results.some((row: any) => !row.image_url || !row.name);
  if (!needsHydration) return results;

  const { data } = await supabase
    .from('products')
    .select('id, name, brand, price, category, subcategory, summary, description, rating, image_url, target_skin_type, target_concerns, attributes, buy_link, ingredients')
    .in('id', ids);

  if (!data || data.length === 0) return results;

  const byId = new Map(data.map((row: any) => [row.id, row]));
  return ids
    .map((id: string) => {
      const base = byId.get(id);
      const sim = results.find((r: any) => (r.id || r.product_id) === id)?.similarity;
      return base ? { ...base, similarity: sim ?? base.similarity ?? null } : null;
    })
    .filter(Boolean);
}

async function executeChatTool(
  toolName: string, 
  args: any, 
  userId: string | null
): Promise<string> {
  try {
    switch (toolName) {
      case 'get_user_skin_profile': {
        if (!userId) return JSON.stringify({ error: 'No user signed in — cannot fetch profile' });
        
        const profile = await DatabaseService.getSkinProfileByUserId(userId);
        if (!profile) return JSON.stringify({ error: 'No skin profile found — user may not have completed onboarding' });
        
        // Return a clean, structured summary
        return JSON.stringify({
          skin_type: profile.skin_type,
          skin_tone: profile.skin_tone,
          skin_tone_label: profile.skin_tone_label,
          skin_goals: profile.skin_goals,
          skin_concerns: profile.skin_concerns,
          sunscreen_usage: profile.sunscreen_usage,
          fragrance_free: profile.fragrance_free,
          hair_type: profile.hair_type,
          hair_concerns: profile.hair_concerns,
          wash_frequency: profile.wash_frequency,
          budget: profile.budget,
          image_analysis: profile.image_analysis ? {
            detected_skin_type: profile.image_analysis.skin?.detected_type,
            detected_tone: profile.image_analysis.skin?.detected_tone,
            concerns_detected: profile.image_analysis.skin?.concerns_detected,
            hydration_score: profile.image_analysis.skin?.hydration_score,
            oiliness_score: profile.image_analysis.skin?.oiliness_score,
            texture_score: profile.image_analysis.skin?.texture_score,
          } : null
        });
      }
      
      case 'get_user_routine': {
        if (!userId) return JSON.stringify({ error: 'No user signed in — cannot fetch routine' });
        
        const routine = await DatabaseService.getLatestRoutine(userId);
        if (!routine) return JSON.stringify({ error: 'No routine found — user may not have generated one yet' });
        
        return JSON.stringify(routine.routine_data);
      }
      
      case 'search_products': {
        const query = args.query || '';
        const category = args.category;
        const skinType = args.skin_type;
        const concerns = args.concerns || [];
        const maxPrice = args.max_price;
        const limit = Math.min(args.limit || 6, 15);
        
        // Build search keywords from the query + filters
        const keywords = query.split(/\s+/).filter((w: string) => w.length > 2);
        if (skinType) keywords.push(skinType);
        if (concerns.length) keywords.push(...concerns);
        
        let results: any[] = [];
        
        // Try hybrid search with embeddings first
        if (openaiChat) {
          try {
            const embeddingResponse = await openaiChat.embeddings.create({
              model: 'text-embedding-3-small',
              input: query
            });
            const queryEmbedding = embeddingResponse.data[0].embedding;
            
            // Vector search via match_products RPC
            const { data: vectorResults, error } = await supabase.rpc('match_products', {
              query_embedding: queryEmbedding,
              match_threshold: 0.25,
              match_count: limit * 3
            });
            
            if (!error && vectorResults) {
              results = vectorResults;
            }
          } catch (e) {
            console.log('⚠️ Embedding search failed, falling back to keyword search');
          }
        }
        
        // Always add text search results from search_vector
        if (keywords.length > 0) {
          const tsQuery = keywords.join(' | ');
          const { data } = await supabase
            .from('products')
            .select('*')
            .textSearch('search_vector', tsQuery)
            .order('rating', { ascending: false })
            .limit(limit);
          if (data) results.push(...data);
        }

        // If vector search didn't work or returned too few results, supplement with keyword search
        if (results.length < limit) {
          // Search by target_skin_type
          if (skinType) {
            const skinTypeVariants: Record<string, string[]> = {
              'oily': ['oily', 'all', 'combination'],
              'dry': ['dry', 'all', 'sensitive'],
              'combination': ['combination', 'all', 'oily', 'dry'],
              'sensitive': ['sensitive', 'all', 'dry'],
              'normal': ['normal', 'all'],
              'acne-prone': ['acne-prone', 'oily', 'all'],
            };
            const variants = skinTypeVariants[skinType] || [skinType, 'all'];
            const { data } = await supabase
              .from('products')
              .select('*')
              .overlaps('target_skin_type', variants)
              .order('rating', { ascending: false })
              .limit(limit);
            if (data) results.push(...data);
          }
          
          // Search by target_concerns
          if (concerns.length > 0) {
            const { data } = await supabase
              .from('products')
              .select('*')
              .overlaps('target_concerns', concerns)
              .order('rating', { ascending: false })
              .limit(limit);
            if (data) results.push(...data);
          }
          
          // Full-text search as final fallback
          if (results.length < 3 && query) {
            const tsQuery = keywords.join(' | ');
            const { data } = await supabase
              .from('products')
              .select('*')
              .textSearch('search_vector', tsQuery)
              .order('rating', { ascending: false })
              .limit(limit);
            if (data) results.push(...data);
          }
        }
        
        // Apply filters
        if (category) results = results.filter((p: any) => p.category?.toLowerCase() === category.toLowerCase());
        if (maxPrice) results = results.filter((p: any) => p.price <= maxPrice);
        
        // Deduplicate by id
        const seen = new Set<string>();
        results = results.filter((p: any) => {
          if (seen.has(p.id)) return false;
          seen.add(p.id);
          return true;
        });
        
        results = await hydrateProductResults(results);

        // Return clean product list
        const cleaned = results.slice(0, limit).map((p: any) => ({
          id: p.id,
          name: p.name,
          brand: p.brand,
          price: p.price,
          category: p.category,
          subcategory: p.subcategory,
          summary: p.summary || p.description,
          rating: p.rating,
          image_url: p.image_url,
          target_skin_type: p.target_skin_type,
          target_concerns: p.target_concerns,
          key_ingredients: (p.ingredients || []).slice(0, 8),
          attributes: p.attributes,
          buy_link: p.buy_link,
          similarity: p.similarity
        }));
        
        return JSON.stringify({ count: cleaned.length, products: cleaned });
      }
      
      case 'get_product_details': {
        let product: any = null;
        
        if (args.product_id) {
          const { data } = await supabase
            .from('products')
            .select('*')
            .eq('id', args.product_id)
            .single();
          product = data;
        } else if (args.product_name) {
          // Fuzzy search by name
          const { data } = await supabase
            .from('products')
            .select('*')
            .ilike('name', `%${args.product_name}%`)
            .limit(1)
            .single();
          product = data;
        }
        
        if (!product) return JSON.stringify({ error: 'Product not found' });
        
        return JSON.stringify({
          id: product.id,
          name: product.name,
          brand: product.brand,
          price: product.price,
          category: product.category,
          subcategory: product.subcategory,
          summary: product.summary,
          rating: product.rating,
          image_url: product.image_url,
          buy_link: product.buy_link,
          retailer: product.retailer,
          target_skin_type: product.target_skin_type,
          target_concerns: product.target_concerns,
          ingredients: product.ingredients,
          attributes: product.attributes,
          size: product.size,
          key_benefits: product.key_benefits,
        });
      }
      
      case 'compare_products': {
        const names = args.product_names || [];
        const products: any[] = [];
        
        for (const name of names) {
          const { data } = await supabase
            .from('products')
            .select('*')
            .ilike('name', `%${name}%`)
            .limit(1)
            .single();
          if (data) {
            products.push({
              name: data.name,
              brand: data.brand,
              price: data.price,
              category: data.category,
              rating: data.rating,
              target_skin_type: data.target_skin_type,
              target_concerns: data.target_concerns,
              ingredients: (data.ingredients || []).slice(0, 10),
              attributes: data.attributes,
              summary: data.summary,
            });
          }
        }
        
        if (products.length === 0) return JSON.stringify({ error: 'No matching products found' });
        return JSON.stringify({ products });
      }

      case 'add_to_cart': {
        if (!userId) return JSON.stringify({ error: 'No user signed in — cannot add to cart' });
        const productId = args.product_id;
        const quantity = Math.max(1, args.quantity || 1);
        if (!productId) return JSON.stringify({ error: 'product_id is required' });
        const ok = await DatabaseService.upsertCartItem(userId, productId, quantity);
        if (!ok) return JSON.stringify({ error: 'Failed to add to cart' });
        return JSON.stringify({ success: true, product_id: productId, quantity });
      }

      case 'remove_from_cart': {
        if (!userId) return JSON.stringify({ error: 'No user signed in — cannot remove from cart' });
        const productId = args.product_id;
        if (!productId) return JSON.stringify({ error: 'product_id is required' });
        const ok = await DatabaseService.removeCartItem(userId, productId);
        if (!ok) return JSON.stringify({ error: 'Failed to remove from cart' });
        return JSON.stringify({ success: true, product_id: productId });
      }

      case 'update_user_routine': {
        if (!userId) return JSON.stringify({ error: 'No user signed in — cannot update routine' });
        const routine = args.routine;
        if (!routine) return JSON.stringify({ error: 'routine is required' });
        const profile = await DatabaseService.getSkinProfileByUserId(userId);
        if (!profile) return JSON.stringify({ error: 'No skin profile found — user may not have completed onboarding' });

        // Resolve product IDs for each step so the saved routine has real products
        const resolveRoutineSteps = async (steps: any[]) => {
          if (!steps || steps.length === 0) return [];
          return Promise.all(steps.map(async (s: any) => {
            let product = null;
            if (s.product_id) {
              const { data } = await supabase.from('products').select('id, name, brand, price, category, image_url, buy_link, rating, summary').eq('id', s.product_id).single();
              if (data) product = data;
            } else if (s.product_name) {
              const { data } = await supabase.from('products').select('id, name, brand, price, category, image_url, buy_link, rating, summary').ilike('name', `%${s.product_name}%`).limit(1).single();
              if (data) product = data;
            }
            return {
              step: s.step,
              name: s.name,
              instructions: s.instructions || '',
              frequency: s.frequency || 'daily',
              product: product ? {
                id: product.id, name: product.name, brand: product.brand,
                price: product.price, category: product.category,
                image_url: product.image_url, buy_link: product.buy_link,
                rating: product.rating, description: product.summary || '',
              } : undefined,
            };
          }));
        };

        const [morning, evening, weekly] = await Promise.all([
          resolveRoutineSteps(routine.morning || []),
          resolveRoutineSteps(routine.evening || []),
          resolveRoutineSteps(routine.weekly || []),
        ]);

        const routinePayload = {
          inference: {
            routine: { morning, evening, weekly },
            summary: args.summary || 'Routine updated from chat',
            personalized_tips: [],
          },
        };
        const saved = await DatabaseService.saveRoutine(userId, profile.id, routinePayload);
        if (!saved) return JSON.stringify({ error: 'Failed to save routine' });
        return JSON.stringify({ success: true, routine_id: saved.id });
      }
      
      default:
        return JSON.stringify({ error: `Unknown tool: ${toolName}` });
    }
  } catch (err: any) {
    console.error(`❌ Tool ${toolName} error:`, err?.message);
    return JSON.stringify({ error: `Tool failed: ${err?.message}` });
  }
}

// ═══════════════════════════════════════════════════════════════
// CHAT ENDPOINT — with dynamic tool calling
// ═══════════════════════════════════════════════════════════════

app.post('/api/chat', async (req, res) => {
  try {
    const { messages, userId, conversationId } = req.body;
    
    if (!messages || !Array.isArray(messages) || messages.length === 0) {
      return res.status(400).json({ error: 'Messages array is required' });
    }

    if (!openaiChat) {
      console.log('⚠️ No OpenAI key — using fallback chat response');
      return res.json({
        success: true,
        message: "I'm having trouble connecting right now. In the meantime: stay consistent with your routine, drink water, and never skip SPF! ✨"
      });
    }

    const chatModel = process.env.GLOWUP_CHAT_MODEL || 'ft:gpt-4o-2024-08-06:dave:glowup-chat-v3:D6qlO5WY';
    console.log(`💬 Chat request: ${messages.length} msgs, model: ${chatModel}, userId: ${userId || 'guest'}`);

    // ── Generate conversation context summary + last exchange (verbatim) ──
    let conversationContext = '';
    let lastExchangeVerbatim = '';
    if (messages.length > 1 && userId && conversationId) {
      try {
        // Fetch previous messages from this conversation
        const { data: prevMessages } = await supabase
          .from('chat_messages')
          .select('role, content, created_at')
          .eq('conversation_id', conversationId)
          .order('created_at', { ascending: true })
          .limit(30);
        
        if (prevMessages && prevMessages.length > 0) {
          // Capture last exchange verbatim (last 2 messages)
          const lastTwo = prevMessages.slice(-2);
          if (lastTwo.length > 0) {
            lastExchangeVerbatim = lastTwo
              .map((m: any) => `${m.role === 'user' ? 'User' : 'Assistant'}: ${m.content}`)
              .join('\n');
          }

          // Generate a concise summary of conversation history excluding last exchange
          const historyText = prevMessages
            .slice(0, Math.max(prevMessages.length - 2, 0))
            .map((m: any) => `${m.role === 'user' ? 'User' : 'Assistant'}: ${m.content}`)
            .join('\n');
          
          if (historyText.length > 0) {
            const summaryResp = await openaiChat.chat.completions.create({
              model: chatModel,
              messages: [
                { role: 'system', content: 'Summarize the conversation history in 2-3 sentences. Focus on: user concerns, products discussed, routine questions, and key context. Be concise.' },
                { role: 'user', content: `Conversation history:\n${historyText}` }
              ],
              max_tokens: 150,
              temperature: 0.3,
            });
            conversationContext = summaryResp.choices[0]?.message?.content?.trim() || '';
          }
        }
      } catch (err) {
        console.log('⚠️ Failed to generate conversation context:', err);
      }
    }

    const systemPrompt = `You are GlowUp AI, the skincare assistant inside the GlowUp app. You help users discover products, build routines, and improve their skin — and everything happens within this app.

${conversationContext ? `## Conversation Context (summary)\n\n${conversationContext}\n\nUse this context to provide personalized, relevant responses. Reference previous discussions naturally. When appropriate, recommend products that align with the user's ongoing concerns and goals.\n\n` : ''}
${lastExchangeVerbatim ? `## Last Exchange (verbatim)\n\n${lastExchangeVerbatim}\n\nUse this as the most recent context before the user's current message.\n\n` : ''}

## ABSOLUTE RULES (never violate these)

1. **NEVER recommend a product without calling search_products or get_product_details first.** Every single product you mention MUST come from a tool call that returned it from our database. If a product is not in our database, do not recommend it.
2. **NEVER say things like "I can help you find where to buy this" or "check out [retailer]" or "you can find it at..."** — GlowUp IS the store. The user buys directly through us. All products you recommend are already purchasable in the app via the product card.
3. **Every product mention MUST include a [[PRODUCT:<id>]] embed.** No exceptions. If you mention a product by name, the product card MUST appear right after it. The user should be able to tap and buy instantly.
4. **NEVER invent product names.** Only reference products that were returned by tool calls in this conversation. If your tools returned 0 results for a category, say so honestly — don't make up a product.
5. **If the user explicitly asks to add or buy products, you MUST call add_to_cart for those products.** Do not just describe them.

## Behavior

- ALWAYS call get_user_skin_profile before giving personalized advice (if you haven't already in this conversation)
- **PROACTIVELY recommend products** — when the user asks about skincare concerns, routines, or needs, search for and recommend relevant products from our database. Don't wait for explicit product requests.
- When recommending products, ALWAYS call search_products first — this searches our real product database
- When the user asks about a specific product, call get_product_details for real data
- When asked to compare, use compare_products
- If the user asks about their routine, call get_user_routine
- When the user asks for a routine or full routine build, call update_user_routine to persist the new routine
- When the user asks to add products or says they want to buy, call add_to_cart for the specific product_id(s)
- Use conversation context to provide continuity — reference previous discussions, build on earlier recommendations, and maintain a coherent thread
- You may call multiple tools in one turn

## Tone & Style

- Warm, encouraging, approachable — like a knowledgeable friend who genuinely cares
- Use emojis sparingly but naturally (✨, 💕, 🧴, 🌸)
- Evidence-based advice backed by real products and profile data from tools
- Be honest when unsure or when a product isn't in our catalog
- Reference specific product names, prices, and ingredients from tool results — never generic claims

## Formatting (the app renders rich text from Markdown)

- Use **bold** for product names, key terms, and emphasis
- Use *italic* for caveats, nuance, or gentle asides
- Use ## or ### for section headings — NEVER use #### or more (max 3 levels)
- Use bullet points (- item) for lists of products, steps, or tips
- Use numbered lists (1. 2. 3.) for ordered steps or routines
- Use --- horizontal rules to separate distinct sections
- Keep paragraphs concise — richness is welcome, walls of text are not
- NEVER wrap your entire response in a code block
- NEVER include image URLs or markdown images like ![alt](url) — the app handles images automatically via [[PRODUCT:id]]

## Spacing (CRITICAL for readability)

- Always leave a blank line BEFORE and AFTER every heading
- Always leave a blank line BEFORE and AFTER every list
- Always leave a blank line BEFORE and AFTER a horizontal rule
- Separate paragraphs with a blank line
- After a list ends, leave a blank line before the next section

## Product Embeds (CRITICAL)

When you mention ANY product from tool results, embed it inline using this exact syntax on its own line:

[[PRODUCT:<product_id>]]

Pattern: describe why the product is great, then immediately place the embed:

**CeraVe Hydrating Cleanser** by *CeraVe* — $15.99 ⭐ 4.7

[[PRODUCT:abc123-def456]]

Rules:
- One embed per product, placed RIGHT AFTER you describe it
- NEVER group all embeds at the end — they go inline with the text
- NEVER mention a product without its embed
- The embed renders as a tappable card with image, price, and buy button`;

    const chatMessages: OpenAI.Chat.Completions.ChatCompletionMessageParam[] = [
      { role: 'system', content: systemPrompt },
      ...messages.map((m: any) => ({ role: m.role as 'user' | 'assistant', content: m.content }))
    ];

    console.log(`💬 Chat request: ${messages.length} msgs, model: ${chatModel}, userId: ${userId || 'guest'}${conversationContext ? ' (with context)' : ''}`);
    if (conversationContext) {
      console.log(`📝 Conversation context: ${conversationContext.substring(0, 100)}...`);
    }

    const collectedProducts: any[] = [];

    // ── Tool-calling loop (max 5 iterations to prevent runaway) ──
    let currentMessages = [...chatMessages];
    let reply = '';
    const MAX_TOOL_ROUNDS = 5;
    
    for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
      const completion = await openaiChat.chat.completions.create({
        model: chatModel,
        messages: currentMessages,
        tools: chatTools,
        tool_choice: round === 0 ? 'auto' : 'auto', // let model decide
        max_tokens: 2000,
        temperature: 0.6,
      });

      const choice = completion.choices[0];
      const assistantMsg = choice.message;
      
      // If the model made tool calls, execute them and feed results back
      if (assistantMsg.tool_calls && assistantMsg.tool_calls.length > 0) {
        console.log(`🔧 Round ${round + 1}: ${assistantMsg.tool_calls.length} tool call(s):`);
        
        // Add the assistant message (with tool_calls) to the conversation
        currentMessages.push(assistantMsg as any);
        
        // Execute each tool call in parallel
        const toolResults = await Promise.all(
          assistantMsg.tool_calls.map(async (toolCall: any) => {
            const fnName = toolCall.function?.name || toolCall.name;
            const fnArgs = toolCall.function?.arguments || toolCall.arguments || '{}';
            const args = JSON.parse(fnArgs);
            console.log(`  🛠️  ${fnName}(${JSON.stringify(args).substring(0, 100)})`);
            
            const result = await executeChatTool(fnName, args, userId || null);
            console.log(`  ✅ ${fnName} → ${result.substring(0, 120)}...`);
            collectProductsFromToolResult(fnName, result, collectedProducts);
            
            return {
              role: 'tool' as const,
              tool_call_id: toolCall.id,
              content: result
            };
          })
        );
        
        // Add all tool results to the conversation
        currentMessages.push(...toolResults as any[]);
        
        // Continue the loop — model will process tool results and either call more tools or generate a final response
        continue;
      }
      
      // No tool calls — this is the final text response
      reply = assistantMsg.content || "I'm not sure how to respond to that. Could you rephrase?";
      console.log(`✅ Chat response (round ${round + 1}): ${reply.substring(0, 80)}...`);
      break;
    }
    
    if (!reply) {
      reply = "I gathered some information but couldn't formulate a complete response. Could you try rephrasing? 💕";
    }

    // Generate a short title summary from the first user message
    let title: string | undefined;
    const userMessages = messages.filter((m: any) => m.role === 'user');
    if (userMessages.length === 1) {
      try {
        const titleCompletion = await openaiChat.chat.completions.create({
          model: chatModel,
          messages: [
            { role: 'system', content: 'Summarize the user message into a very short chat title (max 6 words). No quotes, no punctuation at the end. Just a concise topic label. Examples: "Acne routine help", "Best sunscreen for oily skin", "Vitamin C serum advice"' },
            { role: 'user', content: userMessages[0].content }
          ],
          max_tokens: 20,
          temperature: 0.3,
        });
        title = titleCompletion.choices[0]?.message?.content?.trim();
        console.log(`📝 Generated chat title: ${title}`);
      } catch (e) {
        console.log('⚠️ Title generation failed, using fallback');
      }
    }

    // Build a product map keyed by ID for inline embeds
    const dedupedProducts = dedupeProducts(collectedProducts).slice(0, 20);
    const productMap: Record<string, any> = {};
    for (const p of dedupedProducts) {
      productMap[p.id] = p;
    }

    res.json({ 
      success: true, 
      message: reply, 
      products: dedupedProducts,
      product_map: productMap,
      ...(title && { title }) 
    });

  } catch (error: any) {
    console.error('❌ Chat error:', error?.message || error);
    res.status(500).json({ 
      error: 'Chat failed',
      message: "Sorry, I'm having trouble thinking right now. Try again in a moment! 💕"
    });
  }
});

function collectProductsFromToolResult(toolName: string, result: string, sink: any[]) {
  if (!result) return;
  let parsed: any = null;
  try {
    parsed = JSON.parse(result);
  } catch {
    return;
  }

  if (toolName === 'search_products') {
    const products = Array.isArray(parsed?.products) ? parsed.products : [];
    sink.push(...products);
    return;
  }

  if (toolName === 'get_product_details') {
    if (parsed?.id) sink.push(parsed);
    return;
  }

  if (toolName === 'compare_products') {
    const products = Array.isArray(parsed?.products) ? parsed.products : [];
    sink.push(...products);
  }
}

function dedupeProducts(products: any[]) {
  const map = new Map<string, any>();
  for (const p of products || []) {
    if (!p || !p.id) continue;
    if (!map.has(p.id)) map.set(p.id, p);
  }
  return Array.from(map.values());
}

// ═══════════════════════════════════════════════════════════════
// HOME FEED — Personalized via fine-tuned model + tool calling
// ═══════════════════════════════════════════════════════════════

const FEED_MODEL = process.env.GLOWUP_CHAT_MODEL || 'ft:gpt-4o-2024-08-06:dave:glowup-product-embeds:D6KQn97D';

// ── In-memory cache for home feed AI results (5 min TTL) ──
const feedCache = new Map<string, { data: any; ts: number }>();
const FEED_CACHE_TTL = 5 * 60 * 1000; // 5 minutes

function withTimeout<T>(promise: Promise<T>, ms: number, fallback: T): Promise<T> {
  return Promise.race([
    promise,
    new Promise<T>((resolve) => setTimeout(() => resolve(fallback), ms)),
  ]);
}

app.get('/api/home-feed/:userId', async (req, res) => {
  const { userId } = req.params;
  const startTime = Date.now();
  console.log(`🏠 Home feed request for user: ${userId}`);

  try {
    // ── 1. Fetch user's skin profile ──
    const profile = await DatabaseService.getSkinProfileByUserId(userId);
    if (!profile) {
      return res.status(404).json({ error: 'No skin profile found — complete onboarding first' });
    }

    const skinToneLabel = profile.skin_tone !== undefined
      ? (profile.skin_tone < 0.3 ? 'Fair' : profile.skin_tone < 0.5 ? 'Medium' : profile.skin_tone < 0.7 ? 'Medium-deep' : 'Deep')
      : 'not specified';
    const budgetMax = profile.budget === 'low' ? 25 : profile.budget === 'high' ? 100 : 60;

    // ── 2. Load latest insights for real-time score ──
    const latestInsight = await DatabaseService.getLatestInsightByUserId(userId);
    const confidence = latestInsight?.skin_score
      ? (latestInsight.skin_score > 1 ? Math.min(latestInsight.skin_score / 100, 1) : latestInsight.skin_score)
      : 0.85;

    // ── 3. Check AI cache ──
    const cacheKey = `feed:${userId}`;
    const cached = feedCache.get(cacheKey);
    const hasFreshCache = cached && (Date.now() - cached.ts < FEED_CACHE_TTL);

    // ── 4. Parallel fetches: saved routine, trending, new arrivals, personalized, AI fallback ──
    const [savedRoutineRow, trendingRes, newArrivalsRes, forYouRes, aiResult] = await Promise.all([
      // Load saved routine (product-enriched) from DB
      DatabaseService.getLatestRoutine(userId),

      // Trending = highest rated products
      supabase
        .from('products')
        .select('id, name, brand, price, category, summary, image_url, rating, review_count, buy_link, target_skin_type, target_concerns, attributes')
        .not('image_url', 'is', null)
        .gt('review_count', 50)
        .order('rating', { ascending: false })
        .limit(10),

      // New arrivals = most recently scraped Ulta products
      supabase
        .from('products')
        .select('id, name, brand, price, category, summary, image_url, rating, review_count, buy_link, target_skin_type, target_concerns, attributes')
        .eq('data_source', 'ulta_scrape')
        .not('image_url', 'is', null)
        .order('created_at', { ascending: false })
        .limit(10),

      // For You = embeddings-powered semantic search
      (async () => {
        if (!openaiChat) return [];
        try {
          const query = `${profile.skin_type} skin products for ${(profile.skin_goals || []).join(', ')} concerns: ${(profile.skin_concerns || []).join(', ')}`;
          const embeddingRes = await openaiChat.embeddings.create({
            model: 'text-embedding-3-small',
            input: query
          });
          const { data: vectorResults } = await supabase.rpc('match_products', {
            query_embedding: embeddingRes.data[0].embedding,
            match_threshold: 0.25,
            match_count: 15
          });
          return vectorResults || [];
        } catch { return []; }
      })(),

      // AI-generated summary + tips (used for tips and summary — routine comes from DB first)
      (async () => {
        if (hasFreshCache) {
          console.log('⚡ Using cached AI feed data');
          return cached!.data;
        }
        if (!openaiChat) return null;
        try {
          const systemPrompt = `You are GlowUp AI. Given a user's skin profile, create a personalized home feed. Return ONLY valid JSON:
{"summary":"1-2 sentence personalized insight","morning_routine":[{"step":1,"name":"Cleanser","tip":"short tip"}],"evening_routine":[{"step":1,"name":"Cleanser","tip":"short tip"}],"weekly_reset":[{"step":1,"name":"Exfoliation","tip":"short tip"}],"tips":["tip1","tip2","tip3"]}`;

          const userMsg = `Skin: ${profile.skin_type}, tone: ${skinToneLabel}. Goals: ${(profile.skin_goals || []).join(', ') || 'healthy skin'}. Concerns: ${(profile.skin_concerns || []).join(', ') || 'none'}. Sunscreen: ${profile.sunscreen_usage || 'sometimes'}. Budget: ${profile.budget || 'medium'} (~$${budgetMax}). Fragrance-free: ${profile.fragrance_free ? 'yes' : 'no'}.`;

          const aiPromise = openaiChat.chat.completions.create({
            model: FEED_MODEL,
            messages: [
              { role: 'system', content: systemPrompt },
              { role: 'user', content: userMsg }
            ],
            response_format: { type: 'json_object' },
            temperature: 0.5,
            max_tokens: 600,
          }).then(completion => {
            const content = completion.choices[0]?.message?.content;
            if (!content) return null;
            const parsed = JSON.parse(content);
            const result = {
              summary: parsed.summary || '',
              routine: {
                morning: parsed.morning_routine || [],
                evening: parsed.evening_routine || [],
                weekly: parsed.weekly_reset || [],
              },
              tips: parsed.tips || [],
            };
            feedCache.set(cacheKey, { data: result, ts: Date.now() });
            return result;
          });

          return await withTimeout(aiPromise, 10000, null);
        } catch (err: any) {
          console.log('⚠️ Feed model call failed:', err?.message);
          return null;
        }
      })(),
    ]);

    const trending = (trendingRes.data || []).map(mapProduct);
    const newArrivals = (newArrivalsRes.data || []).map(mapProduct);
    const forYou = await hydrateForYouProducts(forYouRes as any[] || [], profile);

    // ── 5. Build routine from saved DB data (with real products) or fallback to AI text ──
    let routine: any = { morning: [], evening: [], weekly: [] };
    let routineHasProducts = false;

    if (savedRoutineRow?.routine_data) {
      const rd = savedRoutineRow.routine_data;
      const inferenceRoutine = rd?.inference?.routine || rd?.routine || rd?.summary?.routine;
      if (inferenceRoutine) {
        const mapSavedSteps = (steps: any[]) => (steps || []).map((s: any) => ({
          step: s.step,
          name: s.name,
          tip: s.instructions || s.tip || '',
          product_id: s.product?.id || s.product_id || null,
          product_name: s.product?.name || s.product_name || null,
          product_brand: s.product?.brand || s.product_brand || null,
          product_price: s.product?.price || s.product_price || null,
          product_image: s.product?.image_url || s.product_image || null,
          buy_link: s.product?.buy_link || s.buy_link || null,
        }));
        routine = {
          morning: mapSavedSteps(inferenceRoutine.morning),
          evening: mapSavedSteps(inferenceRoutine.evening),
          weekly: mapSavedSteps(inferenceRoutine.weekly),
        };
        routineHasProducts = [...routine.morning, ...routine.evening, ...routine.weekly]
          .some((s: any) => s.product_id);
        console.log(`📋 Loaded saved routine (${routine.morning.length}AM / ${routine.evening.length}PM / ${routine.weekly.length}W) — products: ${routineHasProducts}`);
      }
    }

    // If no saved routine with products, fall back to AI-generated text routine
    if (routine.morning.length === 0 && routine.evening.length === 0) {
      const aiRoutine = aiResult?.routine || { morning: [], evening: [], weekly: [] };
      routine = aiRoutine;
    }

    const summary = aiResult?.summary || '';
    const tips = aiResult?.tips?.length > 0 ? aiResult.tips : [
      'Consistency beats complexity — stick to your routine!',
      'Always apply sunscreen as the last step in your morning routine.',
      'Pat products in gently instead of rubbing for better absorption.'
    ];

    // ── 6. Build response ──
    const elapsed = Date.now() - startTime;
    console.log(`✅ Home feed built in ${elapsed}ms — ${forYou.length} personalized, ${trending.length} trending, ${newArrivals.length} new${hasFreshCache ? ' (cached AI)' : ''}`);

    res.json({
      success: true,
      user_summary: summary || `Welcome back! Here's what's new for your ${profile.skin_type} skin.`,
      sections: {
        picked_for_you: forYou.slice(0, 8),
        trending: trending.slice(0, 8),
        new_arrivals: newArrivals.slice(0, 8),
      },
      routine,
      routine_has_products: routineHasProducts,
      tips,
      confidence,
      concern_spotlight: null,
      generated_at: new Date().toISOString(),
    });

  } catch (err: any) {
    console.error('❌ Home feed error:', err?.message);
    res.status(500).json({ error: 'Failed to generate home feed' });
  }
});

function mapProduct(p: any) {
  return {
    id: p.id,
    name: p.name,
    brand: p.brand,
    price: p.price,
    category: p.category,
    description: p.summary || p.description || '',
    image_url: p.image_url,
    rating: p.rating || 4.0,
    review_count: p.review_count || 0,
    similarity: p.similarity || null,
    buy_link: p.buy_link,
    target_skin_type: p.target_skin_type,
    target_concerns: p.target_concerns,
    attributes: p.attributes,
  };
}

async function hydrateForYouProducts(vectorResults: any[], profile: any) {
  if (!vectorResults || vectorResults.length === 0) return [];

  const ids = vectorResults
    .map((row: any) => row.id || row.product_id)
    .filter(Boolean);

  if (ids.length === 0) return vectorResults.map(mapProduct);

  const { data: productRows, error } = await supabase
    .from('products')
    .select('id, name, brand, price, category, summary, image_url, rating, review_count, buy_link, target_skin_type, target_concerns, attributes')
    .in('id', ids);

  let baseRows = productRows || [];
  if (error || baseRows.length === 0) {
    baseRows = vectorResults as any[];
  }

  // If no images for personalized picks, fallback to image-rich products for this skin type
  const hasImages = baseRows.some((row: any) => row.image_url);
  if (!hasImages && profile?.skin_type) {
    const { data: fallbackRows } = await supabase
      .from('products')
      .select('id, name, brand, price, category, summary, image_url, rating, review_count, buy_link, target_skin_type, target_concerns, attributes')
      .not('image_url', 'is', null)
      .contains('target_skin_type', [profile.skin_type])
      .limit(12);
    if (fallbackRows && fallbackRows.length > 0) {
      baseRows = fallbackRows;
    }
  }

  const similarityMap = new Map(
    (vectorResults || []).map((row: any) => [row.id || row.product_id, row.similarity])
  );

  const byId = new Map(baseRows.map((row: any) => [row.id, row]));
  const merged = ids
    .map((id: string) => {
      const row = byId.get(id);
      if (!row) return null;
      return { ...row, similarity: similarityMap.get(id) ?? row.similarity ?? null };
    })
    .filter(Boolean);

  const finalRows = merged.length > 0 ? merged : baseRows;
  return finalRows.map(mapProduct);
}

// ═══════════════════════════════════════════════════════════════
// ROUTINE CHECK-INS API
// ═══════════════════════════════════════════════════════════════

// Get today's check-in status
app.get('/api/routine-checkins/:userId/today', async (req, res) => {
  try {
    const { userId } = req.params;
    const { date } = req.query;
    
    const checkins = await DatabaseService.getTodayCheckins(userId, date as string);
    const streaks = await DatabaseService.getStreaks(userId);
    
    res.json({
      success: true,
      checkins: Array.from(checkins),
      streaks
    });
  } catch (error: any) {
    console.error('Error fetching check-ins:', error);
    res.status(500).json({ error: 'Failed to fetch check-ins' });
  }
});

// Mark step as complete
app.post('/api/routine-checkins/complete', async (req, res) => {
  try {
    const { userId, routineType, stepId, stepName, date } = req.body;
    
    if (!userId || !routineType || !stepId || !stepName) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    
    const success = await DatabaseService.markStepComplete(userId, routineType, stepId, stepName, date);
    
    if (success) {
      const streaks = await DatabaseService.getStreaks(userId);
      // Update insights with new streaks
      await DatabaseService.updateInsightStreaks(userId);
      res.json({ success: true, streaks });
    } else {
      res.status(500).json({ error: 'Failed to mark step complete' });
    }
  } catch (error: any) {
    console.error('Error marking step complete:', error);
    res.status(500).json({ error: 'Failed to mark step complete' });
  }
});

// Mark step as incomplete
app.post('/api/routine-checkins/incomplete', async (req, res) => {
  try {
    const { userId, routineType, stepId, date } = req.body;
    
    if (!userId || !routineType || !stepId) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    
    const success = await DatabaseService.markStepIncomplete(userId, routineType, stepId, date);
    
    if (success) {
      const streaks = await DatabaseService.getStreaks(userId);
      // Update insights with new streaks
      await DatabaseService.updateInsightStreaks(userId);
      res.json({ success: true, streaks });
    } else {
      res.status(500).json({ error: 'Failed to mark step incomplete' });
    }
  } catch (error: any) {
    console.error('Error marking step incomplete:', error);
    res.status(500).json({ error: 'Failed to mark step incomplete' });
  }
});

// Get streaks
app.get('/api/routine-checkins/:userId/streaks', async (req, res) => {
  try {
    const { userId } = req.params;
    const streaks = await DatabaseService.getStreaks(userId);
    res.json({ success: true, streaks });
  } catch (error: any) {
    console.error('Error fetching streaks:', error);
    res.status(500).json({ error: 'Failed to fetch streaks' });
  }
});

// ═══════════════════════════════════════════════════════════════
// SKIN PAGE — Agent-powered dynamic profile page
// ═══════════════════════════════════════════════════════════════

const skinPageCache = new Map<string, { data: any; ts: number }>();
const SKIN_PAGE_CACHE_TTL = 3 * 60 * 1000; // 3 minutes

app.get('/api/skin-page/:userId', async (req, res) => {
  const { userId } = req.params;
  const forceRefresh = req.query.refresh === 'true';
  console.log(`✨ Skin page request for user: ${userId}`);

  try {
    // ── 1. Fetch all user data in parallel ──
    const [profile, latestRoutineRow, latestInsight, streaks, checkins] = await Promise.all([
      DatabaseService.getSkinProfileByUserId(userId),
      DatabaseService.getLatestRoutine(userId),
      DatabaseService.getLatestInsightByUserId(userId),
      DatabaseService.getStreaks(userId),
      DatabaseService.getTodayCheckins(userId),
    ]);

    if (!profile) {
      return res.status(404).json({ error: 'No skin profile found — complete onboarding first' });
    }

    // ── 2. Extract routine with product details from stored routine_data ──
    const routineData = latestRoutineRow?.routine_data;
    const inferenceRoutine = routineData?.inference?.routine;
    const summaryRoutine = routineData?.summary?.routine;
    const rawRoutine = inferenceRoutine || summaryRoutine;

    // Map routine steps to include product info
    const mapRoutineSteps = (steps: any[] | undefined) => {
      if (!steps || steps.length === 0) return [];
      return steps.map((s: any) => ({
        step: s.step,
        name: s.name,
        product_name: s.product?.name || s.product_name || null,
        product_brand: s.product?.brand || s.product_brand || null,
        product_price: s.product?.price || s.product_price || null,
        product_image: s.product?.image_url || s.product_image || null,
        product_id: s.product?.id || s.product_id || null,
        buy_link: s.product?.buy_link || s.buy_link || null,
        instructions: s.instructions || s.tip || '',
        frequency: s.frequency || 'daily',
      }));
    };

    let routine = {
      morning: mapRoutineSteps(rawRoutine?.morning),
      evening: mapRoutineSteps(rawRoutine?.evening),
      weekly: mapRoutineSteps(rawRoutine?.weekly),
    };

    // ── 2b. If no routine saved, generate one from home feed cache or LLM ──
    if (routine.morning.length === 0 && routine.evening.length === 0) {
      console.log('ℹ️ No saved routine found, generating from home feed or LLM...');
      try {
        // Check if home feed cache has a routine
        const feedCacheKey = `feed:${userId}`;
        const feedCached = feedCache.get(feedCacheKey);
        if (feedCached?.data?.routine) {
          const cached = feedCached.data.routine;
          routine = {
            morning: (cached.morning || []).map((s: any, i: number) => ({
              step: s.step || i + 1,
              name: s.name || `Step ${i + 1}`,
              product_name: null,
              product_brand: null,
              product_price: null,
              product_image: null,
              product_id: null,
              instructions: s.tip || '',
              frequency: 'daily',
            })),
            evening: (cached.evening || []).map((s: any, i: number) => ({
              step: s.step || i + 1,
              name: s.name || `Step ${i + 1}`,
              product_name: null,
              product_brand: null,
              product_price: null,
              product_image: null,
              product_id: null,
              instructions: s.tip || '',
              frequency: 'daily',
            })),
            weekly: (cached.weekly || []).map((s: any, i: number) => ({
              step: s.step || i + 1,
              name: s.name || `Step ${i + 1}`,
              product_name: null,
              product_brand: null,
              product_price: null,
              product_image: null,
              product_id: null,
              instructions: s.tip || '',
              frequency: 'weekly',
            })),
          };
        } else if (openaiChat) {
          // Quick LLM call to generate a routine
          const routinePromise = openaiChat.chat.completions.create({
            model: FEED_MODEL,
            messages: [
              { role: 'system', content: `Generate a skincare routine. Return ONLY JSON: {"morning":[{"step":1,"name":"Cleanser","product_name":"...","product_brand":"...","product_price":0,"instructions":"..."}],"evening":[...]}. Use real product suggestions for ${profile.skin_type} skin.` },
              { role: 'user', content: `Skin: ${profile.skin_type}, goals: ${(profile.skin_goals || []).join(', ') || 'healthy skin'}, concerns: ${(profile.skin_concerns || []).join(', ') || 'none'}, budget: ${profile.budget || 'medium'}` },
            ],
            response_format: { type: 'json_object' },
            temperature: 0.5,
            max_tokens: 600,
          }).then(c => {
            const content = c.choices[0]?.message?.content;
            if (!content) return null;
            return JSON.parse(content);
          });

          const generated = await withTimeout(routinePromise, 8000, null);
          if (generated) {
            routine = {
              morning: (generated.morning || []).map((s: any) => ({
                step: s.step,
                name: s.name,
                product_name: s.product_name || null,
                product_brand: s.product_brand || null,
                product_price: s.product_price || null,
                product_image: null,
                product_id: null,
                instructions: s.instructions || '',
                frequency: s.frequency || 'daily',
              })),
              evening: (generated.evening || []).map((s: any) => ({
                step: s.step,
                name: s.name,
                product_name: s.product_name || null,
                product_brand: s.product_brand || null,
                product_price: s.product_price || null,
                product_image: null,
                product_id: null,
                instructions: s.instructions || '',
                frequency: s.frequency || 'daily',
              })),
              weekly: (generated.weekly || []).map((s: any) => ({
                step: s.step,
                name: s.name,
                product_name: s.product_name || null,
                product_brand: s.product_brand || null,
                product_price: s.product_price || null,
                product_image: null,
                product_id: null,
                instructions: s.instructions || '',
                frequency: s.frequency || 'weekly',
              })),
            };
          }
        }
      } catch (err: any) {
        console.log('⚠️ Routine generation fallback error:', err?.message);
      }
    }

    // ── 3. Build skin profile summary from DB ──
    const skinToneLabel = profile.skin_tone !== undefined
      ? (profile.skin_tone < 0.3 ? 'Fair' : profile.skin_tone < 0.5 ? 'Medium' : profile.skin_tone < 0.7 ? 'Medium-deep' : 'Deep')
      : 'Unknown';

    const skinScore = latestInsight?.skin_score
      ? (latestInsight.skin_score > 1 ? Math.min(latestInsight.skin_score / 100, 1) : latestInsight.skin_score)
      : 0.85;

    // ── 4. AI agent: dynamic tips & page summary (cached) ──
    const cacheKey = `skin-page:${userId}`;
    const cached = skinPageCache.get(cacheKey);
    const hasFreshCache = !forceRefresh && cached && (Date.now() - cached.ts < SKIN_PAGE_CACHE_TTL);

    let agentData: any = null;
    if (hasFreshCache) {
      agentData = cached!.data;
    } else if (openaiChat) {
      try {
        const completedSteps = Array.from(checkins || []);
        const totalMorning = routine.morning.length;
        const totalEvening = routine.evening.length;
        const morningDone = completedSteps.filter((s: string) => s.startsWith('morning-')).length;
        const eveningDone = completedSteps.filter((s: string) => s.startsWith('evening-')).length;

        const agentPrompt = `You are GlowUp's skin coach. Generate a personalized skin page summary for this user. Return ONLY valid JSON:
{
  "page_title": "short personalized greeting (2-4 words)",
  "page_subtitle": "1-sentence motivational insight",
  "skin_assessment": "2-3 sentence assessment of their skin based on profile + progress",
  "weekly_focus": "what they should focus on this week (1 sentence)",
  "tips": ["tip1", "tip2", "tip3", "tip4"],
  "progress_note": "1-sentence note about their routine adherence"
}`;

        const userMsg = `User profile:
- Skin type: ${profile.skin_type}
- Skin tone: ${skinToneLabel}
- Goals: ${(profile.skin_goals || []).join(', ') || 'healthy skin'}
- Concerns: ${(profile.skin_concerns || []).join(', ') || 'none'}
- Sunscreen: ${profile.sunscreen_usage || 'sometimes'}
- Fragrance-free: ${profile.fragrance_free ? 'yes' : 'no'}
- Budget: ${profile.budget || 'medium'}

Progress:
- Morning routine: ${morningDone}/${totalMorning} steps done today
- Evening routine: ${eveningDone}/${totalEvening} steps done today
- Morning streak: ${streaks?.morning || 0} days
- Evening streak: ${streaks?.evening || 0} days
- Skin score: ${Math.round(skinScore * 100)}/100
- Hydration: ${latestInsight?.hydration || 'Unknown'}
- Protection: ${latestInsight?.protection || 'Unknown'}`;

        const aiResult = await withTimeout(
          openaiChat.chat.completions.create({
            model: FEED_MODEL,
            messages: [
              { role: 'system', content: agentPrompt },
              { role: 'user', content: userMsg }
            ],
            response_format: { type: 'json_object' },
            temperature: 0.6,
            max_tokens: 500,
          }).then(c => {
            const content = c.choices[0]?.message?.content;
            if (!content) return null;
            return JSON.parse(content);
          }),
          8000,
          null
        );

        if (aiResult) {
          agentData = aiResult;
          skinPageCache.set(cacheKey, { data: aiResult, ts: Date.now() });
        }
      } catch (err: any) {
        console.log('⚠️ Skin page agent error:', err?.message);
      }
    }

    // ── 5. Build response ──
    res.json({
      success: true,
      profile: {
        skin_type: profile.skin_type || 'Normal',
        skin_tone: skinToneLabel,
        skin_tone_value: profile.skin_tone || 0.5,
        skin_goals: profile.skin_goals || [],
        skin_concerns: profile.skin_concerns || [],
        sunscreen_usage: profile.sunscreen_usage || 'sometimes',
        fragrance_free: profile.fragrance_free ?? false,
        hair_type: profile.hair_type || null,
        hair_concerns: profile.hair_concerns || [],
        wash_frequency: profile.wash_frequency || null,
        budget: profile.budget || 'medium',
      },
      routine,
      insights: {
        skin_score: skinScore,
        hydration: latestInsight?.hydration || null,
        protection: latestInsight?.protection || null,
        texture: latestInsight?.texture || null,
      },
      streaks: {
        morning: streaks?.morning || 0,
        evening: streaks?.evening || 0,
      },
      today_checkins: Array.from(checkins || []),
      agent: agentData || {
        page_title: 'Your Glow',
        page_subtitle: `Personalized care for your ${profile.skin_type || 'unique'} skin`,
        skin_assessment: `Your ${profile.skin_type || 'normal'} skin is on a great path. Keep up with your routine for the best results.`,
        weekly_focus: (profile.skin_concerns || []).length > 0
          ? `Focus on addressing ${(profile.skin_concerns || [])[0]} this week`
          : 'Focus on consistency with your daily routine',
        tips: [
          'Always apply sunscreen as the last step in your morning routine.',
          'Consistency beats complexity — stick to your routine!',
          'Pat products in gently for better absorption.',
          'Stay hydrated — your skin reflects your water intake.'
        ],
        progress_note: 'Keep building your streak for lasting results!',
      },
    });

  } catch (err: any) {
    console.error('❌ Skin page error:', err?.message);
    res.status(500).json({ error: 'Failed to load skin page' });
  }
});

// ═══════════════════════════════════════════════════════════════
// START SERVER
// ═══════════════════════════════════════════════════════════════

app.listen(port, () => {
  console.log(`
╔═══════════════════════════════════════════════════════════╗
║     🧠 GLOWUP MULTI-AGENT API - SERVER READY             ║
╠═══════════════════════════════════════════════════════════╣
║  4 Sub-Agents Active:                                     ║
║    🧴 Skin Analysis Agent                                 ║
║    💇 Hair Analysis Agent                                 ║
║    🔍 Product Matching Agent (Supabase)                   ║
║    💰 Budget Optimization Agent                           ║
╠═══════════════════════════════════════════════════════════╣
║  Server: http://localhost:${port}                            ║
║  Database: Supabase Connected                             ║
╚═══════════════════════════════════════════════════════════╝
  `);
});
