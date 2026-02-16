/**
 * Enrich Products with GPT-4o-nano
 * 
 * 1. Generates a rich executive summary for every product
 * 2. Fills sparse/blank fields (how_to_use, benefits, ingredients, details_full, moat)
 * 
 * Usage:
 *   node src/scripts/enrich-products.js                  # Process all products
 *   node src/scripts/enrich-products.js --test 5         # Test with 5 products
 *   node src/scripts/enrich-products.js --sparse-only    # Only fill sparse fields (skip summaries)
 *   node src/scripts/enrich-products.js --summary-only   # Only regenerate summaries
 *   node src/scripts/enrich-products.js --resume         # Resume from checkpoint
 */

require('dotenv').config({ path: require('path').join(__dirname, '../../.env') });

const SUPABASE_URL = 'https://ukhxwxmqjltfjugizbku.supabase.co';
const SUPABASE_KEY = process.env.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVraHh3eG1xamx0Zmp1Z2l6Ymt1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk1NDA2NTUsImV4cCI6MjA4NTExNjY1NX0.x8sfd80Hmb6_wLtBG0Up9OqQZ49wjrhTE_wfdkVnPk4';
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const MODEL = 'gpt-4o-mini'; // fast + cheap for enrichment

const CONCURRENCY = 5;      // Parallel OpenAI calls
const BATCH_DB_SIZE = 25;   // Products to fetch from DB at a time
const CHECKPOINT_FILE = require('path').join(__dirname, '../../..', 'enrich_checkpoint.json');
const fs = require('fs');
const path = require('path');

// ─── CLI Args ─────────────────────────────────────────────────────
const args = process.argv.slice(2);
const testLimit = args.includes('--test') ? parseInt(args[args.indexOf('--test') + 1]) || 5 : null;
const sparseOnly = args.includes('--sparse-only');
const summaryOnly = args.includes('--summary-only');
const resumeMode = args.includes('--resume');

// ─── Helpers ──────────────────────────────────────────────────────
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

function loadCheckpoint() {
  try {
    return JSON.parse(fs.readFileSync(CHECKPOINT_FILE, 'utf-8'));
  } catch {
    return { lastOffset: 0, enriched: 0, errors: 0 };
  }
}

function saveCheckpoint(data) {
  fs.writeFileSync(CHECKPOINT_FILE, JSON.stringify(data, null, 2));
}

// ─── OpenAI Call ──────────────────────────────────────────────────
async function callGPT(systemPrompt, userPrompt, retries = 2) {
  for (let attempt = 1; attempt <= retries + 1; attempt++) {
    try {
      const response = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${OPENAI_API_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: MODEL,
          messages: [
            { role: 'system', content: systemPrompt },
            { role: 'user', content: userPrompt },
          ],
          temperature: 0.3,
          max_tokens: 1500,
          response_format: { type: 'json_object' },
        }),
        signal: AbortSignal.timeout(30000),
      });

      if (response.status === 429) {
        const wait = 5000 * attempt;
        console.log(`  ⏳ Rate limited, waiting ${wait / 1000}s...`);
        await sleep(wait);
        continue;
      }

      if (!response.ok) {
        const err = await response.text();
        throw new Error(`OpenAI ${response.status}: ${err.substring(0, 200)}`);
      }

      const data = await response.json();
      const content = data.choices[0]?.message?.content;
      if (!content) throw new Error('Empty response from OpenAI');
      return JSON.parse(content);
    } catch (err) {
      if (attempt <= retries) {
        await sleep(2000 * attempt);
        continue;
      }
      throw err;
    }
  }
}

// ─── Supabase helpers ─────────────────────────────────────────────
async function fetchProducts(offset, limit) {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/products?select=*&order=id&limit=${limit}&offset=${offset}`,
    { headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` } }
  );
  if (!res.ok) throw new Error(`Supabase fetch error: ${res.status}`);
  return res.json();
}

