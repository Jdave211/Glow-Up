#!/usr/bin/env node

/**
 * Ulta Product Scraper using ScrapingBee
 * 
 * Scrapes all product URLs from url.json, extracts structured data,
 * and upserts into Supabase products table.
 * 
 * Usage:
 *   node src/scripts/scrape-ulta.js              # Full run (all URLs)
 *   node src/scripts/scrape-ulta.js --test 5     # Test with 5 URLs
 *   node src/scripts/scrape-ulta.js --resume     # Resume from last checkpoint
 *   node src/scripts/scrape-ulta.js --offset 100 # Start from URL #100
 */

require('dotenv').config();
const fs = require('fs');
const path = require('path');
const cheerio = require('cheerio');

// ─── Config ───────────────────────────────────────────────────────
const SUPABASE_URL = 'https://ukhxwxmqjltfjugizbku.supabase.co';
const SUPABASE_KEY = process.env.SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVraHh3eG1xamx0Zmp1Z2l6Ymt1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk1NDA2NTUsImV4cCI6MjA4NTExNjY1NX0.x8sfd80Hmb6_wLtBG0Up9OqQZ49wjrhTE_wfdkVnPk4';

const CONCURRENCY = 3;          // Parallel requests (keep low to avoid rate limits)
const RETRY_ATTEMPTS = 3;       // Retries per URL
const RETRY_DELAY_MS = 3000;    // Delay between retries
const BATCH_SAVE_SIZE = 25;     // Save to DB every N products
const CHECKPOINT_FILE = path.join(__dirname, '../../..', 'scrape_checkpoint.json');
const RESULTS_FILE = path.join(__dirname, '../../..', 'scraped_products.json');

// ─── Parse CLI args ───────────────────────────────────────────────
const args = process.argv.slice(2);
let testLimit = null;
let startOffset = 0;
let resumeMode = false;

let retryFailed = false;

for (let i = 0; i < args.length; i++) {
  if (args[i] === '--test' && args[i + 1]) testLimit = parseInt(args[i + 1]);
  if (args[i] === '--offset' && args[i + 1]) startOffset = parseInt(args[i + 1]);
  if (args[i] === '--resume') resumeMode = true;
  if (args[i] === '--retry-failed') retryFailed = true;
}

// ─── User-Agent rotation for direct fetching ─────────────────────
const USER_AGENTS = [
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0',
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
];

function randomUA() {
  return USER_AGENTS[Math.floor(Math.random() * USER_AGENTS.length)];
}

// ─── Direct Fetch with retries ───────────────────────────────────
async function fetchDirect(url, attempt = 1) {
  try {
    const response = await fetch(url, {
      headers: {
        'User-Agent': randomUA(),
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Accept-Encoding': 'gzip, deflate, br',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'none',
        'Sec-Fetch-User': '?1',
        'Upgrade-Insecure-Requests': '1',
      },
      signal: AbortSignal.timeout(30000), // 30s timeout
      redirect: 'follow',
    });
    
    if (response.status === 429) {
      const wait = RETRY_DELAY_MS * attempt * 3;
      console.log(`  ⏳ Rate limited (429), waiting ${wait/1000}s...`);
      await sleep(wait);
      if (attempt < RETRY_ATTEMPTS) return fetchDirect(url, attempt + 1);
      throw new Error('Rate limit exceeded after retries');
    }
    
    if (response.status === 403) {
      // Blocked — wait longer and retry with different UA
      const wait = RETRY_DELAY_MS * attempt * 5;
      console.log(`  ⏳ Blocked (403), waiting ${wait/1000}s...`);
      await sleep(wait);
      if (attempt < RETRY_ATTEMPTS) return fetchDirect(url, attempt + 1);
      throw new Error('Blocked (403) after retries');
    }
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    
    return await response.text();
  } catch (err) {
    if (attempt < RETRY_ATTEMPTS) {
      const wait = RETRY_DELAY_MS * attempt;
      console.log(`  ⚠️ Attempt ${attempt} failed: ${err.message.substring(0, 60)}. Retrying in ${wait/1000}s...`);
      await sleep(wait);
      return fetchDirect(url, attempt + 1);
    }
    throw err;
  }
}

