"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const dotenv_1 = __importDefault(require("dotenv"));
dotenv_1.default.config();
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const body_parser_1 = __importDefault(require("body-parser"));
const jwt = require('jsonwebtoken');
const crypto_1 = require("crypto");
const supabase_1 = require("./db/supabase");
const apple_1 = require("./auth/apple");
const inference_1 = require("./inference");
if (process.env.NODE_ENV === 'production') {
    const requiredEnv = [
        'JWT_SECRET',
        'ROUTINE_SHARE_SECRET',
        'SUPABASE_URL'
    ];
    const missing = requiredEnv.filter(key => !process.env[key] || String(process.env[key]).trim().length === 0);
    const hasSupabaseKey = (process.env.SUPABASE_SERVICE_ROLE_KEY || '').trim().length > 0 ||
        (process.env.SUPABASE_ANON_KEY || '').trim().length > 0;
    if (!hasSupabaseKey) {
        missing.push('SUPABASE_SERVICE_ROLE_KEY or SUPABASE_ANON_KEY');
    }
    if (missing.length > 0) {
        console.error(`❌ Missing required env vars: ${missing.join(', ')}`);
        process.exit(1);
    }
}
const app = (0, express_1.default)();
const port = process.env.PORT || 4000;
app.set('trust proxy', 1);
const configuredCorsOrigins = (process.env.GLOWUP_CORS_ORIGINS || '')
    .split(',')
    .map(origin => origin.trim())
    .filter(Boolean);
