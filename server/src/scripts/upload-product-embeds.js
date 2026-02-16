#!/usr/bin/env node
/**
 * Upload product_embeds_finetune.jsonl and fine-tune on top of existing model
 * Base Model: ft:gpt-4o-2024-08-06:dave:glowup-skincare-v2:D65Gdpr5
 */

require('dotenv').config();
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

async function main() {
  const filePath = path.resolve(__dirname, '../../../product_embeds_finetune.jsonl');
  
  if (!fs.existsSync(filePath)) {
    console.error('❌ product_embeds_finetune.jsonl not found. Run: node src/scripts/finetune-product-embeds.js');
    process.exit(1);
  }
  
  const lines = fs.readFileSync(filePath, 'utf-8').trim().split('\n');
  console.log(`📄 File: product_embeds_finetune.jsonl (${lines.length} examples)`);
  console.log(`🎯 Base Model: ${BASE_MODEL}\n`);
  
  // Step 1: Upload file
  console.log('📤 Uploading training file to OpenAI...');
  const file = await openai.files.create({
    file: fs.createReadStream(filePath),
    purpose: 'fine-tune'
  });
  console.log(`✅ Uploaded: ${file.id} (${file.bytes} bytes)\n`);
  
  // Step 2: Create fine-tuning job (fine-tuning on top of fine-tuned model)
  console.log('🚀 Starting fine-tuning job (on top of existing fine-tuned model)...');
  const job = await openai.fineTuning.jobs.create({
    training_file: file.id,
    model: BASE_MODEL, // Fine-tune on top of existing fine-tuned model
    suffix: 'glowup-product-embeds',
    hyperparameters: {
      n_epochs: 2, // Fewer epochs since we're refining behavior, not learning from scratch
    }
  });
  
  console.log(`\n✅ Fine-tuning job created!`);
  console.log(`   Job ID: ${job.id}`);
  console.log(`   Base Model: ${BASE_MODEL}`);
  console.log(`   Status: ${job.status}`);
  console.log(`   Training file: ${file.id}`);
  console.log(`\n💡 Check status with:`);
  console.log(`   node src/scripts/check-finetune.js ${job.id}`);
  console.log(`\n📝 Once complete, update GLOWUP_CHAT_MODEL in .env to:`);
  console.log(`   ft:gpt-4o-2024-08-06:dave:glowup-product-embeds:XXXXX`);
}

main().catch(e => {
  console.error('❌ Failed:', e.message);
  if (e.response) {
    console.error('   Details:', JSON.stringify(e.response.data, null, 2));
  }
  process.exit(1);
});




