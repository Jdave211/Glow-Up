#!/usr/bin/env node
/**
 * Converts the skincare/haircare knowledge base (training.jsonl)
 * into proper OpenAI fine-tuning JSONL format, then uploads and
 * creates a fine-tuning job on gpt-4.1-mini.
 */

require('dotenv').config();
const fs = require('fs');
const path = require('path');
const OpenAI = require('openai').default;

const SYSTEM_PROMPT = `You are GlowUp AI, a friendly and expert skincare & haircare assistant inside the GlowUp app. You give warm, evidence-based advice with beautiful markdown formatting.

Formatting rules:
- Use **bold** for key terms, product names, and emphasis
- Use *italic* for caveats, nuance, or gentle asides
- Use ## headings to break up longer answers into sections
- Use bullet points (- item) for lists
- Use numbered lists (1. 2. 3.) for ordered steps
- Use --- horizontal rules to separate sections
- Leave blank lines before and after headings, lists, and dividers
- Use emojis sparingly but naturally (✨, 💕, 🧴)`;

// ─── Helpers ──────────────────────────────────────────────

function stripCitations(text) {
  // Remove [oai_citation:...] markers
  return text.replace(/\s*\[oai_citation:\d+‡[^\]]*\]\([^)]*\)/g, '');
}

function example(userQ, assistantA) {
  return {
    messages: [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: userQ },
      { role: 'assistant', content: stripCitations(assistantA) }
    ]
  };
}

function prettifyLabel(key) {
  return key.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
}

// ─── Generate training examples ───────────────────────────

