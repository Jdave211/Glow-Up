#!/usr/bin/env node
/**
 * Upload skincare_finetune.jsonl to OpenAI and start a fine-tuning job.
 * Model: gpt-4o-2024-08-06
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

async function main() {
  const filePath = path.resolve(__dirname, '../../../skincare_finetune.jsonl');
  
  if (!fs.existsSync(filePath)) {
    console.error('❌ skincare_finetune.jsonl not found. Run doc2dataset first.');
    process.exit(1);
  }
  
  const lines = fs.readFileSync(filePath, 'utf-8').trim().split('\n');
  console.log(`📄 File: skincare_finetune.jsonl (${lines.length} examples)\n`);
  
  // Step 1: Upload file
  console.log('📤 Uploading training file to OpenAI...');
  const file = await openai.files.create({
    file: fs.createReadStream(filePath),
    purpose: 'fine-tune'
  });
  console.log(`✅ Uploaded: ${file.id} (${file.bytes} bytes)\n`);
  
  // Step 2: Create fine-tuning job
  console.log('🚀 Starting fine-tuning job...');
  const job = await openai.fineTuning.jobs.create({
    training_file: file.id,
    model: 'gpt-4o-2024-08-06',
    suffix: 'glowup-chat-v3',
    hyperparameters: {
      n_epochs: 3,
    }
  });
  
  console.log(`✅ Fine-tuning job created!`);
  console.log(`   Job ID: ${job.id}`);
  console.log(`   Model: ${job.model}`);
  console.log(`   Status: ${job.status}`);
  console.log(`   Training file: ${job.training_file}`);
  console.log(`\n💡 Check status with:`);
  console.log(`   node src/scripts/check-finetune.js ${job.id}`);
}

main().catch(e => {
  console.error('❌ Failed:', e.message);
  process.exit(1);
});