async function updateProduct(id, updates) {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/products?id=eq.${id}`,
    {
      method: 'PATCH',
      headers: {
        'apikey': SUPABASE_KEY,
        'Authorization': `Bearer ${SUPABASE_KEY}`,
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal',
      },
      body: JSON.stringify(updates),
    }
  );
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Update failed for ${id}: ${err.substring(0, 200)}`);
  }
}

// ─── Enrichment Logic ─────────────────────────────────────────────

function buildProductContext(p) {
  const parts = [];
  parts.push(`Product: ${p.name}`);
  parts.push(`Brand: ${p.brand}`);
  parts.push(`Category: ${p.category}${p.subcategory ? ' > ' + p.subcategory : ''}`);
  parts.push(`Price: $${p.price} (${p.tier || 'mid'} tier)`);
  if (p.summary) parts.push(`Current Summary: ${p.summary}`);
  if (p.moat) parts.push(`Unique Selling Point: ${p.moat}`);
  if (p.target_skin_type?.length) parts.push(`Target Skin Types: ${p.target_skin_type.join(', ')}`);
  if (p.target_concerns?.length) parts.push(`Target Concerns: ${p.target_concerns.join(', ')}`);
  if (p.attributes?.length) parts.push(`Attributes: ${p.attributes.join(', ')}`);
  if (p.ingredients?.length) parts.push(`Key Ingredients: ${p.ingredients.slice(0, 15).join(', ')}`);
  if (p.ingredients_raw) parts.push(`Full Ingredients: ${p.ingredients_raw.substring(0, 500)}`);
  if (p.how_to_use) parts.push(`How to Use: ${p.how_to_use}`);
  if (p.benefits) parts.push(`Benefits: ${p.benefits}`);
  if (p.rating) parts.push(`Rating: ${p.rating}/5 (${p.review_count || 0} reviews)`);
  if (p.size) parts.push(`Size: ${p.size}`);
  if (p.breadcrumbs?.length) parts.push(`Breadcrumbs: ${p.breadcrumbs.join(' > ')}`);
  return parts.join('\n');
}

function identifySparseFields(p) {
  const sparse = [];
  if (!p.how_to_use) sparse.push('how_to_use');
  if (!p.benefits) sparse.push('benefits');
  if (!p.details_full) sparse.push('details_full');
  if (!p.moat || p.moat.length < 20) sparse.push('moat');
  // Check if target arrays are suspiciously thin
  if (!p.target_concerns?.length || p.target_concerns.length < 2) sparse.push('target_concerns');
  if (!p.target_skin_type?.length) sparse.push('target_skin_type');
  if (!p.ingredients?.length && !p.ingredients_raw) sparse.push('ingredients');
  return sparse;
}

const SYSTEM_PROMPT = `You are a skincare product data analyst. You enrich product listings with accurate, concise information.

Given a product's existing data, you MUST return a JSON object with these fields:

{
  "exec_summary": "A rich 2-3 sentence executive summary covering what the product is, who it's for, key ingredients, and what makes it stand out. Written for a skincare-savvy consumer.",
  "benefits": "3-5 key benefits as a single paragraph, separated by periods. Based on ingredients and product type.",
  "how_to_use": "Clear, practical usage instructions. If unknown, generate reasonable instructions based on the product category.",
  "details_full": "A comprehensive 2-3 sentence product description covering formulation, texture expectations, and ideal use case.",
  "moat": "One concise sentence about what makes this product uniquely compelling vs competitors.",
  "target_concerns_enriched": ["array", "of", "skin", "concerns", "this", "addresses"],
  "target_skin_type_enriched": ["array", "of", "skin", "types", "this", "suits"]
}

Rules:
- Base everything on the ACTUAL product data provided. Do NOT hallucinate ingredients or claims.
- If the product already has good data for a field, improve it slightly rather than replacing.
- For target_concerns and target_skin_type, EXPAND the existing arrays with additional relevant concerns/types based on ingredients and category.
- Keep exec_summary to 2-3 impactful sentences.
- Keep how_to_use practical and specific to the product category.
- For benefits, focus on what the key ingredients actually do.
- Return ONLY valid JSON, no markdown.`;