function generateExamples(data) {
  const examples = [];

  // ═══ SKINCARE ═══
  const sc = data.skincare;

  // General best practices
  examples.push(example(
    "What are some general skincare best practices?",
    `## General Skincare Best Practices ✨\n\nHere are the essential habits for healthy skin:\n\n${sc.general_best_practices.map((t, i) => `${i + 1}. ${t}`).join('\n\n')}\n\n---\n\nConsistency is key — stick to these habits daily and your skin will thank you! 💕`
  ));

  // Daily routine steps
  examples.push(example(
    "What should my daily skincare routine look like?",
    `## Your Daily Skincare Routine 🧴\n\nHere's the ideal order to apply your products:\n\n${sc.daily_routine_steps.map((s, i) => `${i + 1}. **${s.split(' – ')[0]}** – ${s.split(' – ').slice(1).join(' – ')}`).join('\n\n')}\n\n---\n\n*Tip: In the evening, skip sunscreen and makeup but add treatments like retinol after serum!*`
  ));

  // Skin types
  for (const [key, info] of Object.entries(sc.skin_types)) {
    const label = prettifyLabel(key);

    examples.push(example(
      `What is ${label.toLowerCase()} and how should I care for it?`,
      `## ${label}\n\n${info.description}\n\n## Recommended Routine\n\n${info.recommended_routine}\n\n## Additional Tips\n\n${info.additional_tips}`
    ));

    examples.push(example(
      `I have ${label.toLowerCase()}. What products should I use?`,
      `## Product Advice for ${label} ✨\n\n${info.recommended_routine}\n\n---\n\n${info.additional_tips}`
    ));

    // Extra question variants
    examples.push(example(
      `Best routine for ${label.toLowerCase()}?`,
      `## ${label} Routine\n\n${info.recommended_routine}\n\n---\n\n*Remember:* ${info.additional_tips.split('.')[0]}.`
    ));
  }

  // Skin conditions
  for (const [key, info] of Object.entries(sc.conditions)) {
    const label = prettifyLabel(key);
    const mgmt = info.management || info.treatment || '';

    examples.push(example(
      `What is ${label.toLowerCase()} and how do I treat it?`,
      `## ${label}\n\n${info.description}\n\n## How to Manage ${label}\n\n${mgmt}`
    ));

    examples.push(example(
      `I'm struggling with ${label.toLowerCase()}. What should I do?`,
      `## Dealing with ${label} 💕\n\nI hear you — ${label.toLowerCase()} can be frustrating. Here's what dermatologists recommend:\n\n${mgmt}\n\n---\n\n*Be patient — improvements often take 4-8 weeks of consistent care.*`
    ));

    examples.push(example(
      `How can I get rid of ${label.toLowerCase()}?`,
      `## Getting Rid of ${label}\n\n${info.description}\n\n---\n\n## Treatment Plan\n\n${mgmt}`
    ));
  }

  // ═══ HAIRCARE ═══
  const hc = data.haircare;

  // General best practices
  examples.push(example(
    "What are the best haircare practices?",
    `## General Haircare Best Practices ✨\n\nHealthy hair starts with good habits:\n\n${hc.general_best_practices.map(t => `- ${t}`).join('\n\n')}\n\n---\n\nHealthy hair is a journey, not a destination — stay consistent! 💕`
  ));

  // Hair types
  for (const [key, info] of Object.entries(hc.hair_types)) {
    const label = prettifyLabel(key);

    examples.push(example(
      `How should I care for ${label.toLowerCase()}?`,
      `## ${label} Care\n\n${info.description}\n\n## Care Tips\n\n${info.care_tips}`
    ));

    examples.push(example(
      `I have ${label.toLowerCase()}. What should my hair routine be?`,
      `## ${label} Routine ✨\n\n${info.care_tips}\n\n---\n\n*Consistency is everything — give any new routine at least 4 weeks to show results.*`
    ));
  }

  // Hair conditions
  for (const [key, info] of Object.entries(hc.conditions)) {
    const label = prettifyLabel(key);
    const mgmt = info.treatment || info.management || '';

    examples.push(example(
      `How do I deal with ${label.toLowerCase()}?`,
      `## ${label}\n\n${info.description}\n\n## Treatment\n\n${mgmt}`
    ));

    examples.push(example(
      `I have ${label.toLowerCase()} problems. What can I do?`,
      `## Managing ${label} 💕\n\n${mgmt}\n\n---\n\n*If the issue persists after a few weeks of consistent care, consider seeing a dermatologist.*`
    ));
  }

  // Demographics
  for (const [key, info] of Object.entries(hc.demographics)) {
    const label = prettifyLabel(key);
    const tips = info.care_tips || info.notes || '';

    examples.push(example(
      `What haircare advice is there for ${label.toLowerCase()}?`,
      `## ${label}\n\n${info.description}\n\n## Advice\n\n${tips}`
    ));
  }

  // ═══ CROSS-TOPIC / CONVERSATIONAL ═══

  examples.push(example(
    "How often should I wash my face?",
    `## How Often to Wash Your Face\n\nMost dermatologists recommend washing your face **twice daily** — once in the morning and once at night.\n\n- **Morning:** A gentle rinse or light cleanser to remove overnight oil and prep skin for products\n- **Evening:** A thorough cleanse to remove makeup, sunscreen, dirt, and pollutants from the day\n\n---\n\n*If you have very dry or sensitive skin, you can use just water in the morning and save your cleanser for the evening.*`
  ));

  examples.push(example(
    "Do I really need sunscreen every day?",
    `## Yes — Sunscreen Every Single Day! ☀️\n\nThis is the **#1 most important skincare product** you can use. Here's why:\n\n- **UV damage** is the primary cause of premature aging (wrinkles, dark spots, sagging)\n- UV rays penetrate clouds and windows — you're exposed even on cloudy days and indoors\n- Sunscreen prevents **hyperpigmentation** and reduces skin cancer risk\n\n## What to Look For\n\n- **Broad-spectrum** protection (blocks UVA + UVB)\n- **SPF 30** or higher\n- Reapply every **2 hours** when outdoors\n\n---\n\n*Make it the last step of your morning routine, before makeup.* 💕`
  ));

  examples.push(example(
    "What's the difference between AHA and BHA?",
    `## AHA vs. BHA — What's the Difference?\n\nBoth are chemical exfoliants, but they work differently:\n\n## AHA (Alpha Hydroxy Acid)\n\n- Examples: **Glycolic acid**, **Lactic acid**\n- *Water-soluble* — works on the skin's surface\n- Best for: **dry skin**, dullness, fine lines, hyperpigmentation\n- Exfoliates dead skin cells for a brighter, smoother complexion\n\n## BHA (Beta Hydroxy Acid)\n\n- Example: **Salicylic acid**\n- *Oil-soluble* — penetrates into pores\n- Best for: **oily/acne-prone skin**, blackheads, enlarged pores\n- Clears out debris inside pores to prevent breakouts\n\n---\n\n*You can use both, but introduce them slowly and don't use them on the same night to avoid over-exfoliating!*`
  ));

  examples.push(example(
    "What order should I apply my skincare products?",
    `## The Correct Order for Skincare Products\n\nThe general rule is **thinnest to thickest** consistency:\n\n## Morning Routine ☀️\n\n1. **Cleanser** — gentle wash\n2. **Toner** — if you use one\n3. **Serum** — e.g. Vitamin C\n4. **Eye cream** — gently tap around eyes\n5. **Moisturizer** — lock in hydration\n6. **Sunscreen** — SPF 30+ (always last)\n\n## Evening Routine 🌙\n\n1. **Oil cleanser / Makeup remover** — first cleanse\n2. **Water-based cleanser** — second cleanse\n3. **Toner**\n4. **Treatment / Serum** — e.g. Retinol, Niacinamide\n5. **Eye cream**\n6. **Moisturizer** — seal everything in\n\n---\n\n*Wait about 1 minute between each step so products absorb properly!* ✨`
  ));

  examples.push(example(
    "Can I use retinol and vitamin C together?",
    `## Retinol + Vitamin C: Can You Combine Them?\n\nYes, but *with caution*. Here's the deal:\n\n- Both are **powerhouse ingredients** — Vitamin C brightens and protects, Retinol boosts cell turnover and fights wrinkles\n- Using them together in the same step can cause **irritation**, especially for sensitive skin\n\n## The Best Approach\n\n- **Vitamin C in the morning** — it's an antioxidant that boosts sun protection\n- **Retinol at night** — it can make skin sun-sensitive, so nighttime is ideal\n\nThis way, you get the benefits of both without overloading your skin.\n\n---\n\n*If your skin tolerates both well, some people do layer them at night (Vitamin C first, then Retinol), but start slowly!* 💕`
  ));

  examples.push(example(
    "How do I build a skincare routine on a budget?",
    `## Budget-Friendly Skincare Routine 💰\n\nYou don't need expensive products for great skin. Here's the essentials:\n\n## The 3 Non-Negotiables\n\n1. **Gentle Cleanser** — CeraVe, Cetaphil, or Vanicream (~$8-12)\n2. **Moisturizer** — CeraVe Moisturizing Cream or Cetaphil Daily (~$10-15)\n3. **Sunscreen** — Any SPF 30+ broad-spectrum (~$8-15)\n\nThat's it. Those three will get you 80% of the results.\n\n## When You're Ready to Add More\n\n- **Niacinamide serum** — The Ordinary Niacinamide 10% (~$6) for pores and texture\n- **Retinol** — The Ordinary Retinol 0.2% (~$6) for anti-aging\n- **Vitamin C** — The Ordinary Vitamin C Suspension (~$6) for brightening\n\n---\n\n*Focus on consistency over products. A simple routine done daily beats a 10-step routine done occasionally!* ✨`
  ));

  examples.push(example(
    "What ingredients should I avoid in skincare?",
    `## Ingredients to Watch Out For 🚫\n\nNot all ingredients are bad for everyone, but here are some common irritants to be aware of:\n\n- **Fragrance / Parfum** — top cause of skin irritation and allergic reactions\n- **Denatured alcohol (SD Alcohol, Alcohol Denat.)** — can dry and irritate skin\n- **Sulfates (SLS, SLES)** — harsh cleansing agents that strip moisture\n- **Essential oils** — can be sensitizing, especially for sensitive skin (lavender, citrus)\n- **Parabens** — controversial preservatives; some people prefer to avoid them\n\n## Context Matters\n\n- *Oily/acne-prone skin* should avoid heavy comedogenic oils (coconut oil on face)\n- *Sensitive skin* should avoid anything with fragrance, dyes, or high-concentration actives\n- *If using retinol*, avoid combining with AHAs/BHAs on the same night to prevent over-exfoliation\n\n---\n\n*When in doubt, patch test any new product on your inner arm for 24-48 hours before applying to your face.* 💕`
  ));

  return examples;
}

