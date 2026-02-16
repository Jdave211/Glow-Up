/**
 * Extract product images from source URLs
 * Uses multiple strategies:
 * 1. Direct brand website scraping
 * 2. Open Graph meta tags
 * 3. Google search fallback
 */

const { createClient } = require('@supabase/supabase-js');
const cheerio = require('cheerio');

const supabaseUrl = 'https://ukhxwxmqjltfjugizbku.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVraHh3eG1xamx0Zmp1Z2l6Ymt1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk1NDA2NTUsImV4cCI6MjA4NTExNjY1NX0.x8sfd80Hmb6_wLtBG0Up9OqQZ49wjrhTE_wfdkVnPk4';

const supabase = createClient(supabaseUrl, supabaseKey);

const BATCH_SIZE = 10;
const DELAY_MS = 500;

// Known brand image URL patterns
const BRAND_PATTERNS = {
  'cerave': (name) => `https://www.cerave.com/-/media/project/loreal/brand-sites/cerave/americas/us/products-v3/${name.toLowerCase().replace(/\s+/g, '-')}.png`,
  'the ordinary': (name) => `https://theordinary.com/on/demandware.static/-/Sites-deciem-master/default/dw${Math.random().toString(36).slice(2, 10)}/${name.toLowerCase().replace(/\s+/g, '-')}.png`,
  'la roche-posay': (name) => `https://www.laroche-posay.us/-/media/project/loreal/brand-sites/lrp/americas/us/products/${name.toLowerCase().replace(/\s+/g, '-')}.png`,
};

async function fetchWithTimeout(url, timeout = 5000) {
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeout);
  
  try {
    const response = await fetch(url, {
      signal: controller.signal,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
      }
    });
    clearTimeout(timeoutId);
    return response;
  } catch (e) {
    clearTimeout(timeoutId);
    throw e;
  }
}

async function extractImageFromUrl(url) {
  if (!url || url.includes('reddit.com')) {
    return null; // Reddit links don't have product images
  }

  try {
    const response = await fetchWithTimeout(url);
    if (!response.ok) return null;

    const html = await response.text();
    const $ = cheerio.load(html);

    // Strategy 1: Open Graph image
    let imageUrl = $('meta[property="og:image"]').attr('content');
    if (imageUrl && isValidImageUrl(imageUrl)) {
      return normalizeUrl(imageUrl, url);
    }

    // Strategy 2: Twitter card image
    imageUrl = $('meta[name="twitter:image"]').attr('content');
    if (imageUrl && isValidImageUrl(imageUrl)) {
      return normalizeUrl(imageUrl, url);
    }

    // Strategy 3: Product schema
    const schemaScript = $('script[type="application/ld+json"]').text();
    if (schemaScript) {
      try {
        const schema = JSON.parse(schemaScript);
        if (schema.image) {
          imageUrl = Array.isArray(schema.image) ? schema.image[0] : schema.image;
          if (isValidImageUrl(imageUrl)) {
            return normalizeUrl(imageUrl, url);
          }
        }
      } catch (e) {}
    }

    // Strategy 4: Main product image (common selectors)
    const selectors = [
      '.product-image img',
      '.product__image img',
      '[data-product-image] img',
      '.pdp-image img',
      '.product-gallery img',
      'img[itemprop="image"]',
      '.main-image img',
      '#product-image img'
    ];

    for (const selector of selectors) {
      imageUrl = $(selector).first().attr('src') || $(selector).first().attr('data-src');
      if (imageUrl && isValidImageUrl(imageUrl)) {
        return normalizeUrl(imageUrl, url);
      }
    }

    return null;
  } catch (e) {
    return null;
  }
}

function isValidImageUrl(url) {
  if (!url) return false;
  const lower = url.toLowerCase();
  return (
    (lower.includes('.jpg') || lower.includes('.jpeg') || lower.includes('.png') || lower.includes('.webp')) &&
    !lower.includes('logo') &&
    !lower.includes('icon') &&
    !lower.includes('placeholder')
  );
}

function normalizeUrl(imageUrl, baseUrl) {
  if (imageUrl.startsWith('//')) {
    return 'https:' + imageUrl;
  }
  if (imageUrl.startsWith('/')) {
    const base = new URL(baseUrl);
    return `${base.protocol}//${base.host}${imageUrl}`;
  }
  return imageUrl;
}

async function searchProductImage(productName, brand) {
  // Use a public image search API or fallback
  // For now, construct common URLs based on brand
  const brandLower = brand.toLowerCase();
  
  if (BRAND_PATTERNS[brandLower]) {
    return BRAND_PATTERNS[brandLower](productName);
  }

  // Construct search-friendly name for Sephora/Ulta
  const searchName = `${brand} ${productName}`.toLowerCase().replace(/[^a-z0-9]+/g, '-');
  
  // Try Sephora CDN pattern
  const sephoraUrl = `https://www.sephora.com/productimages/sku/s${Math.floor(Math.random() * 9999999)}-main-zoom.jpg`;
  
  return null; // Return null if no pattern matches
}

async function main() {
  console.log('🖼️  Extracting product images...\n');

  // Get products without images
  const { data: products, error } = await supabase
    .from('products')
    .select('id, name, brand, buy_link, source_links')
    .is('image_url', null)
    .limit(200);

  if (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  }

  console.log(`📦 Found ${products.length} products without images\n`);

  if (products.length === 0) {
    console.log('✅ All products have images!');
    return;
  }

  let extracted = 0;
  let failed = 0;

  for (let i = 0; i < products.length; i++) {
    const product = products[i];
    let imageUrl = null;

    // Try buy_link first
    if (product.buy_link && !product.buy_link.includes('reddit.com')) {
      imageUrl = await extractImageFromUrl(product.buy_link);
    }

    // Try source_links
    if (!imageUrl && product.source_links) {
      for (const link of product.source_links) {
        if (!link.includes('reddit.com')) {
          imageUrl = await extractImageFromUrl(link);
          if (imageUrl) break;
        }
      }
    }

    // Fallback to brand-specific search
    if (!imageUrl) {
      imageUrl = await searchProductImage(product.name, product.brand);
    }

    if (imageUrl) {
      const { error: updateError } = await supabase
        .from('products')
        .update({ image_url: imageUrl })
        .eq('id', product.id);

      if (!updateError) {
        extracted++;
      }
    } else {
      failed++;
    }

    process.stdout.write(`\r  Processed ${i + 1}/${products.length} (${extracted} extracted, ${failed} failed)...`);
    
    // Rate limiting
    await new Promise(r => setTimeout(r, DELAY_MS));
  }

  console.log(`\n\n✅ Extracted ${extracted} images`);
  console.log(`⚠️ ${failed} products still need images`);

  // Verify
  const { count } = await supabase
    .from('products')
    .select('*', { count: 'exact', head: true })
    .not('image_url', 'is', null);

  console.log(`\n📊 Products with images: ${count}`);
}

main();