// ─── Parse Product Page ───────────────────────────────────────────
function parseProductPage(html, url) {
  const $ = cheerio.load(html);
  const product = {
    product_url: url,
    retailer: 'Ulta',
    data_source: 'ulta_scrape',
  };

  // 1) JSON-LD Structured Data (most reliable)
  $('script[type="application/ld+json"]').each((i, el) => {
    try {
      const data = JSON.parse($(el).html());
      if (data['@type'] === 'Product') {
        product.name = data.name || null;
        product.brand = data.brand || null;
        product.summary = data.description || null;
        product.image_url = data.image || null;
        product.sku = data.sku || null;
        product.product_id = data.productID || null;
        product.size = data.size || null;

        if (data.offers) {
          product.price = parseFloat(data.offers.price) || null;
          product.currency = data.offers.priceCurrency || 'USD';
          product.availability = data.offers.availability?.includes('InStock') ? 'in_stock' : 'out_of_stock';
          product.buy_link = data.offers.url || url;
        }

        if (data.aggregateRating) {
          product.rating = parseFloat(data.aggregateRating.ratingValue) || null;
          product.review_count = parseInt(data.aggregateRating.reviewCount) || 0;
        }
      }
      
      // Extract breadcrumb for category
      if (data['@type'] === 'BreadcrumbList' && data.itemListElement) {
        const crumbs = data.itemListElement.map(item => item.item?.name).filter(Boolean);
        // e.g. ["Home", "Skin Care", "Moisturizers", "Face Mists & Essences"]
        if (crumbs.length >= 2) {
          product.category = crumbs[1] || null;  // "Skin Care"
          product.subcategory = crumbs[crumbs.length - 1] || null; // "Face Mists & Essences"
          product.breadcrumbs = crumbs;
        }
      }
    } catch {}
  });

  // 2) HTML body sections: Details, How To Use, Ingredients
  const sections = extractTextSections($);
  
  if (sections.details && !product.summary) {
    product.summary = sections.details;
  }
  product.details_full = sections.details || null;
  product.how_to_use = sections.howToUse || null;
  product.ingredients_raw = sections.ingredients || null;
  product.benefits = sections.benefits || null;
  product.clean_ingredients = sections.cleanIngredients || null;

  // 3) Parse ingredients into array
  if (product.ingredients_raw) {
    product.ingredients = parseIngredientsList(product.ingredients_raw);
  }

  // 4) Infer product attributes
  product.attributes = inferAttributes(product);
  
  // 5) Infer target skin types and concerns
  const targeting = inferTargeting(product);
  product.target_skin_type = targeting.skinTypes;
  product.target_concerns = targeting.concerns;

  // 6) Determine price tier
  if (product.price) {
    if (product.price < 15) product.tier = 'budget';
    else if (product.price < 35) product.tier = 'mid';
    else if (product.price < 75) product.tier = 'premium';
    else product.tier = 'luxury';
  }

  // 7) Clean name (remove size suffix if present)
  if (product.name && product.size) {
    product.name_clean = product.name.replace(/ - [\d.]+ (?:oz|ml|fl oz|g|ct|pk)$/i, '').trim();
  }

  return product;
}