// ─── Main ─────────────────────────────────────────────────

async function main() {
  const rootDir = path.resolve(__dirname, '..', '..', '..');
  // Try training.jsonl first, fall back to training.json
  let inputPath = path.join(rootDir, 'training.jsonl');
  if (!fs.existsSync(inputPath) || fs.statSync(inputPath).size === 0) {
    inputPath = path.join(rootDir, 'training.json');
  }
  if (!fs.existsSync(inputPath) || fs.statSync(inputPath).size === 0) {
    console.error('❌ No training data found. Please save training.jsonl first.');
    process.exit(1);
  }
  const outputPath = path.join(rootDir, 'training_prepared.jsonl');

  console.log('📖 Reading knowledge base...');
  const raw = fs.readFileSync(inputPath, 'utf-8');
  const data = JSON.parse(raw);

  console.log('🔄 Generating training examples...');
  const examples = generateExamples(data);
  console.log(`✅ Generated ${examples.length} training examples`);

  // Write JSONL
  const jsonlContent = examples.map(e => JSON.stringify(e)).join('\n');
  fs.writeFileSync(outputPath, jsonlContent + '\n');
  console.log(`📝 Written to ${outputPath}`);

  // Validate
  let totalTokensEstimate = 0;
  for (const ex of examples) {
    const chars = ex.messages.reduce((sum, m) => sum + m.content.length, 0);
    totalTokensEstimate += Math.ceil(chars / 4); // rough estimate
  }
  console.log(`📊 Estimated ~${totalTokensEstimate.toLocaleString()} tokens total`);
  console.log(`📊 ${examples.length} examples (OpenAI recommends 10+ for fine-tuning)`);

  // Upload + create fine-tuning job
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    console.error('❌ OPENAI_API_KEY not set in .env');
    process.exit(1);
  }

  const openai = new OpenAI({ apiKey });

  console.log('\n📤 Uploading training file to OpenAI...');
  const file = await openai.files.create({
    file: fs.createReadStream(outputPath),
    purpose: 'fine-tune'
  });
  console.log(`✅ File uploaded: ${file.id} (${file.filename})`);

  console.log('\n🚀 Creating fine-tuning job on gpt-4.1-mini...');
  const job = await openai.fineTuning.jobs.create({
    training_file: file.id,
    model: 'gpt-4.1-mini-2025-04-14',
    suffix: 'glowup-skincare',
    hyperparameters: {
      n_epochs: 3
    }
  });

  console.log(`\n╔═══════════════════════════════════════════════════╗`);
  console.log(`║  🎯 Fine-Tuning Job Created!                      ║`);
  console.log(`╠═══════════════════════════════════════════════════╣`);
  console.log(`║  Job ID:    ${job.id}`);
  console.log(`║  Model:     gpt-4.1-mini-2025-04-14`);
  console.log(`║  Suffix:    glowup-skincare`);
  console.log(`║  Status:    ${job.status}`);
  console.log(`║  Examples:  ${examples.length}`);
  console.log(`║  Epochs:    3`);
  console.log(`╚═══════════════════════════════════════════════════╝`);
  console.log(`\n⏳ Fine-tuning usually takes 10-30 minutes.`);
  console.log(`   Check status: https://platform.openai.com/finetune/${job.id}`);
  console.log(`   Or run: node server/src/scripts/check-finetune.js ${job.id}`);
}

main().catch(err => {
  console.error('❌ Error:', err.message || err);
  process.exit(1);
});

