/**
 * Generate Embeddings for Product RAG
 * 
 * Creates rich text embeddings using OpenAI text-embedding-3-small
 * combining ALL relevant product fields including the enriched summary.
 * 
 * Usage:
 *   node src/scripts/generate-embeddings.js                # All products without embeddings
 *   node src/scripts/generate-embeddings.js --all          # Regenerate ALL embeddings
 *   node src/scripts/generate-embeddings.js --test 10      # Test with 10 products
 *   node src/scripts/generate-embeddings.js --resume       # Resume from checkpoint
 * 
 * Requires OPENAI_API_KEY in .env
 */

require('dotenv').config({ path: require('path').join(__dirname, '../../.env') });

const fs = require('fs');
const path = require('path');

const SUPABASE_URL = 'https://ukhxwxmqjltfjugizbku.supabase.co';
const SUPABASE_KEY = process.env.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVraHh3eG1xamx0Zmp1Z2l6Ymt1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk1NDA2NTUsImV4cCI6MjA4NTExNjY1NX0.x8sfd80Hmb6_wLtBG0Up9OqQZ49wjrhTE_wfdkVnPk4';
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;

const EMBEDDING_MODEL = 'text-embedding-3-small'; // 1536 dimensions, fast + cheap
const BATCH_SIZE = 50;      // OpenAI supports up to 2048 inputs per batch
const DB_FETCH_SIZE = 200;  // Products to fetch from DB per page
const CHECKPOINT_FILE = path.join(__dirname, '../../..', 'embedding_checkpoint.json');

// ─── CLI Args ─────────────────────────────────────────────────────
const args = process.argv.slice(2);
const testLimit = args.includes('--test') ? parseInt(args[args.indexOf('--test') + 1]) || 10 : null;
const regenerateAll = args.includes('--all');
const resumeMode = args.includes('--resume');

// ─── Helpers ──────────────────────────────────────────────────────
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

function loadCheckpoint() {
  try {
    return JSON.parse(fs.readFileSync(CHECKPOINT_FILE, 'utf-8'));
  } catch {
    return { lastOffset: 0, embedded: 0, errors: 0 };
  }
}

function saveCheckpoint(data) {
  fs.writeFileSync(CHECKPOINT_FILE, JSON.stringify(data, null, 2));
}

// ─── Build Rich Embedding Text ───────────────────────────────────
/**
 * Combines all relevant product fields into a single rich text
 * string optimized for semantic search and RAG retrieval.
 * 
 * Weight strategy:
 * - Product identity (name, brand, category) → appears first for strong signal
 * - Summary + moat → core semantic meaning
 * - Targeting (skin types, concerns) → critical for user matching
 * - Ingredients → enables ingredient-based search
 * - Usage + benefits → enables routine-based search
 * - Attributes → enables filter-like search (vegan, fragrance-free, etc.)
 */
function buildEmbeddingText(product) {
  const sections = [];

  // ── Identity (highest weight by position) ──
  sections.push(`${product.name} by ${product.brand}`);
  sections.push(`Category: ${product.category}${product.subcategory ? ', ' + product.subcategory : ''}`);

  // ── Summary & Description (core meaning) ──
  if (product.summary) sections.push(product.summary);
  if (product.moat) sections.push(`Unique: ${product.moat}`);
  if (product.details_full) sections.push(product.details_full);

  // ── Targeting (critical for user matching) ──
  if (product.target_skin_type?.length) {
    sections.push(`For skin types: ${product.target_skin_type.join(', ')}`);
  }
  if (product.target_concerns?.length) {
    sections.push(`Addresses concerns: ${product.target_concerns.join(', ')}`);
  }
  if (product.target_audience) {
    sections.push(`Audience: ${product.target_audience}`);
  }

  // ── Ingredients (enables ingredient-based search) ──
  if (product.ingredients?.length) {
    sections.push(`Key ingredients: ${product.ingredients.slice(0, 20).join(', ')}`);
  }

  // ── Usage & Benefits (enables routine matching) ──
  if (product.benefits) sections.push(`Benefits: ${product.benefits}`);
  if (product.how_to_use) sections.push(`How to use: ${product.how_to_use}`);

  // ── Attributes (enables tag/filter search) ──
  if (product.attributes?.length) {
    sections.push(`Attributes: ${product.attributes.join(', ')}`);
  }

  // ── Price tier (enables budget matching) ──
  if (product.tier) sections.push(`Price tier: ${product.tier}`);
  if (product.price) sections.push(`Price: $${product.price}`);

  // ── Rating signal ──
  if (product.rating) {
    sections.push(`Rating: ${product.rating}/5${product.review_count ? ` (${product.review_count} reviews)` : ''}`);
  }

  // Join with periods for clear sentence boundaries
  const text = sections.filter(Boolean).join('. ');

  // Truncate to ~8000 chars (model limit is 8191 tokens ≈ ~32K chars, but shorter = better embeddings)
  return text.substring(0, 8000);
}