// ─── Extract text sections from HTML ─────────────────────────────
function extractTextSections($) {
  const result = { details: null, howToUse: null, ingredients: null, benefits: null, cleanIngredients: null };
  
  // Strategy: Find h2/h3 headers and extract the nearest substantial text block
  const sectionMap = {
    'Details': 'details',
    'How To Use': 'howToUse', 
    'Ingredients': 'ingredients',
    'Benefits': 'benefits',
    'Clean Ingredients': 'cleanIngredients',
  };

  // Try finding sections by walking the DOM from headers
  $('h2, h3').each((i, el) => {
    const headerText = $(el).text().trim();
    const sectionKey = sectionMap[headerText];
    if (!sectionKey) return;

    // Walk siblings after this heading
    let content = '';
    let sibling = $(el).next();
    let steps = 0;
    while (sibling.length && steps < 10) {
      const tag = sibling.prop('tagName')?.toLowerCase();
      if (tag === 'h2' || tag === 'h3') break; // next section
      const text = sibling.text().trim();
      if (text && text !== headerText) {
        content += text + ' ';
      }
      sibling = sibling.next();
      steps++;
    }

    // If no sibling content, try parent container
    if (!content.trim()) {
      const parent = $(el).parent();
      const parentText = parent.text().trim();
      // Remove the header text from parent
      content = parentText.replace(headerText, '').trim();
    }

    if (content.trim()) {
      result[sectionKey] = content.trim();
    }
  });

  // Fallback: try the "startsWith" approach on divs
  if (!result.details || !result.howToUse || !result.ingredients) {
    $('div').each((i, el) => {
      const text = $(el).text().trim();
      if (text.length < 50 || text.length > 3000) return;

      if (!result.howToUse && text.startsWith('How To Use') && text.length > 15) {
        result.howToUse = text.replace(/^How To Use\s*/, '').trim();
      }
      if (!result.ingredients && text.startsWith('Ingredients') && !text.startsWith('Ingredients Clean') && text.length > 20) {
        result.ingredients = text.replace(/^Ingredients\s*/, '').trim();
      }
    });
  }

  // Clean up: remove "Benefits..." prefix from details
  if (result.details && result.details.startsWith('Benefits')) {
    result.benefits = result.details;
    result.details = result.details.replace(/^Benefits\s*/, '');
  }

  return result;
}

// ─── Parse ingredients string into array ─────────────────────────
function parseIngredientsList(raw) {
  if (!raw) return [];
  // Ingredients are typically comma-separated
  return raw
    .split(/,\s*/)
    .map(i => i.trim())
    .filter(i => i.length > 1 && i.length < 100)
    .slice(0, 100); // Cap at 100 ingredients
}

// ─── Infer product attributes ────────────────────────────────────
function inferAttributes(product) {
  const attrs = [];
  const text = [
    product.name, 
    product.summary, 
    product.details_full, 
    product.ingredients_raw,
    product.benefits,
  ].filter(Boolean).join(' ').toLowerCase();

  const attrKeywords = {
    'fragrance-free': ['fragrance-free', 'fragrance free', 'unscented', 'no fragrance'],
    'vegan': ['vegan'],
    'cruelty-free': ['cruelty-free', 'cruelty free', 'not tested on animals'],
    'non-comedogenic': ['non-comedogenic', 'non comedogenic', 'won\'t clog pores'],
    'hypoallergenic': ['hypoallergenic'],
    'paraben-free': ['paraben-free', 'paraben free', 'no parabens'],
    'sulfate-free': ['sulfate-free', 'sulfate free'],
    'alcohol-free': ['alcohol-free', 'alcohol free'],
    'oil-free': ['oil-free', 'oil free'],
    'dermatologist-tested': ['dermatologist tested', 'dermatologist-tested', 'derm tested'],
    'spf': ['spf'],
    'retinol': ['retinol', 'retinoid'],
    'vitamin-c': ['vitamin c', 'ascorbic acid', 'l-ascorbic'],
    'hyaluronic-acid': ['hyaluronic acid', 'sodium hyaluronate'],
    'niacinamide': ['niacinamide'],
    'salicylic-acid': ['salicylic acid'],
    'glycolic-acid': ['glycolic acid'],
    'aha': ['alpha hydroxy', 'aha'],
    'bha': ['beta hydroxy', 'bha'],
    'ceramides': ['ceramide'],
    'peptides': ['peptide'],
    'clean': ['clean beauty', 'clean ingredient'],
  };

  for (const [attr, keywords] of Object.entries(attrKeywords)) {
    if (keywords.some(kw => text.includes(kw))) {
      attrs.push(attr);
    }
  }

  return attrs;
}