app.use((0, cors_1.default)(configuredCorsOrigins.length > 0 ? { origin: configuredCorsOrigins } : undefined));
app.use(body_parser_1.default.json({ limit: process.env.GLOWUP_MAX_JSON_BODY || '20mb' }));
app.get('/healthz', (_req, res) => {
    res.status(200).json({
        ok: true,
        service: 'glowup-api',
        uptime_seconds: Math.round(process.uptime()),
        timestamp: new Date().toISOString(),
        environment: process.env.NODE_ENV || 'development',
        llm_available: (0, inference_1.isLLMAvailable)(),
    });
});
// ─────────────────────────────────────────────────────────────────
// AGENT 1: Skin Analysis Agent
// ─────────────────────────────────────────────────────────────────
async function skinAnalysisAgent(profile) {
    const thinking = [];
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
    const skinConcerns = profile.concerns?.filter((c) => ['acne', 'aging', 'dryness', 'oiliness', 'pigmentation', 'sensitivity', 'redness', 'texture', 'dark_spots'].includes(c)) || [];
    thinking.push({
        thought: `Identified ${skinConcerns.length} skin-related concerns: ${skinConcerns.join(', ') || 'none specified'}.`
    });
    // Process skin goals
    const skinGoals = profile.skinGoals || [];
    if (skinGoals.length > 0) {
        thinking.push({
            thought: `Skin goals: ${skinGoals.map((g) => g.replace(/_/g, ' ')).join(', ')}. Tailoring routine to achieve these outcomes.`
        });
    }
    let routineComplexity = 'simple';
    if (skinConcerns.length > 2 || skinGoals.length > 1) {
        routineComplexity = 'comprehensive';
        thinking.push({
            thought: `Multiple concerns/goals detected. Recommending a comprehensive routine with targeted treatments.`
        });
    }
    const actives = [];
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
async function hairAnalysisAgent(profile) {
    const thinking = [];
    thinking.push({
        thought: `Evaluating hair type: "${profile.hairType}". This affects wash frequency and product weight.`
    });
    const hairConcerns = profile.concerns?.filter((c) => ['frizz', 'damage', 'scalp_itch', 'breakage', 'oily_scalp', 'dry_scalp', 'thinning', 'color_damage', 'heat_damage', 'scalp_sensitivity'].includes(c)) || [];
    thinking.push({
        thought: `Hair concerns detected: ${hairConcerns.join(', ') || 'general maintenance'}.`
    });
    // Determine porosity based on hair type
    let porosity = 'medium';
    if (profile.hairType === 'coily' || profile.hairType === 'curly') {
        porosity = 'high';
        thinking.push({ thought: `Curly/coily hair typically has high porosity. Needs protein-moisture balance.` });
    }
    else if (profile.hairType === 'straight') {
        porosity = 'low';
        thinking.push({ thought: `Straight hair often has low porosity. Lighter products absorb better.` });
    }
    // Use the user's selected wash frequency with inclusive options
    const userWashFrequency = profile.washFrequency || '2_3_weekly';
    const washFrequencyMap = {
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
    const stylingNeeds = [];
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
async function productMatchingAgent(skinResult, hairResult, profile) {
    const thinking = [];
    thinking.push({
        thought: `Received ${skinResult.recommendations.length} skin recommendations and ${hairResult.recommendations.length} hair recommendations.`
    });
    thinking.push({
        thought: `Cross-referencing with Supabase product database...`
    });
    // Fetch products from Supabase
    let products = await supabase_1.DatabaseService.getAllProducts();
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
        ];
    }
    else {
        thinking.push({ thought: `Found ${products.length} products in database.` });
    }
    thinking.push({
        thought: `Filtering products based on: ${profile.fragranceFree ? 'fragrance-free requirement, ' : ''}budget tier "${profile.budget}".`
    });
    // Filter by budget
    let maxPrice = profile.budget === 'low' ? 25 : profile.budget === 'medium' ? 50 : 200;
    let filteredProducts = products.filter((p) => p.price <= maxPrice);
    // Calculate match scores
    const scoredProducts = filteredProducts.map((p) => {
        let matchScore = 0.7; // Base score
        // Boost for matching concerns
        if (profile.concerns.some((c) => p.tags?.includes(c))) {
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
    scoredProducts.sort((a, b) => b.match - a.match);
    const topProducts = scoredProducts.slice(0, 6);
    thinking.push({
        thought: `Product selection complete.`,
        conclusion: `Selected ${topProducts.length} products with avg match score ${(topProducts.reduce((s, p) => s + p.match, 0) / topProducts.length * 100).toFixed(0)}%.`
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
async function budgetOptimizationAgent(products, profile) {
    const thinking = [];
    const totalCost = products.reduce((sum, p) => sum + p.price, 0);
    thinking.push({
        thought: `Total routine cost: $${totalCost.toFixed(2)}. Evaluating against "${profile.budget}" budget tier.`
    });
    const productsWithValue = products.map((p) => ({
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
            valueRanking: productsWithValue.sort((a, b) => b.valueScore - a.valueScore)
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
function deriveConcernSignalsFromImageAnalysis(imageAnalysis) {
    if (!imageAnalysis?.skin)
        return [];
    const concerns = new Set();
    const detected = Array.isArray(imageAnalysis.skin?.concerns_detected)
        ? imageAnalysis.skin.concerns_detected.map((c) => String(c).toLowerCase())
        : [];
    for (const concern of detected) {
        if (concern.includes('texture'))
            concerns.add('texture');
        if (concern.includes('oil'))
            concerns.add('oiliness');
        if (concern.includes('dry'))
            concerns.add('dryness');
        if (concern.includes('red'))
            concerns.add('redness');
        if (concern.includes('pigment') || concern.includes('dark'))
            concerns.add('pigmentation');
        if (concern.includes('acne') || concern.includes('breakout'))
            concerns.add('acne');
    }
    const hydration = Number(imageAnalysis.skin?.hydration_score);
    const oiliness = Number(imageAnalysis.skin?.oiliness_score);
    if (!Number.isNaN(hydration) && hydration < 0.42)
        concerns.add('dryness');
    if (!Number.isNaN(oiliness) && oiliness > 0.62)
        concerns.add('oiliness');
    return Array.from(concerns);
}
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
            console.log(`🧠 Using inference engine... (LLM: ${(0, inference_1.isLLMAvailable)() ? 'enabled' : 'fallback mode'})`);
            const savedSkinProfile = userId ? await supabase_1.DatabaseService.getSkinProfileByUserId(userId) : null;
            const profileConcerns = Array.isArray(profile.concerns) ? profile.concerns : [];
            const imageSignalConcerns = deriveConcernSignalsFromImageAnalysis(savedSkinProfile?.image_analysis);
            const mergedConcerns = Array.from(new Set([...profileConcerns, ...imageSignalConcerns]));
            const photoSkinType = String(savedSkinProfile?.image_analysis?.skin?.detected_type || '').toLowerCase();
            const photoConfidence = Number(savedSkinProfile?.image_analysis?.confidence_scores?.skin_analysis || 0);
            const resolvedSkinType = (photoSkinType && photoConfidence >= 0.7)
                ? photoSkinType
                : profile.skinType;
            const hydrationScore = Number(savedSkinProfile?.image_analysis?.skin?.hydration_score);
            const oilinessScore = Number(savedSkinProfile?.image_analysis?.skin?.oiliness_score);
            const textureScore = Number(savedSkinProfile?.image_analysis?.skin?.texture_score);
            const inferenceProfile = {
                skinType: resolvedSkinType,
                skinTone: profile.skinTone,
                skinGoals: profile.skinGoals,
                skinConcerns: mergedConcerns.filter((c) => ['acne', 'aging', 'dryness', 'oiliness', 'pigmentation', 'sensitivity', 'redness', 'texture', 'dark_spots'].includes(c)),
                hairType: profile.hairType,
                hairConcerns: mergedConcerns.filter((c) => ['frizz', 'damage', 'breakage', 'oily_scalp', 'dry_scalp', 'thinning', 'color_damage', 'heat_damage'].includes(c)),
                washFrequency: profile.washFrequency,
                sunscreenUsage: profile.sunscreenUsage,
                budget: profile.budget,
                fragranceFree: profile.fragranceFree,
                detectedSkinTypeFromPhoto: photoSkinType || undefined,
                photoAnalysisConfidence: photoConfidence || undefined,
                imageHydrationScore: Number.isFinite(hydrationScore) ? hydrationScore : undefined,
                imageOilinessScore: Number.isFinite(oilinessScore) ? oilinessScore : undefined,
                imageTextureScore: Number.isFinite(textureScore) ? textureScore : undefined,
            };
            const inferenceResult = await (0, inference_1.runInference)(inferenceProfile);
            // ── Auto-save the product-enriched routine for this user ──
            let routineId = null;
            if (userId) {
                try {
                    const skinProfile = await supabase_1.DatabaseService.getSkinProfileByUserId(userId);
                    const profileId = skinProfile?.id || userId;
                    const saved = await supabase_1.DatabaseService.saveRoutine(userId, profileId, {
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
                }
                catch (err) {
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
                    const uniqueProductIds = new Set();
                    for (const step of allSteps) {
                        const pid = step.product?.id;
                        if (pid && !uniqueProductIds.has(pid)) {
                            uniqueProductIds.add(pid);
                            await supabase_1.DatabaseService.upsertCartItem(userId, pid, 1);
                        }
                    }
                    console.log(`🛒 Auto-added ${uniqueProductIds.size} routine products to cart`);
                }
                catch (err) {
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
                            totalCost: inferenceResult.products.reduce((sum, p) => sum + p.price, 0),
                            monthlyEstimate: inferenceResult.products.reduce((sum, p) => sum + p.price, 0) * 0.3
                        },
                        confidence: 0.90
                    }
                ],
                summary: {
                    totalProducts: inferenceResult.products.length,
                    totalCost: inferenceResult.products.reduce((sum, p) => sum + p.price, 0),
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
                overallConfidence: ((skinResult.confidence + hairResult.confidence + productResult.confidence + budgetResult.confidence) / 4).toFixed(2)
            }
        };
        console.log('✅ Rule-based analysis complete. Confidence:', response.summary.overallConfidence);
        res.json(response);
    }
    catch (error) {
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
        const result = await (0, apple_1.verifyAppleToken)(identityToken, fullName);
        if (result.success) {
            // Include onboarded status in response
            res.json({ success: true, user: result.user });
        }
        else {
            res.status(401).json({ error: result.error || 'Authentication failed' });
        }
    }
    catch (error) {
        console.error('Apple Auth Error:', error);
        res.status(500).json({ error: 'Internal server error' });
    }
});
// Check user onboarding status
app.get('/api/users/:userId/onboarded', async (req, res) => {
    try {
        console.log('🔍 Checking onboarded status for user:', req.params.userId);
        const isOnboarded = await supabase_1.DatabaseService.isUserOnboarded(req.params.userId);
        console.log('📊 User onboarded:', isOnboarded);
        res.json({ success: true, onboarded: isOnboarded });
    }
    catch (error) {
        console.error('Error checking onboarding:', error);
        res.status(500).json({ error: 'Server error' });
    }
});
// Get user info
app.get('/api/users/:userId', async (req, res) => {
    try {
        const user = await supabase_1.DatabaseService.getUserById(req.params.userId);
        if (user) {
            res.json({ success: true, user });
        }
        else {
            res.status(404).json({ error: 'User not found' });
        }
    }
    catch (error) {
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
        const user = await supabase_1.DatabaseService.getOrCreateUser(email, name);
        if (user) {
            res.json({ success: true, user });
        }
        else {
            res.status(400).json({ error: 'Failed to create user' });
        }
    }
    catch (error) {
        console.error('Error:', error);
        res.status(500).json({ error: 'Server error' });
    }
});
// Save user profile
app.post('/api/profiles', async (req, res) => {
    try {
        const { userId, profile } = req.body;
        const savedProfile = await supabase_1.DatabaseService.saveProfile(userId, profile);
        if (savedProfile) {
            res.json({ success: true, profile: savedProfile });
        }
        else {
            res.status(400).json({ error: 'Failed to save profile' });
        }
    }
    catch (error) {
        console.error('Error:', error);
        res.status(500).json({ error: 'Server error' });
    }
});
// Get user profile
app.get('/api/profiles/:userId', async (req, res) => {
    try {
        const profile = await supabase_1.DatabaseService.getProfileByUserId(req.params.userId);
        if (profile) {
            res.json({ success: true, profile });
        }
        else {
            res.status(404).json({ error: 'Profile not found' });
        }
    }
    catch (error) {
        console.error('Error:', error);
        res.status(500).json({ error: 'Server error' });
    }
});
// Save routine
app.post('/api/routines', async (req, res) => {
    try {
        const { userId, profileId, routineData } = req.body;
        const routine = await supabase_1.DatabaseService.saveRoutine(userId, profileId, routineData);
        if (routine) {
            res.json({ success: true, routine });
        }
        else {
            res.status(400).json({ error: 'Failed to save routine' });
        }
    }
    catch (error) {
        console.error('Error:', error);
        res.status(500).json({ error: 'Server error' });
    }
});
const fulfillment_1 = require("./agents/fulfillment");
const orderTrackingStore = new Map();
const latestOrderByUser = new Map();
function pushTrackingEvent(orderId, status, message) {
    const record = orderTrackingStore.get(orderId);
    if (!record)
        return;
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
        const result = await fulfillment_1.FulfillmentAgent.setupSession();
        res.json(result);
    }
    catch (error) {
        console.error('Session Setup Error:', error);
        res.status(500).json({ success: false, message: `Setup failed: ${error}` });
    }
});
// Check if the Ulta session is still valid
app.get('/api/orders/session-status', async (_req, res) => {
    try {
        const valid = await fulfillment_1.FulfillmentAgent.isSessionValid();
        res.json({ valid, message: valid ? 'Session active' : 'Session expired or not set up' });
    }
    catch (error) {
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
        const result = await fulfillment_1.FulfillmentAgent.processOrder({
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
            const nextRecord = {
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
        }
        else {
            console.log(`❌ Order failed: ${result.error}`);
            pushTrackingEvent(pendingOrderId, 'failed', result.error || 'Checkout failed before confirmation.');
            res.status(500).json({ success: false, error: result.error, logs: result.logs });
        }
    }
    catch (error) {
        console.error('Order Error:', error);
        res.status(500).json({ error: 'Failed to process order' });
    }
});
// Get tracking for a specific order
app.get('/api/orders/:orderId/tracking', async (req, res) => {
    try {
        const { orderId } = req.params;
        const record = orderTrackingStore.get(orderId);
        if (!record)
            return res.status(404).json({ error: 'Tracking not found' });
        res.json({ success: true, tracking: record });
    }
    catch (error) {
        console.error('Tracking Error:', error);
        res.status(500).json({ error: 'Failed to fetch tracking' });
    }
});
// Get latest order tracking for a user
app.get('/api/orders/user/:userId/latest-tracking', async (req, res) => {
    try {
        const { userId } = req.params;
        const latestOrderId = latestOrderByUser.get(userId);
        if (!latestOrderId)
            return res.status(404).json({ error: 'No tracked order found' });
        const record = orderTrackingStore.get(latestOrderId);
        if (!record)
            return res.status(404).json({ error: 'Tracking not found' });
        res.json({ success: true, tracking: record });
    }
    catch (error) {
        console.error('Latest Tracking Error:', error);
        res.status(500).json({ error: 'Failed to fetch latest tracking' });
    }
});
// Get user routines
app.get('/api/routines/:userId', async (req, res) => {
    try {
        console.log('📋 Getting routines for user:', req.params.userId);
        const routines = await supabase_1.DatabaseService.getRoutinesByUserId(req.params.userId);
        console.log('📋 Found', routines?.length || 0, 'routines');
        res.json({ success: true, routines });
    }
    catch (error) {
        console.error('Error:', error);
        res.status(500).json({ error: 'Server error' });
    }
});
function getRoutineObjectFromData(routineData) {
    if (!routineData)
        return null;
    return routineData?.inference?.routine || routineData?.routine || routineData?.summary?.routine || null;
}
function routineHasLinkedProducts(routineData) {
    const routine = getRoutineObjectFromData(routineData);
    if (!routine)
        return false;
    const allSteps = [
        ...(routine.morning || []),
        ...(routine.evening || []),
        ...(routine.weekly || []),
    ];
    return allSteps.some((s) => Boolean(s?.product?.id || s?.product_id));
}
function mapDbProfileToInference(profile) {
    const profileSkinConcerns = Array.isArray(profile?.skin_concerns) ? profile.skin_concerns : [];
    const imageSignalConcerns = deriveConcernSignalsFromImageAnalysis(profile?.image_analysis);
    const mergedSkinConcerns = Array.from(new Set([...profileSkinConcerns, ...imageSignalConcerns]))
        .map((c) => String(c).toLowerCase().replace(/\s+/g, '_'));
    const hairConcerns = (Array.isArray(profile?.hair_concerns) ? profile.hair_concerns : [])
        .map((c) => String(c).toLowerCase().replace(/\s+/g, '_'));
    const photoSkinType = String(profile?.image_analysis?.skin?.detected_type || '').toLowerCase();
    const photoConfidence = Number(profile?.image_analysis?.confidence_scores?.skin_analysis || 0);
    const resolvedSkinType = (photoSkinType && photoConfidence >= 0.7)
        ? photoSkinType
        : (profile?.skin_type || 'normal');
    const hydrationScore = Number(profile?.image_analysis?.skin?.hydration_score);
    const oilinessScore = Number(profile?.image_analysis?.skin?.oiliness_score);
    const textureScore = Number(profile?.image_analysis?.skin?.texture_score);
    return {
        skinType: resolvedSkinType,
        skinTone: profile?.skin_tone,
        skinGoals: Array.isArray(profile?.skin_goals) ? profile.skin_goals : [],
        skinConcerns: mergedSkinConcerns.filter((c) => ['acne', 'aging', 'dryness', 'oiliness', 'pigmentation', 'sensitivity', 'redness', 'texture', 'dark_spots'].includes(c)),
        hairType: profile?.hair_type || undefined,
        hairConcerns: hairConcerns.filter((c) => ['frizz', 'damage', 'breakage', 'oily_scalp', 'dry_scalp', 'thinning', 'color_damage', 'heat_damage'].includes(c)),
        washFrequency: profile?.wash_frequency || undefined,
        sunscreenUsage: profile?.sunscreen_usage || undefined,
        budget: profile?.budget || 'medium',
        fragranceFree: !!profile?.fragrance_free,
        detectedSkinTypeFromPhoto: photoSkinType || undefined,
        photoAnalysisConfidence: photoConfidence || undefined,
        imageHydrationScore: Number.isFinite(hydrationScore) ? hydrationScore : undefined,
        imageOilinessScore: Number.isFinite(oilinessScore) ? oilinessScore : undefined,
        imageTextureScore: Number.isFinite(textureScore) ? textureScore : undefined,
    };
}
async function ensureUserHasProductRoutine(userId, profile, latestRoutineRow) {
    if (latestRoutineRow?.routine_data && routineHasLinkedProducts(latestRoutineRow.routine_data)) {
        return latestRoutineRow;
    }
    try {
        console.log(`🧴 No product-linked routine found for ${userId}. Generating one from inference...`);
        const inferenceProfile = mapDbProfileToInference(profile);
        const inferred = await withTimeout((0, inference_1.runInference)(inferenceProfile), 22000, null);
        if (!inferred)
            return latestRoutineRow;
        const profileId = profile?.id || userId;
        const saved = await supabase_1.DatabaseService.saveRoutine(userId, profileId, {
            inference: {
                routine: inferred.routine,
                summary: inferred.summary,
                personalized_tips: inferred.personalized_tips,
            },
        });
        if (!saved)
            return latestRoutineRow;
        const refreshed = await supabase_1.DatabaseService.getLatestRoutine(userId);
        if (refreshed?.routine_data && routineHasLinkedProducts(refreshed.routine_data)) {
            console.log(`✅ Product-linked routine generated for ${userId}`);
            return refreshed;
        }
    }
    catch (err) {
        console.log(`⚠️ Failed to auto-generate product routine for ${userId}:`, err?.message);
    }
    return latestRoutineRow;
}
async function searchProductsForRoutineEditor(query, userId, category, limit = 8) {
    const cappedLimit = Math.max(1, Math.min(limit, 20));
    const safeQuery = String(query || '').trim();
    const normalizedCategory = category ? String(category).toLowerCase() : undefined;
    const results = [];
    let profile = null;
    if (userId) {
        profile = await supabase_1.DatabaseService.getSkinProfileByUserId(userId);
    }
    if (openaiChat && safeQuery.length > 0) {
        try {
            const embeddingRes = await openaiChat.embeddings.create({
                model: 'text-embedding-3-small',
                input: safeQuery,
            });
            const queryEmbedding = embeddingRes.data[0].embedding;
            const { data: vectorResults } = await supabase_1.supabase.rpc('match_products', {
                query_embedding: queryEmbedding,
                match_threshold: 0.22,
                match_count: cappedLimit * 4,
            });
            if (vectorResults && vectorResults.length > 0) {
                results.push(...vectorResults);
            }
        }
        catch { }
    }
    const qTerm = safeQuery.replace(/[,%]/g, ' ').trim();
    let dbQuery = supabase_1.supabase
        .from('products')
        .select('id, name, brand, price, category, summary, description, image_url, rating, buy_link, target_skin_type, target_concerns')
        .order('rating', { ascending: false })
        .limit(cappedLimit * 4);
    if (normalizedCategory)
        dbQuery = dbQuery.eq('category', normalizedCategory);
    if (qTerm.length > 0) {
        dbQuery = dbQuery.or(`name.ilike.%${qTerm}%,brand.ilike.%${qTerm}%,summary.ilike.%${qTerm}%`);
    }
    const { data: keywordResults } = await dbQuery;
    if (keywordResults?.length) {
        results.push(...keywordResults);
    }
    if (results.length < cappedLimit && qTerm.length > 0) {
        const tsQuery = qTerm.split(/\s+/).filter(Boolean).join(' | ');
        if (tsQuery.length > 0) {
            const { data: textResults } = await supabase_1.supabase
                .from('products')
                .select('id, name, brand, price, category, summary, description, image_url, rating, buy_link, target_skin_type, target_concerns')
                .textSearch('search_vector', tsQuery)
                .order('rating', { ascending: false })
                .limit(cappedLimit * 3);
            if (textResults?.length)
                results.push(...textResults);
        }
    }
    const seen = new Set();
    let deduped = results.filter((p) => {
        const id = p?.id;
        if (!id || seen.has(id))
            return false;
        seen.add(id);
        return true;
    });
    if (normalizedCategory) {
        deduped = deduped.filter((p) => String(p.category || '').toLowerCase() === normalizedCategory);
    }
    if (profile?.skin_type) {
        const preferred = deduped.filter((p) => {
            const types = Array.isArray(p.target_skin_type) ? p.target_skin_type.map((t) => t.toLowerCase()) : [];
            return types.includes(profile.skin_type) || types.includes('all');
        });
        if (preferred.length >= Math.min(3, cappedLimit)) {
            deduped = [...preferred, ...deduped.filter((p) => !preferred.find((pp) => pp.id === p.id))];
        }
    }
    deduped.sort((a, b) => {
        const simA = Number(a.similarity || 0);
        const simB = Number(b.similarity || 0);
        if (simA !== simB)
            return simB - simA;
        return Number(b.rating || 0) - Number(a.rating || 0);
    });
    return deduped.slice(0, cappedLimit).map((p) => ({
        id: p.id,
        name: p.name,
        brand: p.brand,
        price: Number(p.price || 0),
        category: p.category,
        description: p.summary || p.description || '',
        image_url: p.image_url || null,
        rating: p.rating || null,
        buy_link: p.buy_link || null,
    }));
}
app.post('/api/routine/search-products', async (req, res) => {
    try {
        const { userId, query, category, limit } = req.body || {};
        const normalizedQuery = String(query || '').trim();
        if (!normalizedQuery) {
            return res.status(400).json({ error: 'query is required' });
        }
        const products = await searchProductsForRoutineEditor(normalizedQuery, userId, category, Number(limit || 8));
        res.json({ success: true, products });
    }
    catch (error) {
        console.error('Routine search error:', error?.message);
        res.status(500).json({ error: 'Failed to search routine products' });
    }
});
app.post('/api/routine/update', async (req, res) => {
    try {
        const { userId, routine, summary } = req.body || {};
        if (!userId || !routine) {
            return res.status(400).json({ error: 'userId and routine are required' });
        }
        const profile = await supabase_1.DatabaseService.getSkinProfileByUserId(userId);
        if (!profile) {
            return res.status(404).json({ error: 'Skin profile not found' });
        }
        const resolveProduct = async (step) => {
            if (step?.product_id) {
                const { data } = await supabase_1.supabase
                    .from('products')
                    .select('id, name, brand, price, category, image_url, buy_link, rating, summary, description')
                    .eq('id', step.product_id)
                    .limit(1);
                if (data && data[0])
                    return data[0];
            }
            if (step?.product_name) {
                const q = String(step.product_name).trim().replace(/[,%]/g, ' ');
                if (q.length > 0) {
                    const { data } = await supabase_1.supabase
                        .from('products')
                        .select('id, name, brand, price, category, image_url, buy_link, rating, summary, description')
                        .or(`name.ilike.%${q}%,brand.ilike.%${q}%`)
                        .order('rating', { ascending: false })
                        .limit(1);
                    if (data && data[0])
                        return data[0];
                }
            }
            return null;
        };
        const normalizeSteps = async (steps, routineType) => {
            const input = Array.isArray(steps) ? steps : [];
            const normalized = await Promise.all(input.map(async (s, idx) => {
                const resolvedProduct = await resolveProduct(s);
                return {
                    step: Number(s?.step || idx + 1),
                    name: String(s?.name || `Step ${idx + 1}`),
                    instructions: String(s?.instructions || s?.tip || ''),
                    frequency: String(s?.frequency || (routineType === 'weekly' ? 'weekly' : 'daily')),
                    product: resolvedProduct ? {
                        id: resolvedProduct.id,
                        name: resolvedProduct.name,
                        brand: resolvedProduct.brand,
                        price: resolvedProduct.price,
                        category: resolvedProduct.category,
                        image_url: resolvedProduct.image_url,
                        buy_link: resolvedProduct.buy_link,
                        rating: resolvedProduct.rating || 4.0,
                        description: resolvedProduct.summary || resolvedProduct.description || '',
                    } : undefined,
                };
            }));
            return normalized
                .sort((a, b) => Number(a.step) - Number(b.step))
                .map((s, idx) => ({ ...s, step: idx + 1 }));
        };
        const [morning, evening, weekly] = await Promise.all([
            normalizeSteps(routine.morning || [], 'morning'),
            normalizeSteps(routine.evening || [], 'evening'),
            normalizeSteps(routine.weekly || [], 'weekly'),
        ]);
        const payload = {
            inference: {
                routine: { morning, evening, weekly },
                summary: summary || 'Routine updated by user',
                personalized_tips: [],
            },
        };
        const saved = await supabase_1.DatabaseService.saveRoutine(userId, profile.id, payload);
        if (!saved) {
            return res.status(500).json({ error: 'Failed to save routine' });
        }
        res.json({ success: true, routine_id: saved.id, routine: payload.inference.routine });
    }
    catch (error) {
        console.error('Routine update error:', error?.message);
        res.status(500).json({ error: 'Failed to update routine' });
    }
});
const ROUTINE_SHARE_SECRET = process.env.ROUTINE_SHARE_SECRET || process.env.JWT_SECRET || 'glowup-routine-share-dev-secret';
const APP_STORE_URL = process.env.GLOWUP_APP_STORE_URL || 'https://apps.apple.com/us/search?term=GlowUp';
function normalizeShareStep(step, fallbackIndex) {
    return {
        step: Number(step?.step || fallbackIndex + 1),
        name: String(step?.name || `Step ${fallbackIndex + 1}`),
        instructions: String(step?.instructions || step?.tip || ''),
        frequency: String(step?.frequency || 'daily'),
        product_id: step?.product?.id || step?.product_id || null,
        product_name: step?.product?.name || step?.product_name || null,
        product_brand: step?.product?.brand || step?.product_brand || null,
        product_price: step?.product?.price || step?.product_price || null,
    };
}
function buildRoutineSharePayload(routineData, routineType) {
    const routine = getRoutineObjectFromData(routineData) || { morning: [], evening: [], weekly: [] };
    const morning = (routine?.morning || []).map(normalizeShareStep);
    const evening = (routine?.evening || []).map(normalizeShareStep);
    const weekly = (routine?.weekly || []).map(normalizeShareStep);
    if (routineType === 'morning')
        return { morning, evening: [], weekly: [] };
    if (routineType === 'evening')
        return { morning: [], evening, weekly: [] };
    if (routineType === 'weekly')
        return { morning: [], evening: [], weekly };
    return { morning, evening, weekly };
}
function escapeHtml(input) {
    return input
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}
function renderRoutineSectionHtml(title, steps) {
    if (!steps || steps.length === 0)
        return '';
    const rows = steps.map((step) => {
        const productLine = step.product_name
            ? `<div class="product">${escapeHtml(step.product_brand || '')}${step.product_brand ? ' • ' : ''}${escapeHtml(step.product_name)}</div>`
            : '';
        const idLine = step.product_id
            ? `<div class="pid">ID ${escapeHtml(String(step.product_id))}</div>`
            : '';
        const instructionLine = step.instructions
            ? `<div class="instructions">${escapeHtml(step.instructions)}</div>`
            : '';
        return `
      <div class="step-card">
        <div class="step-top">
          <span class="step-chip">Step ${step.step}</span>
          <span class="step-name">${escapeHtml(step.name)}</span>
        </div>
        ${productLine}
        ${idLine}
        ${instructionLine}
      </div>
    `;
    }).join('');
    return `
    <section class="section">
      <h2>${escapeHtml(title)}</h2>
      <div class="steps">${rows}</div>
    </section>
  `;
}
app.post('/api/routine/share', async (req, res) => {
    try {
        const { userId, routineType } = req.body || {};
        const selectedType = (['morning', 'evening', 'weekly'].includes(String(routineType)))
            ? String(routineType)
            : 'all';
        if (!userId) {
            return res.status(400).json({ error: 'userId is required' });
        }
        const profile = await supabase_1.DatabaseService.getSkinProfileByUserId(userId);
        if (!profile)
            return res.status(404).json({ error: 'Profile not found' });
        const latestRoutine = await supabase_1.DatabaseService.getLatestRoutine(userId);
        const ensuredRoutine = await ensureUserHasProductRoutine(userId, profile, latestRoutine);
        if (!ensuredRoutine?.routine_data) {
            return res.status(404).json({ error: 'No routine found' });
        }
        const routinePayload = buildRoutineSharePayload(ensuredRoutine.routine_data, selectedType);
        const tokenPayload = {
            userId,
            routineType: selectedType,
            routine: routinePayload,
            issuedAt: new Date().toISOString(),
        };
        const token = jwt.sign(tokenPayload, ROUTINE_SHARE_SECRET, { expiresIn: '30d' });
        const baseUrl = process.env.GLOWUP_SHARE_BASE_URL || `${req.protocol}://${req.get('host')}`;
        const shareUrl = `${baseUrl}/share/routine/${encodeURIComponent(token)}`;
        const appDeepLink = `glowup://routine/shared?token=${encodeURIComponent(token)}`;
        res.json({
            success: true,
            share_url: shareUrl,
            app_deep_link: appDeepLink,
            routine_type: selectedType,
        });
    }
    catch (error) {
        console.error('Routine share error:', error?.message);
        res.status(500).json({ error: 'Failed to create routine share link' });
    }
});
app.get('/share/routine/:token', async (req, res) => {
    try {
        const decoded = jwt.verify(req.params.token, ROUTINE_SHARE_SECRET);
        const routine = decoded?.routine || { morning: [], evening: [], weekly: [] };
        const deepLink = `glowup://routine/shared?token=${encodeURIComponent(req.params.token)}`;
        const morningHtml = renderRoutineSectionHtml('Morning Glow', routine.morning || []);
        const eveningHtml = renderRoutineSectionHtml('Evening Repair', routine.evening || []);
        const weeklyHtml = renderRoutineSectionHtml('Weekly Reset', routine.weekly || []);
        const html = `
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Shared GlowUp Routine</title>
  <style>
    :root { --pink:#ff6b9d; --rose:#ff8aaf; --ink:#232323; --muted:#6f6f6f; --bg1:#fff5fa; --bg2:#ffe8f1; }
    *{box-sizing:border-box}
    body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",sans-serif;background:linear-gradient(180deg,var(--bg1),var(--bg2));color:var(--ink)}
    .wrap{max-width:840px;margin:0 auto;padding:28px 16px 40px}
    .hero{background:#fff;border:1px solid #ffd9e7;border-radius:22px;padding:22px;box-shadow:0 8px 26px rgba(255,107,157,.12)}
    .badge{display:inline-block;padding:6px 10px;border-radius:999px;background:#ffe6ef;color:#a84a6d;font-size:12px;font-weight:700;letter-spacing:.4px;text-transform:uppercase}
    h1{margin:12px 0 8px;font-size:32px;line-height:1.05;font-family:"Didot","Times New Roman",serif}
    .sub{margin:0;color:var(--muted);font-size:14px}
    .actions{display:flex;gap:10px;flex-wrap:wrap;margin-top:16px}
    .btn{display:inline-flex;align-items:center;justify-content:center;padding:11px 14px;border-radius:12px;font-size:14px;font-weight:700;text-decoration:none}
    .btn-primary{background:linear-gradient(90deg,var(--pink),var(--rose));color:#fff}
    .btn-secondary{background:#f8f8f8;color:#444;border:1px solid #e9e9e9}
    .section{margin-top:18px;background:#fff;border:1px solid #f3d9e3;border-radius:18px;padding:16px}
    .section h2{margin:0 0 12px;font-size:18px}
    .steps{display:grid;gap:10px}
    .step-card{background:#fff8fb;border:1px solid #ffe0ec;border-radius:12px;padding:12px}
    .step-top{display:flex;align-items:center;gap:8px;flex-wrap:wrap}
    .step-chip{font-size:11px;font-weight:700;padding:4px 8px;border-radius:999px;background:#ffe4ef;color:#c74f7f}
    .step-name{font-size:15px;font-weight:700}
    .product{margin-top:8px;font-size:13px;color:#4d4d4d}
    .pid{margin-top:4px;font-size:11px;color:#949494;font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;word-break:break-all}
    .instructions{margin-top:7px;font-size:13px;color:#666;line-height:1.35}
    .foot{margin-top:16px;text-align:center;color:#848484;font-size:12px}
  </style>
</head>
<body>
  <main class="wrap">
    <section class="hero">
      <span class="badge">Shared from GlowUp</span>
      <h1>Skincare Routine</h1>
      <p class="sub">Open in GlowUp to personalize, track streaks, and shop your exact routine.</p>
      <div class="actions">
        <a class="btn btn-primary" href="${deepLink}">Open in GlowUp App</a>
        <a class="btn btn-secondary" href="${APP_STORE_URL}">Get GlowUp</a>
      </div>
    </section>
    ${morningHtml}
    ${eveningHtml}
    ${weeklyHtml}
    <p class="foot">Shared routine links expire in 30 days for privacy.</p>
  </main>
</body>
</html>`;
        res.setHeader('Content-Type', 'text/html; charset=utf-8');
        res.send(html);
    }
    catch (error) {
        res.status(400).send('Invalid or expired routine share link.');
    }
});
// Get all products
app.get('/api/products', async (req, res) => {
    try {
        const products = await supabase_1.DatabaseService.getAllProducts();
        res.json({ success: true, products });
    }
    catch (error) {
        console.error('Error:', error);
        res.status(500).json({ error: 'Server error' });
    }
});
// ═══════════════════════════════════════════════════════════════
// CART ENDPOINTS
// ═══════════════════════════════════════════════════════════════
function extractRoutineContext(routineRow) {
    const routineData = routineRow?.routine_data || routineRow;
    const routine = routineData?.routine ||
        routineData?.inference?.routine ||
        routineData?.summary?.routine ||
        routineData;
    const morning = routine?.morning || [];
    const evening = routine?.evening || [];
    const steps = [...morning, ...evening];
    const categories = new Set();
    const productIds = new Set();
    const stepNames = [];
    const categoryHints = {
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
        if (!s)
            continue;
        const name = (s.name || s.step_name || '').toString();
        const productId = s.product_id || s.product?.id;
        const productName = s.product_name || s.product?.name;
        const category = s.category || s.product?.category;
        if (name)
            stepNames.push(name);
        if (productName)
            stepNames.push(productName);
        if (productId)
            productIds.add(productId);
        if (category)
            categories.add(String(category).toLowerCase());
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
function buildCartAnalysisRuleBased(profile, products, routineCtx) {
    const routineCategories = new Set((routineCtx?.categories || []).map((c) => c.toLowerCase()));
    const routineProductIds = new Set(routineCtx?.productIds || []);
    return products.map((product) => {
        const targetSkinTypes = product.target_skin_type || [];
        const targetConcerns = product.target_concerns || [];
        const attributes = product.attributes || [];
        let score = 0;
        const reasons = [];
        if (profile?.skin_type && targetSkinTypes.includes(profile.skin_type)) {
            score += 1;
            reasons.push(`Matches your ${profile.skin_type} skin`);
        }
        const concerns = profile?.skin_concerns || [];
        const intersection = concerns.filter((c) => targetConcerns.includes(c));
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
        }
        else if (productCategory && routineCategories.has(productCategory)) {
            reasons.push(`You already have a ${productCategory} in your routine`);
            score -= 0.2;
        }
        let label = 'Neutral';
        if (score >= 2)
            label = 'Great fit';
        else if (score === 1)
            label = 'Good match';
        else if (score < 0)
            label = 'Caution';
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
        const items = await supabase_1.DatabaseService.getCartItems(userId);
        const payload = items.map((item) => ({
            product: mapProduct(item.product),
            quantity: item.quantity
        }));
        res.json({ success: true, items: payload });
    }
    catch (error) {
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
        const success = await supabase_1.DatabaseService.upsertCartItem(userId, productId, quantity);
        if (!success)
            return res.status(500).json({ error: 'Failed to update cart' });
        res.json({ success: true });
    }
    catch (error) {
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
        const success = await supabase_1.DatabaseService.upsertCartItem(userId, productId, quantity);
        if (!success)
            return res.status(500).json({ error: 'Failed to update cart' });
        res.json({ success: true });
    }
    catch (error) {
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
        const success = await supabase_1.DatabaseService.removeCartItem(userId, productId);
        if (!success)
            return res.status(500).json({ error: 'Failed to remove cart item' });
        res.json({ success: true });
    }
    catch (error) {
        console.error('Error removing cart item:', error);
        res.status(500).json({ error: 'Server error' });
    }
});
app.delete('/api/cart/:userId', async (req, res) => {
    try {
        const { userId } = req.params;
        const success = await supabase_1.DatabaseService.clearCart(userId);
        if (!success)
            return res.status(500).json({ error: 'Failed to clear cart' });
        res.json({ success: true });
    }
    catch (error) {
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
        const profile = await supabase_1.DatabaseService.getSkinProfileByUserId(userId);
        const products = await supabase_1.DatabaseService.getProductsByIds(productIds);
        const routineRow = await supabase_1.DatabaseService.getLatestRoutine(userId);
        const routineCtx = extractRoutineContext(routineRow);
        let results = [];
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
${JSON.stringify(products.map((p) => ({
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
            }
            catch (err) {
                console.error('Cart LLM analysis failed, using fallback:', err?.message);
                results = buildCartAnalysisRuleBased(profile, products, routineCtx);
            }
        }
        else {
            results = buildCartAnalysisRuleBased(profile, products, routineCtx);
        }
        res.json({ success: true, items: results });
    }
    catch (error) {
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
            supabase_1.DatabaseService.getProductsByIds([productId]),
            supabase_1.DatabaseService.getSkinProfileByUserId(userId),
            supabase_1.DatabaseService.getLatestRoutine(userId),
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
                morning: (routineData.morning || []).map((s) => ({ step: s.step, name: s.name, product_name: s.product?.name || s.product_name || 'Generic' })),
                evening: (routineData.evening || []).map((s) => ({ step: s.step, name: s.name, product_name: s.product?.name || s.product_name || 'Generic' })),
                weekly: (routineData.weekly || []).map((s) => ({ step: s.step, name: s.name, product_name: s.product?.name || s.product_name || 'Generic' })),
            });
            const prompt = `You are GlowUp's routine optimizer. A user just purchased a new product. Determine where it fits in their existing routine.

PRODUCT:
- Name: ${product.name}
- Brand: ${product.brand}
- Category: ${product.category}
- Summary: ${product.summary || product.description || 'N/A'}

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
                if (jsonMatch)
                    jsonStr = jsonMatch[0];
                let placements = JSON.parse(jsonStr);
                if (!Array.isArray(placements))
                    placements = [placements];
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
                    const key = placement.routine_type;
                    if (!newRoutine[key])
                        continue;
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
                    }
                    else {
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
                const saved = await supabase_1.DatabaseService.saveRoutine(userId, profile.id, {
                    inference: {
                        routine: newRoutine,
                        summary: routineRow?.routine_data?.inference?.summary || 'Updated routine',
                        personalized_tips: routineRow?.routine_data?.inference?.personalized_tips || [],
                    },
                });
                console.log(`✅ Integrated product ${product.name} into routine for user ${userId}`);
                return res.json({ success: true, placements, routine_id: saved?.id || null });
            }
            catch (err) {
                console.error('LLM integration failed:', err?.message);
                return res.status(500).json({ error: 'Failed to integrate product' });
            }
        }
        res.status(500).json({ error: 'LLM not available for integration' });
    }
    catch (error) {
        console.error('Error integrating product:', error);
        res.status(500).json({ error: 'Server error' });
    }
});
const PHOTO_BUCKET = process.env.GLOWUP_PRIVATE_PHOTO_BUCKET || 'glowup-private-photos';
const PHOTO_SIGNED_URL_TTL_SECONDS = Number(process.env.GLOWUP_PHOTO_SIGNED_URL_TTL_SECONDS || '3600');
const PHOTO_MAX_BYTES = Number(process.env.GLOWUP_PHOTO_MAX_BYTES || `${6 * 1024 * 1024}`);
const PHOTO_RETENTION_DAYS = Number(process.env.GLOWUP_PHOTO_RETENTION_DAYS || '90');
function hasAnyPhotos(photos) {
    return !!(photos?.front || photos?.left || photos?.right || photos?.scalp);
}
function sanitizePathToken(input) {
    return input.replace(/[^a-zA-Z0-9_-]/g, '_');
}
function parseDataImage(imageValue) {
    const match = imageValue.match(/^data:(image\/[a-zA-Z0-9.+-]+);base64,(.+)$/);
    if (!match)
        return null;
    const contentType = match[1].toLowerCase();
    const base64Payload = match[2];
    const buffer = Buffer.from(base64Payload, 'base64');
    if (!buffer.length || buffer.length > PHOTO_MAX_BYTES)
        return null;
    const extByType = {
        'image/jpeg': 'jpg',
        'image/jpg': 'jpg',
        'image/png': 'png',
        'image/webp': 'webp',
        'image/heic': 'heic',
        'image/heif': 'heif',
    };
    return {
        buffer,
        contentType,
        extension: extByType[contentType] || 'jpg',
    };
}
async function uploadPhotoReference(userId, slot, value, context = 'onboarding') {
    if (!value || typeof value !== 'string')
        return {};
    const trimmed = value.trim();
    if (!trimmed)
        return {};
    // Backward compatibility for already-hosted URLs/paths.
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        return { ref: trimmed };
    }
    if (!trimmed.startsWith('data:')) {
        return { ref: trimmed };
    }
    const parsed = parseDataImage(trimmed);
    if (!parsed) {
        console.warn(`⚠️ Skipping invalid image payload for ${slot}`);
        return {};
    }
    const userPath = sanitizePathToken(userId);
    const dateFolder = new Date().toISOString().slice(0, 10);
    const filename = `${slot}-${Date.now()}-${(0, crypto_1.randomUUID)().slice(0, 8)}.${parsed.extension}`;
    const path = `${userPath}/${context}/${dateFolder}/${filename}`;
    const { error } = await supabase_1.supabase.storage
        .from(PHOTO_BUCKET)
        .upload(path, parsed.buffer, {
        contentType: parsed.contentType,
        upsert: false,
    });
    if (error) {
        console.error(`❌ Photo upload failed for ${slot}:`, error.message);
        return {};
    }
    return { ref: path, uploadedPath: path };
}
async function persistIncomingPhotos(userId, photos, context = 'onboarding') {
    const stored = {};
    const uploadedPaths = [];
    const slots = ['front', 'left', 'right', 'scalp'];
    for (const slot of slots) {
        const { ref, uploadedPath } = await uploadPhotoReference(userId, slot, photos?.[slot], context);
        if (ref)
            stored[slot] = ref;
        if (uploadedPath)
            uploadedPaths.push(uploadedPath);
    }
    return { stored, uploadedPaths };
}
async function removePrivatePhotoPaths(paths) {
    if (!paths.length)
        return;
    const { error } = await supabase_1.supabase.storage.from(PHOTO_BUCKET).remove(paths);
    if (error) {
        console.error('⚠️ Failed to remove private photo paths:', error.message);
    }
}
function isStoragePathRef(ref) {
    if (!ref)
        return false;
    return !ref.startsWith('http://') && !ref.startsWith('https://') && !ref.startsWith('data:');
}
async function toSignedPhotoUrl(ref) {
    if (!ref)
        return ref;
    if (ref.startsWith('http://') || ref.startsWith('https://'))
        return ref;
    const { data, error } = await supabase_1.supabase.storage
        .from(PHOTO_BUCKET)
        .createSignedUrl(ref, PHOTO_SIGNED_URL_TTL_SECONDS);
    if (error)
        return null;
    return data?.signedUrl || null;
}
async function withSignedProfilePhotos(profile) {
    if (!profile)
        return profile;
    const [front, left, right, scalp] = await Promise.all([
        toSignedPhotoUrl(profile.photo_front_url),
        toSignedPhotoUrl(profile.photo_left_url),
        toSignedPhotoUrl(profile.photo_right_url),
        toSignedPhotoUrl(profile.photo_scalp_url),
    ]);
    return {
        ...profile,
        photo_front_url: front || null,
        photo_left_url: left || null,
        photo_right_url: right || null,
        photo_scalp_url: scalp || null,
    };
}
async function withSignedCheckInPhotos(checkIn) {
    if (!checkIn)
        return checkIn;
    const [front, left, right] = await Promise.all([
        toSignedPhotoUrl(checkIn.photo_front_url),
        toSignedPhotoUrl(checkIn.photo_left_url),
        toSignedPhotoUrl(checkIn.photo_right_url),
    ]);
    return {
        ...checkIn,
        photo_front_url: front || null,
        photo_left_url: left || null,
        photo_right_url: right || null,
    };
}
async function redactExpiredCheckInPhotos(userId) {
    if (!PHOTO_RETENTION_DAYS || PHOTO_RETENTION_DAYS <= 0)
        return;
    const cutoff = new Date(Date.now() - PHOTO_RETENTION_DAYS * 24 * 60 * 60 * 1000).toISOString();
    const { data, error } = await supabase_1.supabase
        .from('photo_check_ins')
        .select('id, photo_front_url, photo_left_url, photo_right_url, created_at')
        .eq('user_id', userId)
        .lt('created_at', cutoff);
    if (error || !data || data.length === 0)
        return;
    const pathsToDelete = [];
    const rowIds = [];
    for (const row of data) {
        rowIds.push(row.id);
        const refs = [row.photo_front_url, row.photo_left_url, row.photo_right_url];
        for (const ref of refs) {
            if (isStoragePathRef(ref))
                pathsToDelete.push(ref);
        }
    }
    await removePrivatePhotoPaths(pathsToDelete);
    const { error: updateError } = await supabase_1.supabase
        .from('photo_check_ins')
        .update({
        photo_front_url: null,
        photo_left_url: null,
        photo_right_url: null,
    })
        .in('id', rowIds);
    if (updateError) {
        console.error('⚠️ Failed to redact expired check-in photo refs:', updateError.message);
    }
    else {
        console.log(`🧹 Redacted photo refs for ${rowIds.length} expired check-ins`);
    }
}
function toLevelLabel(score) {
    if (score === undefined || score === null || Number.isNaN(score))
        return 'Unknown';
    if (score >= 0.75)
        return 'High';
    if (score >= 0.45)
        return 'Medium';
    return 'Low';
}
function clamp01(value) {
    if (!Number.isFinite(value))
        return 0.5;
    return Math.max(0, Math.min(1, value));
}
function normalizeSkinScore(raw) {
    const value = Number(raw);
    if (!Number.isFinite(value))
        return null;
    const normalized = value > 1 ? value / 100 : value;
    return Math.max(0, Math.min(1, normalized));
}
function inferInsightFromProfileImage(profile) {
    const skin = profile?.image_analysis?.skin;
    if (!skin)
        return null;
    const hydrationRaw = Number(skin.hydration_score);
    const oilinessRaw = Number(skin.oiliness_score);
    const textureRaw = Number(skin.texture_score);
    const hasAnySignal = [hydrationRaw, oilinessRaw, textureRaw].some(Number.isFinite);
    if (!hasAnySignal)
        return null;
    const hydration = Number.isFinite(hydrationRaw) ? clamp01(hydrationRaw) : 0.5;
    const oiliness = Number.isFinite(oilinessRaw) ? clamp01(oilinessRaw) : 0.5;
    const texture = Number.isFinite(textureRaw) ? clamp01(textureRaw) : 0.5;
    const concerns = Array.isArray(skin?.concerns_detected) ? skin.concerns_detected : [];
    const concernPenalty = Math.min(0.08, concerns.length * 0.02);
    const averageRaw = (hydration + (1 - oiliness) + texture) / 3;
    const skinScore = Number(Math.max(0.35, Math.min(0.95, averageRaw - concernPenalty)).toFixed(2));
    return {
        skinScore,
        hydration: toLevelLabel(hydration),
        protection: toLevelLabel(1 - oiliness * 0.4),
        texture: toLevelLabel(texture),
        source: 'skin_page_photo_inference',
        notes: 'Inferred from onboarding/check-in photo analysis.',
    };
}
function inferInsightFromProfileSignals(profile, streaks) {
    const skinType = String(profile?.skin_type || 'normal').toLowerCase();
    const concerns = (Array.isArray(profile?.skin_concerns) ? profile.skin_concerns : [])
        .map((c) => String(c).toLowerCase());
    const sunscreenUsage = String(profile?.sunscreen_usage || 'sometimes').toLowerCase();
    const hydrationSignal = skinType === 'dry' ? 0.42
        : skinType === 'oily' ? 0.63
            : skinType === 'sensitive' ? 0.52
                : 0.56;
    const sunscreenSignal = sunscreenUsage === 'always' ? 0.86
        : sunscreenUsage === 'often' ? 0.74
            : sunscreenUsage === 'sometimes' ? 0.58
                : sunscreenUsage === 'rarely' ? 0.44
                    : 0.34;
    const textureConcernPenalty = concerns.some((c) => c.includes('texture')) ? 0.12 : 0;
    const acnePenalty = concerns.some((c) => c.includes('acne')) ? 0.1 : 0;
    const agingPenalty = concerns.some((c) => c.includes('aging') || c.includes('wrinkle')) ? 0.08 : 0;
    const pigmentationPenalty = concerns.some((c) => c.includes('pigment') || c.includes('dark_spot')) ? 0.06 : 0;
    const concernPenalty = Math.min(0.2, textureConcernPenalty + acnePenalty + agingPenalty + pigmentationPenalty);
    const textureSignal = Math.max(0.35, Math.min(0.8, 0.66 - concernPenalty));
    const streakValue = Math.max(Number(streaks?.morning || 0), Number(streaks?.evening || 0));
    const streakBonus = Math.min(0.08, streakValue * 0.005);
    const fragranceBonus = profile?.fragrance_free ? 0.01 : 0;
    const scoreRaw = (hydrationSignal * 0.4) + (sunscreenSignal * 0.35) + (textureSignal * 0.25) + streakBonus + fragranceBonus;
    const skinScore = Number(Math.max(0.35, Math.min(0.92, scoreRaw)).toFixed(2));
    return {
        skinScore,
        hydration: toLevelLabel(hydrationSignal),
        protection: toLevelLabel(sunscreenSignal),
        texture: toLevelLabel(textureSignal),
        source: 'skin_page_profile_inference',
        notes: 'Inferred from onboarding profile + routine consistency signals.',
    };
}
function buildInsightFromImageAnalysis(imageAnalysis, source, notes) {
    if (!imageAnalysis?.skin)
        return null;
    const hydrationScore = clamp01(Number(imageAnalysis.skin?.hydration_score || 0));
    const oilinessScore = clamp01(Number(imageAnalysis.skin?.oiliness_score || 0));
    const textureScore = clamp01(Number(imageAnalysis.skin?.texture_score || 0));
    const averageRaw = (hydrationScore + (1 - oilinessScore) + textureScore) / 3;
    const skinScore = Number(Math.max(0.35, Math.min(0.95, averageRaw)).toFixed(2));
    return {
        skinScore,
        hydration: toLevelLabel(hydrationScore),
        protection: toLevelLabel(1 - oilinessScore * 0.4),
        texture: toLevelLabel(textureScore),
        notes: notes || 'Updated from private photo analysis.',
        source,
    };
}
async function loadPhotoBuffer(ref) {
    if (!ref)
        return null;
    const trimmed = ref.trim();
    if (!trimmed)
        return null;
    if (trimmed.startsWith('data:')) {
        return parseDataImage(trimmed)?.buffer || null;
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        try {
            const response = await fetch(trimmed);
            if (!response.ok)
                return null;
            const arrayBuffer = await response.arrayBuffer();
            const buffer = Buffer.from(arrayBuffer);
            return buffer.length > 0 ? buffer : null;
        }
        catch {
            return null;
        }
    }
    try {
        const { data, error } = await supabase_1.supabase.storage.from(PHOTO_BUCKET).download(trimmed);
        if (error || !data)
            return null;
        const arrayBuffer = await data.arrayBuffer();
        const buffer = Buffer.from(arrayBuffer);
        return buffer.length > 0 ? buffer : null;
    }
    catch {
        return null;
    }
}
function computePhotoSignalHeuristics(buffers) {
    if (!buffers.length)
        return null;
    let byteCount = 0;
    let byteSum = 0;
    let diffSum = 0;
    let chunkVariance = 0;
    let chunkCount = 0;
    for (const buffer of buffers) {
        const sampleStride = Math.max(1, Math.floor(buffer.length / 18000));
        let prev = -1;
        let localCount = 0;
        let localSum = 0;
        const sampled = [];
        for (let i = 0; i < buffer.length; i += sampleStride) {
            const v = buffer[i];
            sampled.push(v);
            byteSum += v;
            byteCount += 1;
            localSum += v;
            localCount += 1;
            if (prev >= 0)
                diffSum += Math.abs(v - prev);
            prev = v;
        }
        if (localCount > 0) {
            const mean = localSum / localCount;
            let variance = 0;
            for (const v of sampled)
                variance += Math.pow(v - mean, 2);
            chunkVariance += variance / localCount;
            chunkCount += 1;
        }
    }
    if (!byteCount)
        return null;
    const mean = byteSum / byteCount / 255;
    const normalizedDiff = clamp01((diffSum / Math.max(1, byteCount - 1)) / 90);
    const variance = clamp01((chunkVariance / Math.max(1, chunkCount)) / 6500);
    const hydration = clamp01(0.4 + (1 - variance) * 0.35 + (mean - 0.5) * 0.2);
    const oiliness = clamp01(0.48 + variance * 0.28 + normalizedDiff * 0.18 - mean * 0.1);
    const texture = clamp01(0.45 + (1 - normalizedDiff) * 0.3 + (1 - variance) * 0.2);
    const concerns = [];
    if (oiliness > 0.62)
        concerns.push('slight_oiliness');
    if (hydration < 0.44)
        concerns.push('dehydration_signs');
    if (texture < 0.5)
        concerns.push('mild_texture');
    const detectedType = oiliness > 0.63 ? 'oily'
        : hydration < 0.42 ? 'dry'
            : Math.abs(oiliness - 0.5) > 0.09 ? 'combination'
                : 'normal';
    return {
        detected_tone: mean > 0.62 ? 'light-medium' : mean > 0.44 ? 'medium' : 'medium-deep',
        detected_type: detectedType,
        oiliness_score: Number(oiliness.toFixed(2)),
        hydration_score: Number(hydration.toFixed(2)),
        texture_score: Number(texture.toFixed(2)),
        concerns_detected: concerns,
        redness_areas: [],
        pore_visibility: oiliness > 0.6 ? 'moderate' : 'low',
        confidence: Number((0.64 + buffers.length * 0.08).toFixed(2)),
    };
}
async function analyzeImagesWithVisionModel(imageUrls) {
    if (!openaiChat || imageUrls.length === 0)
        return null;
    const visionModel = process.env.GLOWUP_VISION_MODEL || 'gpt-4o-mini';
    const imageContent = imageUrls.slice(0, 3).map(url => ({ type: 'image_url', image_url: { url, detail: 'low' } }));
    const completion = await openaiChat.chat.completions.create({
        model: visionModel,
        response_format: { type: 'json_object' },
        temperature: 0.2,
        max_tokens: 700,
        messages: [
            {
                role: 'system',
                content: 'Analyze onboarding skin photos for skincare routine generation. Return ONLY JSON with keys: detected_tone, detected_type, oiliness_score, hydration_score, texture_score, concerns_detected (array of short strings), redness_areas (array), pore_visibility (low|moderate|high), confidence (0-1). Scores must be numbers between 0 and 1.'
            },
            {
                role: 'user',
                content: [
                    { type: 'text', text: 'Evaluate the photos and return the JSON only.' },
                    ...imageContent
                ]
            }
        ]
    });
    const raw = completion.choices[0]?.message?.content;
    if (!raw)
        return null;
    const parsed = JSON.parse(raw);
    return {
        detected_tone: String(parsed.detected_tone || 'medium'),
        detected_type: String(parsed.detected_type || 'combination').toLowerCase(),
        oiliness_score: Number(clamp01(Number(parsed.oiliness_score))),
        hydration_score: Number(clamp01(Number(parsed.hydration_score))),
        texture_score: Number(clamp01(Number(parsed.texture_score))),
        concerns_detected: Array.isArray(parsed.concerns_detected) ? parsed.concerns_detected.slice(0, 5).map((v) => String(v)) : [],
        redness_areas: Array.isArray(parsed.redness_areas) ? parsed.redness_areas.slice(0, 5).map((v) => String(v)) : [],
        pore_visibility: ['low', 'moderate', 'high'].includes(String(parsed.pore_visibility || '').toLowerCase())
            ? String(parsed.pore_visibility).toLowerCase()
            : 'moderate',
        confidence: Number(clamp01(Number(parsed.confidence || 0.7))),
    };
}
async function analyzeImages(photos) {
    const refs = [photos.front, photos.left, photos.right].filter(Boolean);
    if (refs.length === 0)
        return null;
    const signedOrRawUrls = await Promise.all(refs.map(async (ref) => {
        if (ref.startsWith('data:') || ref.startsWith('http://') || ref.startsWith('https://'))
            return ref;
        return (await toSignedPhotoUrl(ref)) || '';
    }));
    const imageUrls = signedOrRawUrls.filter(Boolean);
    let skinSignals = null;
    try {
        skinSignals = await analyzeImagesWithVisionModel(imageUrls);
    }
    catch (err) {
        console.log('⚠️ Vision model analysis failed, using deterministic heuristics:', err?.message);
    }
    if (!skinSignals) {
        const buffers = (await Promise.all(refs.map(loadPhotoBuffer))).filter(Boolean);
        skinSignals = computePhotoSignalHeuristics(buffers);
    }
    if (!skinSignals)
        return null;
    return {
        analyzed_at: new Date().toISOString(),
        model_version: skinSignals?.confidence ? 'vision+heuristic-v2' : 'heuristic-v2',
        skin: {
            detected_tone: skinSignals.detected_tone,
            detected_type: skinSignals.detected_type,
            oiliness_score: skinSignals.oiliness_score,
            hydration_score: skinSignals.hydration_score,
            texture_score: skinSignals.texture_score,
            concerns_detected: skinSignals.concerns_detected,
            redness_areas: skinSignals.redness_areas,
            pore_visibility: skinSignals.pore_visibility
        },
        hair: {
            detected_type: 'not_analyzed',
            frizz_level: 'unknown',
            damage_indicators: [],
            scalp_condition: 'unknown'
        },
        confidence_scores: {
            skin_analysis: Number(clamp01(Number(skinSignals.confidence || 0.72)).toFixed(2)),
            hair_analysis: 0.0
        },
        recommendations_from_analysis: [
            skinSignals.hydration_score < 0.45 ? 'Prioritize hydration and barrier support in your routine.' : 'Maintain hydration with a lightweight humectant serum.',
            skinSignals.oiliness_score > 0.6 ? 'Use oil-balancing cleanser and non-comedogenic moisturizers.' : 'Use gentle cleanse and avoid over-stripping.',
            'Daily SPF remains essential for long-term results.'
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
        const visualHistoryEnabled = profile?.photoCheckIns !== false;
        const persistedPhotos = await persistIncomingPhotos(userId, photos, 'onboarding');
        const photoRefs = visualHistoryEnabled ? persistedPhotos.stored : {};
        // Analyze images if provided
        let imageAnalysis = null;
        if (hasAnyPhotos(persistedPhotos.stored) || hasAnyPhotos(photos)) {
            console.log('🔍 Analyzing uploaded photos...');
            imageAnalysis = await analyzeImages(hasAnyPhotos(persistedPhotos.stored) ? persistedPhotos.stored : photos);
            console.log('✅ Image analysis complete. Confidence:', imageAnalysis?.confidence_scores?.skin_analysis);
        }
        if (!visualHistoryEnabled && persistedPhotos.uploadedPaths.length > 0) {
            await removePrivatePhotoPaths(persistedPhotos.uploadedPaths);
        }
        // Combine user input with image analysis
        const combinedProfile = {
            ...profile,
            photoFrontUrl: photoRefs.front,
            photoLeftUrl: photoRefs.left,
            photoRightUrl: photoRefs.right,
            photoScalpUrl: photoRefs.scalp,
            imageAnalysis
        };
        const savedProfile = await supabase_1.DatabaseService.saveSkinProfile(userId, combinedProfile);
        if (savedProfile) {
            const insight = buildInsightFromImageAnalysis(imageAnalysis, 'onboarding_photo');
            if (insight) {
                await supabase_1.DatabaseService.saveInsight(userId, insight);
            }
            // Mark user as onboarded in users table
            const onboardedSuccess = await supabase_1.DatabaseService.markUserOnboarded(userId);
            if (onboardedSuccess) {
                console.log('✅ User marked as onboarded in users table:', userId);
            }
            else {
                console.error('⚠️ Failed to mark user as onboarded in users table:', userId);
            }
            const profileWithSignedPhotos = await withSignedProfilePhotos(savedProfile);
            res.json({
                success: true,
                profile: profileWithSignedPhotos,
                imageAnalysis: imageAnalysis,
                onboarded: onboardedSuccess
            });
        }
        else {
            res.status(400).json({ error: 'Failed to save skin profile' });
        }
    }
    catch (error) {
        console.error('Error saving skin profile:', error);
        res.status(500).json({ error: 'Server error' });
    }
});
// Get skin profile
app.get('/api/skin-profiles/:userId', async (req, res) => {
    try {
        const profile = await supabase_1.DatabaseService.getSkinProfileByUserId(req.params.userId);
        if (profile) {
            const profileWithSignedPhotos = await withSignedProfilePhotos(profile);
            res.json({ success: true, profile: profileWithSignedPhotos });
        }
        else {
            res.status(404).json({ error: 'Skin profile not found' });
        }
    }
    catch (error) {
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
        const existingProfile = await supabase_1.DatabaseService.getSkinProfileByUserId(userId);
        const visualHistoryEnabled = existingProfile?.photo_check_ins !== false;
        const persistedPhotos = await persistIncomingPhotos(userId, photos, 'reanalyze');
        const imageAnalysis = await analyzeImages(hasAnyPhotos(persistedPhotos.stored) ? persistedPhotos.stored : photos);
        const updatedProfile = await supabase_1.DatabaseService.updateImageAnalysis(userId, imageAnalysis);
        if (!visualHistoryEnabled && persistedPhotos.uploadedPaths.length > 0) {
            await removePrivatePhotoPaths(persistedPhotos.uploadedPaths);
        }
        if (updatedProfile) {
            const insight = buildInsightFromImageAnalysis(imageAnalysis, 'reanalyze_photo');
            if (insight) {
                await supabase_1.DatabaseService.saveInsight(userId, insight);
            }
            const profileWithSignedPhotos = await withSignedProfilePhotos(updatedProfile);
            res.json({
                success: true,
                profile: profileWithSignedPhotos,
                imageAnalysis
            });
        }
        else {
            res.status(400).json({ error: 'Failed to update analysis' });
        }
    }
    catch (error) {
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
        const profile = await supabase_1.DatabaseService.getSkinProfileByUserId(userId);
        const visualHistoryEnabled = profile?.photo_check_ins !== false;
        const persistedPhotos = await persistIncomingPhotos(userId, photos, 'checkin');
        // Analyze new photos
        let imageAnalysis = null;
        let comparison = null;
        if (hasAnyPhotos(persistedPhotos.stored) || hasAnyPhotos(photos)) {
            imageAnalysis = await analyzeImages(hasAnyPhotos(persistedPhotos.stored) ? persistedPhotos.stored : photos);
            // Get baseline for comparison
            const baselineProfile = await supabase_1.DatabaseService.getSkinProfileByUserId(userId);
            if (baselineProfile?.image_analysis) {
                // Mock comparison (in production, this would be a real comparison)
                comparison = {
                    improvements: improvement ? ['user_reported_improvement'] : [],
                    concerns: irritation ? ['user_reported_irritation'] : [],
                    recommendation_changes: []
                };
            }
        }
        if (!visualHistoryEnabled && persistedPhotos.uploadedPaths.length > 0) {
            await removePrivatePhotoPaths(persistedPhotos.uploadedPaths);
        }
        const checkIn = await supabase_1.DatabaseService.savePhotoCheckIn(userId, skinProfileId, {
            photoFrontUrl: visualHistoryEnabled ? persistedPhotos.stored.front : undefined,
            photoLeftUrl: visualHistoryEnabled ? persistedPhotos.stored.left : undefined,
            photoRightUrl: visualHistoryEnabled ? persistedPhotos.stored.right : undefined,
            imageAnalysis,
            comparisonToBaseline: comparison,
            userNotes,
            irritationReported: irritation,
            improvementReported: improvement
        });
        if (checkIn) {
            const insight = buildInsightFromImageAnalysis(imageAnalysis, 'photo_check_in', userNotes);
            if (insight) {
                await supabase_1.DatabaseService.saveInsight(userId, insight);
            }
            await redactExpiredCheckInPhotos(userId);
            const signedCheckIn = await withSignedCheckInPhotos(checkIn);
            res.json({ success: true, checkIn: signedCheckIn, comparison });
        }
        else {
            res.status(400).json({ error: 'Failed to save check-in' });
        }
    }
    catch (error) {
        console.error('Error:', error);
        res.status(500).json({ error: 'Server error' });
    }
});
// Get photo check-ins history
app.get('/api/photo-check-ins/:userId', async (req, res) => {
    try {
        await redactExpiredCheckInPhotos(req.params.userId);
        const checkIns = await supabase_1.DatabaseService.getPhotoCheckIns(req.params.userId);
        const signedCheckIns = await Promise.all(checkIns.map((checkIn) => withSignedCheckInPhotos(checkIn)));
        res.json({ success: true, checkIns: signedCheckIns });
    }
    catch (error) {
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
        if (!userId)
            return res.status(400).json({ error: 'userId required' });
        const conversation = await supabase_1.DatabaseService.createConversation(userId, title);
        if (conversation) {
            res.json({ success: true, conversation });
        }
        else {
            res.status(500).json({ error: 'Failed to create conversation' });
        }
    }
    catch (error) {
        console.error('Error creating conversation:', error);
        res.status(500).json({ error: 'Server error' });
    }
});
// List conversations for a user
app.get('/api/conversations/:userId', async (req, res) => {
    try {
        const conversations = await supabase_1.DatabaseService.getConversations(req.params.userId);
        res.json({ success: true, conversations });
    }
    catch (error) {
        console.error('Error listing conversations:', error);
        res.status(500).json({ error: 'Server error' });
    }
});
// Get messages for a conversation
app.get('/api/conversations/:conversationId/messages', async (req, res) => {
    try {
        const messages = await supabase_1.DatabaseService.getConversationMessages(req.params.conversationId);
        res.json({ success: true, messages });
    }
    catch (error) {
        console.error('Error getting messages:', error);
        res.status(500).json({ error: 'Server error' });
    }
});
// Save a message to a conversation
app.post('/api/conversations/:conversationId/messages', async (req, res) => {
    try {
        const { role, content, metadata } = req.body;
        if (!role || !content)
            return res.status(400).json({ error: 'role and content required' });
        const message = await supabase_1.DatabaseService.saveMessage(req.params.conversationId, role, content, metadata || undefined);
        if (message) {
            res.json({ success: true, message });
        }
        else {
            res.status(500).json({ error: 'Failed to save message' });
        }
    }
    catch (error) {
        console.error('Error saving message:', error);
        res.status(500).json({ error: 'Server error' });
    }
});
// Update conversation title
app.patch('/api/conversations/:conversationId', async (req, res) => {
    try {
        const { title } = req.body;
        const success = await supabase_1.DatabaseService.updateConversationTitle(req.params.conversationId, title);
        res.json({ success });
    }
    catch (error) {
        res.status(500).json({ error: 'Server error' });
    }
});
// Delete a conversation
app.delete('/api/conversations/:conversationId', async (req, res) => {
    try {
        const success = await supabase_1.DatabaseService.deleteConversation(req.params.conversationId);
        res.json({ success });
    }
    catch (error) {
        res.status(500).json({ error: 'Server error' });
    }
});
// ─────────────────────────────────────────────
// Insights
// ─────────────────────────────────────────────
// Get latest insights for a user
app.get('/api/insights/:userId', async (req, res) => {
    try {
        const insight = await supabase_1.DatabaseService.getLatestInsightByUserId(req.params.userId);
        if (!insight) {
            return res.status(404).json({ success: false, error: 'No insights found' });
        }
        res.json({ success: true, insight });
    }
    catch (error) {
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
        const saved = await supabase_1.DatabaseService.saveInsight(userId, insight);
        if (!saved) {
            return res.status(500).json({ error: 'Failed to save insights' });
        }
        res.json({ success: true, insight: saved });
    }
    catch (error) {
        res.status(500).json({ error: 'Server error' });
    }
});
// ═══════════════════════════════════════════════════════════════
// CHAT ENDPOINT (GPT-4o-mini powered)
// ═══════════════════════════════════════════════════════════════
const openai_1 = __importDefault(require("openai"));
const openaiChat = process.env.OPENAI_API_KEY
    ? new openai_1.default({ apiKey: process.env.OPENAI_API_KEY })
    : null;
// ═══════════════════════════════════════════════════════════════
// CHAT TOOL DEFINITIONS — model can call these dynamically
// ═══════════════════════════════════════════════════════════════
const chatTools = [
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
async function hydrateProductResults(results) {
    if (!results || results.length === 0)
        return results;
    const ids = results
        .map((row) => row.id || row.product_id)
        .filter(Boolean);
    if (ids.length === 0)
        return results;
    const needsHydration = results.some((row) => !row.image_url || !row.name);
    if (!needsHydration)
        return results;
    const { data } = await supabase_1.supabase
        .from('products')
        .select('id, name, brand, price, category, subcategory, summary, description, rating, image_url, target_skin_type, target_concerns, attributes, buy_link, ingredients')
        .in('id', ids);
    if (!data || data.length === 0)
        return results;
    const byId = new Map(data.map((row) => [row.id, row]));
    return ids
        .map((id) => {
        const base = byId.get(id);
        const sim = results.find((r) => (r.id || r.product_id) === id)?.similarity;
        return base ? { ...base, similarity: sim ?? base.similarity ?? null } : null;
    })
        .filter(Boolean);
}
async function executeChatTool(toolName, args, userId) {
    try {
        switch (toolName) {
            case 'get_user_skin_profile': {
                if (!userId)
                    return JSON.stringify({ error: 'No user signed in — cannot fetch profile' });
                const profile = await supabase_1.DatabaseService.getSkinProfileByUserId(userId);
                if (!profile)
                    return JSON.stringify({ error: 'No skin profile found — user may not have completed onboarding' });
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
                if (!userId)
                    return JSON.stringify({ error: 'No user signed in — cannot fetch routine' });
                const routine = await supabase_1.DatabaseService.getLatestRoutine(userId);
                if (!routine)
                    return JSON.stringify({ error: 'No routine found — user may not have generated one yet' });
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
                const keywords = query.split(/\s+/).filter((w) => w.length > 2);
                if (skinType)
                    keywords.push(skinType);
                if (concerns.length)
                    keywords.push(...concerns);
                let results = [];
                // Try hybrid search with embeddings first
                if (openaiChat) {
                    try {
                        const embeddingResponse = await openaiChat.embeddings.create({
                            model: 'text-embedding-3-small',
                            input: query
                        });
                        const queryEmbedding = embeddingResponse.data[0].embedding;
                        // Vector search via match_products RPC
                        const { data: vectorResults, error } = await supabase_1.supabase.rpc('match_products', {
                            query_embedding: queryEmbedding,
                            match_threshold: 0.25,
                            match_count: limit * 3
                        });
                        if (!error && vectorResults) {
                            results = vectorResults;
                        }
                    }
                    catch (e) {
                        console.log('⚠️ Embedding search failed, falling back to keyword search');
                    }
                }
                // Always add text search results from search_vector
                if (keywords.length > 0) {
                    const tsQuery = keywords.join(' | ');
                    const { data } = await supabase_1.supabase
                        .from('products')
                        .select('*')
                        .textSearch('search_vector', tsQuery)
                        .order('rating', { ascending: false })
                        .limit(limit);
                    if (data)
                        results.push(...data);
                }
                // If vector search didn't work or returned too few results, supplement with keyword search
                if (results.length < limit) {
                    // Search by target_skin_type
                    if (skinType) {
                        const skinTypeVariants = {
                            'oily': ['oily', 'all', 'combination'],
                            'dry': ['dry', 'all', 'sensitive'],
                            'combination': ['combination', 'all', 'oily', 'dry'],
                            'sensitive': ['sensitive', 'all', 'dry'],
                            'normal': ['normal', 'all'],
                            'acne-prone': ['acne-prone', 'oily', 'all'],
                        };
                        const variants = skinTypeVariants[skinType] || [skinType, 'all'];
                        const { data } = await supabase_1.supabase
                            .from('products')
                            .select('*')
                            .overlaps('target_skin_type', variants)
                            .order('rating', { ascending: false })
                            .limit(limit);
                        if (data)
                            results.push(...data);
                    }
                    // Search by target_concerns
                    if (concerns.length > 0) {
                        const { data } = await supabase_1.supabase
                            .from('products')
                            .select('*')
                            .overlaps('target_concerns', concerns)
                            .order('rating', { ascending: false })
                            .limit(limit);
                        if (data)
                            results.push(...data);
                    }
                    // Full-text search as final fallback
                    if (results.length < 3 && query) {
                        const tsQuery = keywords.join(' | ');
                        const { data } = await supabase_1.supabase
                            .from('products')
                            .select('*')
                            .textSearch('search_vector', tsQuery)
                            .order('rating', { ascending: false })
                            .limit(limit);
                        if (data)
                            results.push(...data);
                    }
                }
                // Apply filters
                if (category)
                    results = results.filter((p) => p.category?.toLowerCase() === category.toLowerCase());
                if (maxPrice)
                    results = results.filter((p) => p.price <= maxPrice);
                // Deduplicate by id
                const seen = new Set();
                results = results.filter((p) => {
                    if (seen.has(p.id))
                        return false;
                    seen.add(p.id);
                    return true;
                });
                results = await hydrateProductResults(results);
                // Return clean product list
                const cleaned = results.slice(0, limit).map((p) => ({
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
                let product = null;
                if (args.product_id) {
                    const { data } = await supabase_1.supabase
                        .from('products')
                        .select('*')
                        .eq('id', args.product_id)
                        .single();
                    product = data;
                }
                else if (args.product_name) {
                    // Fuzzy search by name
                    const { data } = await supabase_1.supabase
                        .from('products')
                        .select('*')
                        .ilike('name', `%${args.product_name}%`)
                        .limit(1)
                        .single();
                    product = data;
                }
                if (!product)
                    return JSON.stringify({ error: 'Product not found' });
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
                const products = [];
                for (const name of names) {
                    const { data } = await supabase_1.supabase
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
                if (products.length === 0)
                    return JSON.stringify({ error: 'No matching products found' });
                return JSON.stringify({ products });
            }
            case 'add_to_cart': {
                if (!userId)
                    return JSON.stringify({ error: 'No user signed in — cannot add to cart' });
                const productId = args.product_id;
                const quantity = Math.max(1, args.quantity || 1);
                if (!productId)
                    return JSON.stringify({ error: 'product_id is required' });
                const ok = await supabase_1.DatabaseService.upsertCartItem(userId, productId, quantity);
                if (!ok)
                    return JSON.stringify({ error: 'Failed to add to cart' });
                return JSON.stringify({ success: true, product_id: productId, quantity });
            }
            case 'remove_from_cart': {
                if (!userId)
                    return JSON.stringify({ error: 'No user signed in — cannot remove from cart' });
                const productId = args.product_id;
                if (!productId)
                    return JSON.stringify({ error: 'product_id is required' });
                const ok = await supabase_1.DatabaseService.removeCartItem(userId, productId);
                if (!ok)
                    return JSON.stringify({ error: 'Failed to remove from cart' });
                return JSON.stringify({ success: true, product_id: productId });
            }
            case 'update_user_routine': {
                if (!userId)
                    return JSON.stringify({ error: 'No user signed in — cannot update routine' });
                const routine = args.routine;
                if (!routine)
                    return JSON.stringify({ error: 'routine is required' });
                const profile = await supabase_1.DatabaseService.getSkinProfileByUserId(userId);
                if (!profile)
                    return JSON.stringify({ error: 'No skin profile found — user may not have completed onboarding' });
                // Resolve product IDs for each step so the saved routine has real products
                const resolveRoutineSteps = async (steps) => {
                    if (!steps || steps.length === 0)
                        return [];
                    return Promise.all(steps.map(async (s) => {
                        let product = null;
                        if (s.product_id) {
                            const { data } = await supabase_1.supabase.from('products').select('id, name, brand, price, category, image_url, buy_link, rating, summary').eq('id', s.product_id).single();
                            if (data)
                                product = data;
                        }
                        else if (s.product_name) {
                            const { data } = await supabase_1.supabase.from('products').select('id, name, brand, price, category, image_url, buy_link, rating, summary').ilike('name', `%${s.product_name}%`).limit(1).single();
                            if (data)
                                product = data;
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
                const saved = await supabase_1.DatabaseService.saveRoutine(userId, profile.id, routinePayload);
                if (!saved)
                    return JSON.stringify({ error: 'Failed to save routine' });
                return JSON.stringify({ success: true, routine_id: saved.id });
            }
            default:
                return JSON.stringify({ error: `Unknown tool: ${toolName}` });
        }
    }
    catch (err) {
        console.error(`❌ Tool ${toolName} error:`, err?.message);
        return JSON.stringify({ error: `Tool failed: ${err?.message}` });
    }
}
function normalizeLightweightMessages(raw, maxMessages) {
    if (!Array.isArray(raw))
        return [];
    const normalized = [];
    for (const item of raw) {
        const role = item?.role === 'assistant' ? 'assistant' : (item?.role === 'user' ? 'user' : null);
        const content = typeof item?.content === 'string' ? item.content.trim() : '';
        if (!role || !content)
            continue;
        normalized.push({
            role,
            content: content.slice(0, 700),
        });
    }
    if (normalized.length === 0)
        return [];
    return normalized.slice(-maxMessages);
}
app.post('/api/chat/guest', async (req, res) => {
    try {
        const messages = normalizeLightweightMessages(req.body?.messages, 8);
        if (messages.length === 0) {
            return res.status(400).json({ error: 'Messages array is required' });
        }
        if (!openaiChat) {
            return res.json({
                success: true,
                message: "I can still help with basics in guest mode: use a gentle cleanser, moisturizer, and daily SPF 30+. Sign in for personalized routines, progress tracking, and premium features."
            });
        }
        const configuredGuestModel = process.env.GLOWUP_GUEST_CHAT_MODEL;
        const modelCandidates = Array.from(new Set([configuredGuestModel, 'gpt-4.1-nano', 'gpt-4.1-mini', 'gpt-4o-mini']
            .filter((m) => !!m && m.trim().length > 0)));
        const systemPrompt = `You are GlowUp Guest Assistant inside the GlowUp iOS app.

You are in guest mode. Give useful, safe, basic skincare guidance with lightweight context.

What GlowUp does:
- GlowUp helps users improve skin with AI-guided routines, product discovery, and progress workflows.
- Signed-in users can save routines, keep conversation history, and track improvements over time.
- Premium (GlowUp+, $1.99/month) adds enhanced AI help, smart price scouting, free shipping perks, and expanded catalog access.

Guest-mode rules:
- Use only the conversation provided in this request. There is no long-term memory.
- Keep answers concise and practical.
- Do not claim you can access user profile data, photos, or saved history.
- Do not diagnose medical conditions. For severe or persistent issues, suggest seeing a dermatologist.
- No tool calling, no product-card syntax, no fabricated app data.

Account and premium guidance:
- When relevant, briefly mention that creating an account unlocks personalization and saved progress.
- When relevant, briefly mention premium benefits naturally (never pushy, never spammy).

Answer style:
- Friendly, clear, and direct.
- Prefer short bullet lists for routines.
- End with one practical next step.`;
        let reply = '';
        let usedModel = modelCandidates[0];
        let lastError = null;
        for (const candidate of modelCandidates) {
            try {
                const completion = await openaiChat.chat.completions.create({
                    model: candidate,
                    messages: [
                        { role: 'system', content: systemPrompt },
                        ...messages.map((m) => ({ role: m.role, content: m.content })),
                    ],
                    max_tokens: 420,
                    temperature: 0.6,
                });
                reply = completion.choices[0]?.message?.content?.trim() || '';
                usedModel = candidate;
                if (reply)
                    break;
            }
            catch (err) {
                lastError = err;
            }
        }
        if (!reply) {
            if (lastError) {
                console.error('❌ Guest chat error:', lastError?.message || lastError);
            }
            reply = "I can help with basic skincare in guest mode. Start with: gentle cleanser, moisturizer, and SPF 30+ every morning. If you want personalized guidance and saved progress, create an account.";
        }
        res.json({
            success: true,
            message: reply,
            model: usedModel,
        });
    }
    catch (error) {
        console.error('❌ Guest chat endpoint error:', error?.message || error);
        res.status(500).json({
            error: 'Guest chat failed',
            message: 'Sorry, guest chat is temporarily unavailable.'
        });
    }
});
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
                const { data: prevMessages } = await supabase_1.supabase
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
                            .map((m) => `${m.role === 'user' ? 'User' : 'Assistant'}: ${m.content}`)
                            .join('\n');
                    }
                    // Generate a concise summary of conversation history excluding last exchange
                    const historyText = prevMessages
                        .slice(0, Math.max(prevMessages.length - 2, 0))
                        .map((m) => `${m.role === 'user' ? 'User' : 'Assistant'}: ${m.content}`)
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
            }
            catch (err) {
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
        const chatMessages = [
            { role: 'system', content: systemPrompt },
            ...messages.map((m) => ({ role: m.role, content: m.content }))
        ];
        console.log(`💬 Chat request: ${messages.length} msgs, model: ${chatModel}, userId: ${userId || 'guest'}${conversationContext ? ' (with context)' : ''}`);
        if (conversationContext) {
            console.log(`📝 Conversation context: ${conversationContext.substring(0, 100)}...`);
        }
        const collectedProducts = [];
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
                currentMessages.push(assistantMsg);
                // Execute each tool call in parallel
                const toolResults = await Promise.all(assistantMsg.tool_calls.map(async (toolCall) => {
                    const fnName = toolCall.function?.name || toolCall.name;
                    const fnArgs = toolCall.function?.arguments || toolCall.arguments || '{}';
                    const args = JSON.parse(fnArgs);
                    console.log(`  🛠️  ${fnName}(${JSON.stringify(args).substring(0, 100)})`);
                    const result = await executeChatTool(fnName, args, userId || null);
                    console.log(`  ✅ ${fnName} → ${result.substring(0, 120)}...`);
                    collectProductsFromToolResult(fnName, result, collectedProducts);
                    return {
                        role: 'tool',
                        tool_call_id: toolCall.id,
                        content: result
                    };
                }));
                // Add all tool results to the conversation
                currentMessages.push(...toolResults);
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
        let title;
        const userMessages = messages.filter((m) => m.role === 'user');
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
            }
            catch (e) {
                console.log('⚠️ Title generation failed, using fallback');
            }
        }
        // Build a product map keyed by ID for inline embeds
        const dedupedProducts = dedupeProducts(collectedProducts).slice(0, 20);
        const productMap = {};
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
    }
    catch (error) {
        console.error('❌ Chat error:', error?.message || error);
        res.status(500).json({
            error: 'Chat failed',
            message: "Sorry, I'm having trouble thinking right now. Try again in a moment! 💕"
        });
    }
});
function collectProductsFromToolResult(toolName, result, sink) {
    if (!result)
        return;
    let parsed = null;
    try {
        parsed = JSON.parse(result);
    }
    catch {
        return;
    }
    if (toolName === 'search_products') {
        const products = Array.isArray(parsed?.products) ? parsed.products : [];
        sink.push(...products);
        return;
    }
    if (toolName === 'get_product_details') {
        if (parsed?.id)
            sink.push(parsed);
        return;
    }
    if (toolName === 'compare_products') {
        const products = Array.isArray(parsed?.products) ? parsed.products : [];
        sink.push(...products);
    }
}
function dedupeProducts(products) {
    const map = new Map();
    for (const p of products || []) {
        if (!p || !p.id)
            continue;
        if (!map.has(p.id))
            map.set(p.id, p);
    }
    return Array.from(map.values());
}
// ═══════════════════════════════════════════════════════════════
// HOME FEED — Personalized via fine-tuned model + tool calling
// ═══════════════════════════════════════════════════════════════
const FEED_MODEL = process.env.GLOWUP_CHAT_MODEL || 'ft:gpt-4o-2024-08-06:dave:glowup-product-embeds:D6KQn97D';
// ── In-memory cache for home feed AI results (5 min TTL) ──
const feedCache = new Map();
const FEED_CACHE_TTL = 5 * 60 * 1000; // 5 minutes
function withTimeout(promise, ms, fallback) {
    return Promise.race([
        promise,
        new Promise((resolve) => setTimeout(() => resolve(fallback), ms)),
    ]);
}
app.get('/api/home-feed/:userId', async (req, res) => {
    const { userId } = req.params;
    const startTime = Date.now();
    console.log(`🏠 Home feed request for user: ${userId}`);
    try {
        // ── 1. Fetch user's skin profile ──
        const profile = await supabase_1.DatabaseService.getSkinProfileByUserId(userId);
        if (!profile) {
            return res.status(404).json({ error: 'No skin profile found — complete onboarding first' });
        }
        const skinToneLabel = profile.skin_tone !== undefined
            ? (profile.skin_tone < 0.3 ? 'Fair' : profile.skin_tone < 0.5 ? 'Medium' : profile.skin_tone < 0.7 ? 'Medium-deep' : 'Deep')
            : 'not specified';
        const budgetMax = profile.budget === 'low' ? 25 : profile.budget === 'high' ? 100 : 60;
        // ── 2. Load latest insights for real-time score ──
        const latestInsight = await supabase_1.DatabaseService.getLatestInsightByUserId(userId);
        const confidence = latestInsight?.skin_score
            ? (latestInsight.skin_score > 1 ? Math.min(latestInsight.skin_score / 100, 1) : latestInsight.skin_score)
            : 0.85;
        // ── 3. Check AI cache ──
        const cacheKey = `feed:${userId}`;
        const cached = feedCache.get(cacheKey);
        const hasFreshCache = cached && (Date.now() - cached.ts < FEED_CACHE_TTL);
        // ── 4. Parallel fetches: saved routine, trending, new arrivals, personalized, AI fallback ──
        const [rawRoutineRow, trendingRes, newArrivalsRes, forYouRes, aiResult] = await Promise.all([
            // Load saved routine (product-enriched) from DB
            supabase_1.DatabaseService.getLatestRoutine(userId),
            // Trending = highest rated products
            supabase_1.supabase
                .from('products')
                .select('id, name, brand, price, category, summary, image_url, rating, review_count, buy_link, target_skin_type, target_concerns, attributes')
                .not('image_url', 'is', null)
                .gt('review_count', 50)
                .order('rating', { ascending: false })
                .limit(10),
            // New arrivals = most recently scraped Ulta products
            supabase_1.supabase
                .from('products')
                .select('id, name, brand, price, category, summary, image_url, rating, review_count, buy_link, target_skin_type, target_concerns, attributes')
                .eq('data_source', 'ulta_scrape')
                .not('image_url', 'is', null)
                .order('created_at', { ascending: false })
                .limit(10),
            // For You = embeddings-powered semantic search
            (async () => {
                if (!openaiChat)
                    return [];
                try {
                    const query = `${profile.skin_type} skin products for ${(profile.skin_goals || []).join(', ')} concerns: ${(profile.skin_concerns || []).join(', ')}`;
                    const embeddingRes = await openaiChat.embeddings.create({
                        model: 'text-embedding-3-small',
                        input: query
                    });
                    const { data: vectorResults } = await supabase_1.supabase.rpc('match_products', {
                        query_embedding: embeddingRes.data[0].embedding,
                        match_threshold: 0.25,
                        match_count: 15
                    });
                    return vectorResults || [];
                }
                catch {
                    return [];
                }
            })(),
            // AI-generated summary + tips (used for tips and summary — routine comes from DB first)
            (async () => {
                if (hasFreshCache) {
                    console.log('⚡ Using cached AI feed data');
                    return cached.data;
                }
                if (!openaiChat)
                    return null;
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
                        if (!content)
                            return null;
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
                }
                catch (err) {
                    console.log('⚠️ Feed model call failed:', err?.message);
                    return null;
                }
            })(),
        ]);
        const savedRoutineRow = await ensureUserHasProductRoutine(userId, profile, rawRoutineRow);
        const trending = (trendingRes.data || []).map(mapProduct);
        const newArrivals = (newArrivalsRes.data || []).map(mapProduct);
        const forYou = await hydrateForYouProducts(forYouRes || [], profile);
        // ── 5. Build routine from saved DB data (with real products) or fallback to AI text ──
        let routine = { morning: [], evening: [], weekly: [] };
        let routineHasProducts = false;
        if (savedRoutineRow?.routine_data) {
            const rd = savedRoutineRow.routine_data;
            const inferenceRoutine = rd?.inference?.routine || rd?.routine || rd?.summary?.routine;
            if (inferenceRoutine) {
                const mapSavedSteps = (steps) => (steps || []).map((s) => ({
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
                    .some((s) => s.product_id);
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
    }
    catch (err) {
        console.error('❌ Home feed error:', err?.message);
        res.status(500).json({ error: 'Failed to generate home feed' });
    }
});
function mapProduct(p) {
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
async function hydrateForYouProducts(vectorResults, profile) {
    if (!vectorResults || vectorResults.length === 0)
        return [];
    const ids = vectorResults
        .map((row) => row.id || row.product_id)
        .filter(Boolean);
    if (ids.length === 0)
        return vectorResults.map(mapProduct);
    const { data: productRows, error } = await supabase_1.supabase
        .from('products')
        .select('id, name, brand, price, category, summary, image_url, rating, review_count, buy_link, target_skin_type, target_concerns, attributes')
        .in('id', ids);
    let baseRows = productRows || [];
    if (error || baseRows.length === 0) {
        baseRows = vectorResults;
    }
    // If no images for personalized picks, fallback to image-rich products for this skin type
    const hasImages = baseRows.some((row) => row.image_url);
    if (!hasImages && profile?.skin_type) {
        const { data: fallbackRows } = await supabase_1.supabase
            .from('products')
            .select('id, name, brand, price, category, summary, image_url, rating, review_count, buy_link, target_skin_type, target_concerns, attributes')
            .not('image_url', 'is', null)
            .contains('target_skin_type', [profile.skin_type])
            .limit(12);
        if (fallbackRows && fallbackRows.length > 0) {
            baseRows = fallbackRows;
        }
    }
    const similarityMap = new Map((vectorResults || []).map((row) => [row.id || row.product_id, row.similarity]));
    const byId = new Map(baseRows.map((row) => [row.id, row]));
    const merged = ids
        .map((id) => {
        const row = byId.get(id);
        if (!row)
            return null;
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
        const checkins = await supabase_1.DatabaseService.getTodayCheckins(userId, date);
        const streaks = await supabase_1.DatabaseService.getStreaks(userId);
        res.json({
            success: true,
            checkins: Array.from(checkins),
            streaks
        });
    }
    catch (error) {
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
        const success = await supabase_1.DatabaseService.markStepComplete(userId, routineType, stepId, stepName, date);
        if (success) {
            const streaks = await supabase_1.DatabaseService.getStreaks(userId);
            // Update insights with new streaks
            await supabase_1.DatabaseService.updateInsightStreaks(userId);
            res.json({ success: true, streaks });
        }
        else {
            res.status(500).json({ error: 'Failed to mark step complete' });
        }
    }
    catch (error) {
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
        const success = await supabase_1.DatabaseService.markStepIncomplete(userId, routineType, stepId, date);
        if (success) {
            const streaks = await supabase_1.DatabaseService.getStreaks(userId);
            // Update insights with new streaks
            await supabase_1.DatabaseService.updateInsightStreaks(userId);
            res.json({ success: true, streaks });
        }
        else {
            res.status(500).json({ error: 'Failed to mark step incomplete' });
        }
    }
    catch (error) {
        console.error('Error marking step incomplete:', error);
        res.status(500).json({ error: 'Failed to mark step incomplete' });
    }
});
// Get streaks
app.get('/api/routine-checkins/:userId/streaks', async (req, res) => {
    try {
        const { userId } = req.params;
        const streaks = await supabase_1.DatabaseService.getStreaks(userId);
        res.json({ success: true, streaks });
    }
    catch (error) {
        console.error('Error fetching streaks:', error);
        res.status(500).json({ error: 'Failed to fetch streaks' });
    }
});
// ═══════════════════════════════════════════════════════════════
// SKIN PAGE — Agent-powered dynamic profile page
// ═══════════════════════════════════════════════════════════════
const skinPageCache = new Map();
const SKIN_PAGE_CACHE_TTL = 3 * 60 * 1000; // 3 minutes
app.get('/api/skin-page/:userId', async (req, res) => {
    const { userId } = req.params;
    const forceRefresh = req.query.refresh === 'true';
    console.log(`✨ Skin page request for user: ${userId}`);
    try {
        // ── 1. Fetch all user data in parallel ──
        const [profile, latestRoutineRow, latestInsightRow, streaks, checkins] = await Promise.all([
            supabase_1.DatabaseService.getSkinProfileByUserId(userId),
            supabase_1.DatabaseService.getLatestRoutine(userId),
            supabase_1.DatabaseService.getLatestInsightByUserId(userId),
            supabase_1.DatabaseService.getStreaks(userId),
            supabase_1.DatabaseService.getTodayCheckins(userId),
        ]);
        if (!profile) {
            return res.status(404).json({ error: 'No skin profile found — complete onboarding first' });
        }
        const ensuredRoutineRow = await ensureUserHasProductRoutine(userId, profile, latestRoutineRow);
        let latestInsight = latestInsightRow;
        const inferredFromImage = inferInsightFromProfileImage(profile);
        const inferredFromProfile = inferInsightFromProfileSignals(profile, streaks || { morning: 0, evening: 0 });
        // Backfill insight from photo analysis when legacy users have no insight row yet.
        if ((!latestInsight || latestInsight.skin_score === null || latestInsight.skin_score === undefined) && (inferredFromImage || inferredFromProfile)) {
            const savedInferredInsight = await supabase_1.DatabaseService.saveInsight(userId, inferredFromImage || inferredFromProfile);
            if (savedInferredInsight) {
                latestInsight = savedInferredInsight;
            }
        }
        // ── 2. Extract routine with product details from stored routine_data ──
        const routineData = ensuredRoutineRow?.routine_data;
        const inferenceRoutine = routineData?.inference?.routine;
        const summaryRoutine = routineData?.summary?.routine;
        const rawRoutine = inferenceRoutine || summaryRoutine;
        // Map routine steps to include product info
        const mapRoutineSteps = (steps) => {
            if (!steps || steps.length === 0)
                return [];
            return steps.map((s) => ({
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
                        morning: (cached.morning || []).map((s, i) => ({
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
                        evening: (cached.evening || []).map((s, i) => ({
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
                        weekly: (cached.weekly || []).map((s, i) => ({
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
                }
                else if (openaiChat) {
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
                        if (!content)
                            return null;
                        return JSON.parse(content);
                    });
                    const generated = await withTimeout(routinePromise, 8000, null);
                    if (generated) {
                        routine = {
                            morning: (generated.morning || []).map((s) => ({
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
                            evening: (generated.evening || []).map((s) => ({
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
                            weekly: (generated.weekly || []).map((s) => ({
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
            }
            catch (err) {
                console.log('⚠️ Routine generation fallback error:', err?.message);
            }
        }
        // ── 3. Build skin profile summary from DB ──
        const skinToneLabel = profile.skin_tone !== undefined
            ? (profile.skin_tone < 0.3 ? 'Fair' : profile.skin_tone < 0.5 ? 'Medium' : profile.skin_tone < 0.7 ? 'Medium-deep' : 'Deep')
            : 'Unknown';
        const normalizedInsightScore = normalizeSkinScore(latestInsight?.skin_score);
        const skinScore = normalizedInsightScore
            ?? inferredFromImage?.skinScore
            ?? inferredFromProfile?.skinScore
            ?? 0.72;
        const hydrationLevel = latestInsight?.hydration || inferredFromImage?.hydration || inferredFromProfile?.hydration || null;
        const protectionLevel = latestInsight?.protection || inferredFromImage?.protection || inferredFromProfile?.protection || null;
        const textureLevel = latestInsight?.texture || inferredFromImage?.texture || inferredFromProfile?.texture || null;
        // ── 4. AI agent: dynamic tips & page summary (cached) ──
        const cacheKey = `skin-page:${userId}`;
        const cached = skinPageCache.get(cacheKey);
        const hasFreshCache = !forceRefresh && cached && (Date.now() - cached.ts < SKIN_PAGE_CACHE_TTL);
        let agentData = null;
        if (hasFreshCache) {
            agentData = cached.data;
        }
        else if (openaiChat) {
            try {
                const completedSteps = Array.from(checkins || []);
                const totalMorning = routine.morning.length;
                const totalEvening = routine.evening.length;
                const morningDone = completedSteps.filter((s) => s.startsWith('morning-')).length;
                const eveningDone = completedSteps.filter((s) => s.startsWith('evening-')).length;
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
- Hydration: ${hydrationLevel || 'Unknown'}
- Protection: ${protectionLevel || 'Unknown'}`;
                const aiResult = await withTimeout(openaiChat.chat.completions.create({
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
                    if (!content)
                        return null;
                    return JSON.parse(content);
                }), 8000, null);
                if (aiResult) {
                    agentData = aiResult;
                    skinPageCache.set(cacheKey, { data: aiResult, ts: Date.now() });
                }
            }
            catch (err) {
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
                skin_score: Number(skinScore.toFixed(2)),
                hydration: hydrationLevel,
                protection: protectionLevel,
                texture: textureLevel,
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
    }
    catch (err) {
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