async function enrichProduct(product) {
  const context = buildProductContext(product);
  const sparseFields = identifySparseFields(product);

  const userPrompt = `Enrich this product listing:\n\n${context}\n\nSparse/missing fields that need filling: ${sparseFields.length ? sparseFields.join(', ') : 'none (just generate summary + improve existing)'}`;

  const result = await callGPT(SYSTEM_PROMPT, userPrompt);

  // Build update object
  const updates = {};

  // Always update summary
  if (!summaryOnly || true) {
    if (result.exec_summary) updates.summary = result.exec_summary;
  }

  // Fill sparse fields
  if (!summaryOnly) {
    if (result.benefits && !product.benefits) {
      updates.benefits = result.benefits;
    }
    if (result.how_to_use && !product.how_to_use) {
      updates.how_to_use = result.how_to_use;
    }
    if (result.details_full && !product.details_full) {
      updates.details_full = result.details_full;
    }
    if (result.moat && (!product.moat || product.moat.length < 20)) {
      updates.moat = result.moat;
    }

    // Enrich arrays (merge, don't replace)
    if (result.target_concerns_enriched?.length) {
      const existing = new Set((product.target_concerns || []).map(c => c.toLowerCase()));
      const enriched = result.target_concerns_enriched
        .map(c => c.toLowerCase())
        .filter(c => !existing.has(c));
      if (enriched.length > 0) {
        updates.target_concerns = [...(product.target_concerns || []), ...enriched];
      }
    }

    if (result.target_skin_type_enriched?.length) {
      const existing = new Set((product.target_skin_type || []).map(t => t.toLowerCase()));
      const enriched = result.target_skin_type_enriched
        .map(t => t.toLowerCase())
        .filter(t => !existing.has(t));
      if (enriched.length > 0) {
        updates.target_skin_type = [...(product.target_skin_type || []), ...enriched];
      }
    }
  }

  return updates;
}

// ─── Parallel Processing ──────────────────────────────────────────
async function processChunk(products) {
  const results = await Promise.allSettled(
    products.map(async (product) => {
      try {
        const updates = await enrichProduct(product);
        if (Object.keys(updates).length > 0) {
          await updateProduct(product.id, updates);
        }
        return { success: true, name: product.name, brand: product.brand, updates: Object.keys(updates).length };
      } catch (err) {
        return { success: false, name: product.name, brand: product.brand, error: err.message };
      }
    })
  );

  return results.map(r => r.status === 'fulfilled' ? r.value : { success: false, error: r.reason?.message });
}