// ─── Infer targeting (skin types & concerns) ─────────────────────
function inferTargeting(product) {
  const text = [
    product.name, 
    product.summary, 
    product.details_full, 
    product.benefits,
  ].filter(Boolean).join(' ').toLowerCase();

  const skinTypes = [];
  const skinTypeMap = {
    'oily': ['oily skin', 'excess oil', 'oil control', 'mattifying'],
    'dry': ['dry skin', 'dehydrated', 'flaky', 'moisturizing', 'hydrating'],
    'combination': ['combination skin', 'combo skin'],
    'sensitive': ['sensitive skin', 'gentle', 'calming', 'soothing', 'redness'],
    'normal': ['normal skin', 'all skin types', 'every skin type'],
    'acne-prone': ['acne-prone', 'acne prone', 'breakout', 'blemish'],
    'mature': ['aging', 'anti-aging', 'mature skin', 'wrinkle', 'fine lines'],
  };

  for (const [type, keywords] of Object.entries(skinTypeMap)) {
    if (keywords.some(kw => text.includes(kw))) {
      skinTypes.push(type);
    }
  }

  const concerns = [];
  const concernMap = {
    'acne': ['acne', 'breakout', 'blemish', 'pimple', 'zit'],
    'aging': ['aging', 'anti-aging', 'wrinkle', 'fine lines', 'firmness', 'elasticity'],
    'pigmentation': ['dark spots', 'hyperpigmentation', 'pigmentation', 'brightening', 'dark circles', 'uneven tone'],
    'dryness': ['dryness', 'dehydration', 'flaking', 'moisture barrier'],
    'oiliness': ['oily', 'excess oil', 'shine control', 'mattifying'],
    'redness': ['redness', 'rosacea', 'inflammation', 'irritation'],
    'pores': ['pores', 'minimize pores', 'enlarged pores'],
    'texture': ['texture', 'rough skin', 'smoothing', 'exfoliat'],
    'sun-damage': ['sun damage', 'uv protection', 'sun spots', 'spf'],
    'dark-circles': ['dark circles', 'under eye', 'puffy eyes', 'eye bags'],
    'scarring': ['scarring', 'scar', 'post-acne marks'],
    'dullness': ['dull skin', 'dullness', 'radiance', 'glow', 'luminous'],
  };

  for (const [concern, keywords] of Object.entries(concernMap)) {
    if (keywords.some(kw => text.includes(kw))) {
      concerns.push(concern);
    }
  }

  // Default to "all skin types" if nothing matched
  if (skinTypes.length === 0) skinTypes.push('normal');

  return { skinTypes, concerns };
}

// ─── Normalize category from breadcrumbs ─────────────────────────
function normalizeCategory(raw) {
  if (!raw) return 'Other';
  const lower = raw.toLowerCase();
  
  const categoryMap = {
    'cleanser': ['cleanser', 'face wash', 'cleansing'],
    'moisturizer': ['moisturizer', 'cream', 'lotion', 'hydrator'],
    'serum': ['serum', 'essence', 'ampoule'],
    'sunscreen': ['sunscreen', 'spf', 'sun care', 'sun protection'],
    'toner': ['toner', 'tonic', 'mist'],
    'mask': ['mask', 'peel', 'exfoliat'],
    'eye care': ['eye cream', 'eye care', 'eye treatment'],
    'lip care': ['lip balm', 'lip care', 'lip treatment', 'lip mask'],
    'treatment': ['treatment', 'spot treatment', 'acne treatment'],
    'oil': ['facial oil', 'face oil'],
    'tool': ['tool', 'device', 'roller', 'gua sha'],
    'body care': ['body', 'lotion', 'body wash'],
    'hair care': ['hair', 'shampoo', 'conditioner'],
    'makeup': ['makeup', 'foundation', 'concealer', 'primer'],
    'gift set': ['gift set', 'kit', 'set', 'starter kit'],
  };

  for (const [normalized, keywords] of Object.entries(categoryMap)) {
    if (keywords.some(kw => lower.includes(kw))) return normalized;
  }
  return raw;
}