// ─── OpenAI Batch Embedding ──────────────────────────────────────
async function generateBatchEmbeddings(texts, retries = 2) {
  for (let attempt = 1; attempt <= retries + 1; attempt++) {
    try {
      const response = await fetch('https://api.openai.com/v1/embeddings', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${OPENAI_API_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: EMBEDDING_MODEL,
          input: texts,
        }),
        signal: AbortSignal.timeout(60000),
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
      return data.data.map(d => d.embedding);
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
async function fetchProducts(offset, limit, onlyMissing = true) {
  let url = `${SUPABASE_URL}/rest/v1/products?select=*&order=id&limit=${limit}&offset=${offset}`;
  if (onlyMissing) {
    url += '&embedding=is.null';
  }
  const res = await fetch(url, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` },
  });
  if (!res.ok) throw new Error(`Supabase fetch error: ${res.status}`);
  return res.json();
}

async function updateProductEmbedding(id, embedding) {
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
      body: JSON.stringify({ embedding }),
    }
  );
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Update failed: ${err.substring(0, 200)}`);
  }
}

async function countProducts(onlyMissing = true) {
  let url = `${SUPABASE_URL}/rest/v1/products?select=id`;
  if (onlyMissing) url += '&embedding=is.null';
  const res = await fetch(url, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}`, 'Prefer': 'count=exact' },
    method: 'HEAD',
  });
  return parseInt(res.headers.get('content-range')?.split('/')[1] || '0');
}

// ─── Main ─────────────────────────────────────────────────────────
async function main() {
  if (!OPENAI_API_KEY) {
    console.error('❌ OPENAI_API_KEY not found in .env');
    process.exit(1);
  }

  console.log('╔══════════════════════════════════════════════════╗');
  console.log('║   🧠 Product Embedding Generator                ║');
  console.log('║   Model: text-embedding-3-small (1536d)         ║');
  console.log('╚══════════════════════════════════════════════════╝\n');

  const onlyMissing = !regenerateAll;
  const totalToProcess = await countProducts(onlyMissing);

  if (regenerateAll) console.log('🔄 Regenerating ALL embeddings');
  if (testLimit) console.log(`🧪 Test mode: ${testLimit} products`);

  let checkpoint = { lastOffset: 0, embedded: 0, errors: 0 };
  if (resumeMode) {
    checkpoint = loadCheckpoint();
    console.log(`🔄 Resuming from offset ${checkpoint.lastOffset} (${checkpoint.embedded} embedded so far)`);
  }

  const limit = testLimit || totalToProcess;
  console.log(`📦 Products ${onlyMissing ? 'without' : 'total for'} embeddings: ${totalToProcess}`);
  console.log(`🎯 Will process: ${Math.min(limit, totalToProcess)}`);
  console.log(`⚡ Batch size: ${BATCH_SIZE}\n`);

  if (totalToProcess === 0 && !regenerateAll) {
    console.log('✅ All products already have embeddings!');
    return;
  }

  const startTime = Date.now();
  let totalEmbedded = checkpoint.embedded;
  let totalErrors = checkpoint.errors;
  let processed = 0;
  let offset = checkpoint.lastOffset;

  while (processed < limit) {
    const fetchSize = Math.min(DB_FETCH_SIZE, limit - processed);
    const products = await fetchProducts(offset, fetchSize, onlyMissing);

    if (products.length === 0) break;

    // Process in batches for OpenAI
    for (let i = 0; i < products.length; i += BATCH_SIZE) {
      const batch = products.slice(i, i + BATCH_SIZE);
      const batchNum = Math.floor((processed + i) / BATCH_SIZE) + 1;
      const totalBatches = Math.ceil(Math.min(limit, totalToProcess) / BATCH_SIZE);

      try {
        // Build embedding texts
        const texts = batch.map(buildEmbeddingText);

        // Generate embeddings
        const embeddings = await generateBatchEmbeddings(texts);

        // Update each product
        let batchSuccess = 0;
        for (let j = 0; j < batch.length; j++) {
          try {
            await updateProductEmbedding(batch[j].id, embeddings[j]);
            batchSuccess++;
          } catch (err) {
            totalErrors++;
            console.log(`  ⚠️ Failed to save ${batch[j].name}: ${err.message.substring(0, 60)}`);
          }
        }

        totalEmbedded += batchSuccess;
        const elapsed = (Date.now() - startTime) / 1000;
        const rate = (processed + i + batch.length) / elapsed;
        const remaining = Math.min(limit, totalToProcess) - (processed + i + batch.length);
        const eta = remaining > 0 ? Math.round(remaining / rate) : 0;
        const etaStr = eta > 60 ? `${Math.floor(eta / 60)}m ${eta % 60}s` : `${eta}s`;

        console.log(`  📦 Batch ${batchNum}/${totalBatches}: ${batchSuccess}/${batch.length} embedded | Total: ${totalEmbedded} | ETA: ${etaStr}`);

        // Rate limit pause
        await sleep(200);

      } catch (err) {
        totalErrors += batch.length;
        console.log(`  ❌ Batch ${batchNum} failed: ${err.message.substring(0, 80)}`);
        await sleep(5000);
      }
    }

    processed += products.length;
    if (!onlyMissing) offset += products.length;

    // Checkpoint
    saveCheckpoint({
      lastOffset: onlyMissing ? 0 : offset, // For missing-only, always start from 0
      embedded: totalEmbedded,
      errors: totalErrors,
      timestamp: new Date().toISOString(),
    });
  }

  const elapsed = ((Date.now() - startTime) / 1000).toFixed(0);
  const elapsedStr = elapsed > 60 ? `${Math.floor(elapsed / 60)}m ${elapsed % 60}s` : `${elapsed}s`;

  console.log('\n╔══════════════════════════════════════════════════╗');
  console.log('║              📊 EMBEDDING SUMMARY               ║');
  console.log('╠══════════════════════════════════════════════════╣');
  console.log(`║  Total Processed: ${String(processed).padStart(8)}`);
  console.log(`║  Embedded:        ${String(totalEmbedded).padStart(8)}`);
  console.log(`║  Errors:          ${String(totalErrors).padStart(8)}`);
  console.log(`║  Time:         ${elapsedStr.padStart(11)}`);
  console.log('╚══════════════════════════════════════════════════╝');

  // Final count
  const withEmbeddings = await countProducts(false) - await countProducts(true);
  console.log(`\n📊 Products with embeddings: ${withEmbeddings}`);
}

main().catch(err => {
  console.error('💥 Fatal error:', err.message);
  process.exit(1);
});