// ─── Main ─────────────────────────────────────────────────────────
async function main() {
  if (!OPENAI_API_KEY) {
    console.error('❌ OPENAI_API_KEY not found in .env');
    process.exit(1);
  }

  console.log('╔══════════════════════════════════════════════════╗');
  console.log('║   🧴 Product Enrichment Engine (GPT-4o-mini)    ║');
  console.log('╚══════════════════════════════════════════════════╝\n');

  if (sparseOnly) console.log('📌 Mode: Sparse fields only (no summary regen)');
  if (summaryOnly) console.log('📌 Mode: Summary generation only');
  if (testLimit) console.log(`🧪 Test mode: ${testLimit} products`);

  let checkpoint = { lastOffset: 0, enriched: 0, errors: 0 };
  if (resumeMode) {
    checkpoint = loadCheckpoint();
    console.log(`🔄 Resuming from offset ${checkpoint.lastOffset} (${checkpoint.enriched} enriched so far)`);
  }

  // Count total products
  const countRes = await fetch(`${SUPABASE_URL}/rest/v1/products?select=id`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}`, 'Prefer': 'count=exact' },
    method: 'HEAD',
  });
  const totalProducts = parseInt(countRes.headers.get('content-range')?.split('/')[1] || '0');
  
  // When resuming, adjust limit to only process remaining products
  const remainingProducts = totalProducts - checkpoint.lastOffset;
  const limit = testLimit || (resumeMode ? remainingProducts : totalProducts);
  
  console.log(`📦 Total products: ${totalProducts}`);
  if (resumeMode) {
    console.log(`🔄 Resuming: ${checkpoint.lastOffset} already processed, ${remainingProducts} remaining`);
  }
  console.log(`🎯 Will process: ${limit} products`);
  console.log(`⚡ Concurrency: ${CONCURRENCY}\n`);

  const startTime = Date.now();
  let totalEnriched = checkpoint.enriched;
  let totalErrors = checkpoint.errors;
  let offset = checkpoint.lastOffset;
  let processed = 0; // This tracks products processed in THIS run, not total

  while (processed < limit) {
    const batchSize = Math.min(BATCH_DB_SIZE, limit - processed);
    const products = await fetchProducts(offset, batchSize);

    if (products.length === 0) break;

    // Process in parallel chunks
    for (let i = 0; i < products.length; i += CONCURRENCY) {
      const chunk = products.slice(i, i + CONCURRENCY);
      const results = await processChunk(chunk);

      for (const r of results) {
        if (r.success) {
          totalEnriched++;
          const globalIndex = checkpoint.lastOffset + processed + i + results.indexOf(r);
          process.stdout.write(`  ✅ [${globalIndex}] ${r.brand} - ${r.name} (${r.updates} fields)\n`);
        } else {
          totalErrors++;
          const globalIndex = checkpoint.lastOffset + processed + i + results.indexOf(r);
          process.stdout.write(`  ❌ [${globalIndex}] ${r.name}: ${(r.error || '').substring(0, 60)}\n`);
        }
      }

      // Brief pause between chunks to avoid rate limits
      await sleep(300);
    }

    processed += products.length;
    offset += products.length;

    // Checkpoint
    saveCheckpoint({ lastOffset: offset, enriched: totalEnriched, errors: totalErrors, timestamp: new Date().toISOString() });

    const elapsed = (Date.now() - startTime) / 1000;
    const rate = processed / elapsed;
    const remaining = limit - processed;
    const eta = remaining > 0 && rate > 0 ? Math.round(remaining / rate) : 0;
    const etaStr = eta > 60 ? `${Math.floor(eta / 60)}m ${eta % 60}s` : `${eta}s`;

    const globalProcessed = checkpoint.lastOffset + processed;
    console.log(`\n─── Progress: ${processed}/${limit} in this run | Total: ${globalProcessed}/${totalProducts} ─── [${totalEnriched} enriched | ${totalErrors} errors | ETA: ${etaStr}]\n`);
  }

  const elapsed = ((Date.now() - startTime) / 1000).toFixed(0);
  const elapsedStr = elapsed > 60 ? `${Math.floor(elapsed / 60)}m ${elapsed % 60}s` : `${elapsed}s`;

  console.log('╔══════════════════════════════════════════════════╗');
  console.log('║              📊 ENRICHMENT SUMMARY              ║');
  console.log('╠══════════════════════════════════════════════════╣');
  console.log(`║  Total Processed: ${String(processed).padStart(8)}`);
  console.log(`║  Enriched:        ${String(totalEnriched).padStart(8)}`);
  console.log(`║  Errors:          ${String(totalErrors).padStart(8)}`);
  console.log(`║  Time:         ${elapsedStr.padStart(11)}`);
  console.log('╚══════════════════════════════════════════════════╝');
}

main().catch(err => {
  console.error('💥 Fatal error:', err.message);
  process.exit(1);
});