// ─── Upsert to Supabase ──────────────────────────────────────────
async function upsertToSupabase(products) {
  const rows = products.map(p => ({
    name: (p.name_clean || p.name || 'Unknown Product').substring(0, 500),
    brand: (p.brand || 'Unknown').substring(0, 200),
    category: normalizeCategory(p.subcategory || p.category || 'Other'),
    subcategory: (p.subcategory || null),
    price: p.price || 0,
    tier: p.tier || 'mid',
    stock_availability: p.availability || 'in_stock',
    summary: (p.summary || '').substring(0, 2000),
    moat: (p.benefits || '').substring(0, 1000),
    target_skin_type: p.target_skin_type || ['normal'],
    target_concerns: p.target_concerns || [],
    attributes: p.attributes || [],
    ingredients: p.ingredients || [],
    buy_link: p.buy_link || p.product_url,
    source_links: [p.product_url],
    retailer: 'Ulta',
    image_url: p.image_url || null,
    rating: p.rating || null,
    review_count: p.review_count || 0,
    data_source: 'ulta_scrape',
    // New enriched columns
    how_to_use: (p.how_to_use || '').substring(0, 2000) || null,
    size: (p.size || '').substring(0, 100) || null,
    benefits: (p.benefits || '').substring(0, 2000) || null,
    ingredients_raw: (p.ingredients_raw || '').substring(0, 5000) || null,
    details_full: (p.details_full || '').substring(0, 5000) || null,
    breadcrumbs: p.breadcrumbs || null,
    external_id: p.product_id || null,
    sku: p.sku || null,
  }));

  // Use Supabase REST API with upsert on the unique constraint
  const response = await fetch(`${SUPABASE_URL}/rest/v1/products`, {
    method: 'POST',
    headers: {
      'apikey': SUPABASE_KEY,
      'Authorization': `Bearer ${SUPABASE_KEY}`,
      'Content-Type': 'application/json',
      'Prefer': 'resolution=merge-duplicates,return=minimal',
    },
    body: JSON.stringify(rows),
  });

  if (!response.ok) {
    const error = await response.text();
    // If conflict, try individual upserts
    if (response.status === 409) {
      console.log('  ⚠️ Batch conflict, falling back to individual upserts...');
      let saved = 0;
      for (const row of rows) {
        try {
          const r = await fetch(`${SUPABASE_URL}/rest/v1/products?on_conflict=name,brand`, {
            method: 'POST',
            headers: {
              'apikey': SUPABASE_KEY,
              'Authorization': `Bearer ${SUPABASE_KEY}`,
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            },
            body: JSON.stringify(row),
          });
          if (r.ok) saved++;
          else {
            const err = await r.text();
            console.log(`    ⚠️ Skip "${row.name}": ${err.substring(0, 80)}`);
          }
        } catch {}
      }
      return saved;
    }
    throw new Error(`Supabase upsert failed: ${response.status} - ${error}`);
  }

  return rows.length;
}

// ─── Checkpoint Management ────────────────────────────────────────
function loadCheckpoint() {
  try {
    if (fs.existsSync(CHECKPOINT_FILE)) {
      return JSON.parse(fs.readFileSync(CHECKPOINT_FILE, 'utf-8'));
    }
  } catch {}
  return { lastIndex: 0, scraped: 0, failed: 0, savedToDB: 0 };
}

function saveCheckpoint(data) {
  fs.writeFileSync(CHECKPOINT_FILE, JSON.stringify(data, null, 2));
}

function appendResults(products) {
  let existing = [];
  try {
    if (fs.existsSync(RESULTS_FILE)) {
      existing = JSON.parse(fs.readFileSync(RESULTS_FILE, 'utf-8'));
    }
  } catch {}
  existing.push(...products);
  fs.writeFileSync(RESULTS_FILE, JSON.stringify(existing, null, 2));
}

// ─── Utility ──────────────────────────────────────────────────────
function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function formatDuration(ms) {
  const s = Math.floor(ms / 1000);
  const m = Math.floor(s / 60);
  const h = Math.floor(m / 60);
  if (h > 0) return `${h}h ${m % 60}m ${s % 60}s`;
  if (m > 0) return `${m}m ${s % 60}s`;
  return `${s}s`;
}

// ─── Process a batch of URLs concurrently ─────────────────────────
async function processBatch(urls, batchNum) {
  const results = await Promise.allSettled(
    urls.map(async ({ url, index }) => {
      try {
        const html = await fetchDirect(url);
        const product = parseProductPage(html, url);
        
        if (!product.name || !product.brand) {
          console.log(`  ⚠️ [${index}] Incomplete data for ${url.substring(0, 60)}...`);
          return { success: false, url, error: 'Missing name or brand' };
        }

        console.log(`  ✅ [${index}] ${product.brand} - ${product.name} ($${product.price})`);
        return { success: true, product };
      } catch (err) {
        console.log(`  ❌ [${index}] Failed: ${err.message.substring(0, 80)}`);
        return { success: false, url, error: err.message };
      }
    })
  );

  const products = [];
  const failures = [];

  for (const r of results) {
    if (r.status === 'fulfilled' && r.value.success) {
      products.push(r.value.product);
    } else if (r.status === 'fulfilled') {
      failures.push(r.value);
    } else {
      failures.push({ error: r.reason?.message || 'Unknown error' });
    }
  }

  return { products, failures };
}

// ─── Main ─────────────────────────────────────────────────────────
async function main() {
  console.log('╔══════════════════════════════════════════════════╗');
  console.log('║   🧴 Ulta Product Scraper (Direct Fetch)        ║');
  console.log('╚══════════════════════════════════════════════════╝\n');

  let urls;
  
  if (retryFailed) {
    // Retry previously failed URLs from scrape_failed.json
    const failFile = path.join(__dirname, '../../..', 'scrape_failed.json');
    if (!fs.existsSync(failFile)) {
      console.log('❌ No scrape_failed.json found — nothing to retry.');
      return;
    }
    const failedData = JSON.parse(fs.readFileSync(failFile, 'utf-8'));
    const allFailedUrls = failedData.filter(f => f.url).map(f => f.url);
    console.log(`🔄 Found ${allFailedUrls.length} previously failed URLs`);
    
    // Check which are already in the DB to avoid wasting credits
    console.log('🔍 Checking DB for already-scraped products...');
    try {
      const dbRes = await fetch(`${SUPABASE_URL}/rest/v1/products?select=buy_link&data_source=eq.ulta_scrape&limit=10000`, {
        headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` },
      });
      if (dbRes.ok) {
        const existing = await dbRes.json();
        const existingUrls = new Set(existing.map(p => p.buy_link));
        urls = allFailedUrls.filter(u => !existingUrls.has(u));
        console.log(`  ✅ ${allFailedUrls.length - urls.length} already in DB, ${urls.length} still need scraping`);
      } else {
        urls = allFailedUrls;
        console.log('  ⚠️ Could not check DB, retrying all URLs');
      }
    } catch {
      urls = allFailedUrls;
      console.log('  ⚠️ Could not check DB, retrying all URLs');
    }
  } else {
    // Load URLs from url.json
    const urlData = JSON.parse(fs.readFileSync(path.join(__dirname, '../../..', 'url.json'), 'utf-8'));
    urls = urlData.product_urls.map(u => u.value);
    console.log(`📦 Total URLs in file: ${urls.length}`);

    // Resume from checkpoint if requested
    let checkpoint = { lastIndex: 0, scraped: 0, failed: 0, savedToDB: 0 };
    if (resumeMode) {
      checkpoint = loadCheckpoint();
      startOffset = checkpoint.lastIndex;
      console.log(`🔄 Resuming from index ${startOffset} (${checkpoint.scraped} scraped, ${checkpoint.savedToDB} saved)`);
    }

    // Apply offset and limit
    if (startOffset > 0) {
      urls = urls.slice(startOffset);
      console.log(`⏭️  Starting from URL #${startOffset}`);
    }
  }
  
  if (testLimit) {
    urls = urls.slice(0, testLimit);
    console.log(`🧪 Test mode: limiting to ${testLimit} URLs`);
  }

  console.log(`🎯 URLs to process: ${urls.length}`);
  console.log(`⚡ Concurrency: ${CONCURRENCY}`);
  console.log(`💾 Batch save size: ${BATCH_SAVE_SIZE}\n`);

  const startTime = Date.now();
  let totalScraped = retryFailed ? 0 : (resumeMode ? loadCheckpoint().scraped : 0);
  let totalFailed = retryFailed ? 0 : (resumeMode ? loadCheckpoint().failed : 0);
  let totalSaved = retryFailed ? 0 : (resumeMode ? loadCheckpoint().savedToDB : 0);
  let pendingProducts = [];
  let failedUrls = [];

  // Process in batches
  for (let i = 0; i < urls.length; i += CONCURRENCY) {
    const batch = urls.slice(i, i + CONCURRENCY).map((url, j) => ({
      url,
      index: startOffset + i + j,
    }));

    const batchNum = Math.floor(i / CONCURRENCY) + 1;
    const totalBatches = Math.ceil(urls.length / CONCURRENCY);
    const elapsed = Date.now() - startTime;
    const rate = totalScraped > 0 ? (elapsed / totalScraped) : 0;
    const remaining = rate * (urls.length - i);

    console.log(`\n─── Batch ${batchNum}/${totalBatches} ─── [${totalScraped} scraped | ${totalFailed} failed | ETA: ${formatDuration(remaining)}]`);

    const { products, failures } = await processBatch(batch, batchNum);
    
    totalScraped += products.length;
    totalFailed += failures.length;
    pendingProducts.push(...products);
    failedUrls.push(...failures);

    // Save to DB in batches
    if (pendingProducts.length >= BATCH_SAVE_SIZE) {
      try {
        const saved = await upsertToSupabase(pendingProducts);
        totalSaved += saved;
        console.log(`  💾 Saved ${saved} products to DB (total: ${totalSaved})`);
        appendResults(pendingProducts);
        pendingProducts = [];
      } catch (err) {
        console.log(`  ⚠️ DB save failed: ${err.message}`);
        // Keep products in memory, will retry next batch
      }
    }

    // Save checkpoint
    saveCheckpoint({
      lastIndex: startOffset + i + CONCURRENCY,
      scraped: totalScraped,
      failed: totalFailed,
      savedToDB: totalSaved,
      timestamp: new Date().toISOString(),
    });

    // Small delay between batches to be polite
    if (i + CONCURRENCY < urls.length) {
      await sleep(500);
    }
  }

  // Save remaining products
  if (pendingProducts.length > 0) {
    try {
      const saved = await upsertToSupabase(pendingProducts);
      totalSaved += saved;
      appendResults(pendingProducts);
      console.log(`\n💾 Final save: ${saved} products to DB`);
    } catch (err) {
      console.log(`\n⚠️ Final DB save failed: ${err.message}`);
      appendResults(pendingProducts);
    }
  }

  // Save failed URLs for retry
  if (failedUrls.length > 0) {
    const failFile = path.join(__dirname, '../../..', 'scrape_failed.json');
    fs.writeFileSync(failFile, JSON.stringify(failedUrls, null, 2));
    console.log(`\n📝 ${failedUrls.length} failed URLs saved to scrape_failed.json`);
  }

  // Summary
  const totalTime = Date.now() - startTime;
  console.log('\n╔══════════════════════════════════════════════════╗');
  console.log('║              📊 SCRAPE SUMMARY                  ║');
  console.log('╠══════════════════════════════════════════════════╣');
  console.log(`║  Total URLs:      ${urls.length.toString().padStart(6)}`);
  console.log(`║  Scraped:         ${totalScraped.toString().padStart(6)}`);
  console.log(`║  Failed:          ${totalFailed.toString().padStart(6)}`);
  console.log(`║  Saved to DB:     ${totalSaved.toString().padStart(6)}`);
  console.log(`║  Time:            ${formatDuration(totalTime).padStart(6)}`);
  console.log(`║  Avg per product: ${(totalScraped > 0 ? (totalTime/totalScraped/1000).toFixed(1) + 's' : 'N/A').padStart(6)}`);
  console.log('╚══════════════════════════════════════════════════╝');
}

main().catch(err => {
  console.error('\n💥 Fatal error:', err);
  process.exit(1);
});

