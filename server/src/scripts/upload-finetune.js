#!/usr/bin/env node
/**
 * Upload a JSONL training file to OpenAI and start a fine-tuning job.
 *
 * Usage:
 *   node src/scripts/upload-finetune.js
 *   node src/scripts/upload-finetune.js --file ../../../looksmaxxing_pdf_finetune.jsonl
 *   node src/scripts/upload-finetune.js --base-model ft:... --suffix glowup-v5 --epochs 2
 */

require('dotenv').config();
const fs = require('fs');
const path = require('path');
const OpenAI = require('openai').default;

const DEFAULT_BASE_MODEL = 'gpt-4.1-mini-2025-04-14';
const DEFAULT_SUFFIX = 'glowup-chat-v4';
const DEFAULT_EPOCHS = 2;

function getArgValue(flag) {
  const idx = process.argv.indexOf(flag);
  if (idx === -1) return null;
  const next = process.argv[idx + 1];
  return next && !next.startsWith('--') ? next : null;
}

function resolveBaseModel(cliBaseModel) {
  return (
    cliBaseModel ||
    process.env.GLOWUP_FINETUNE_BASE_MODEL ||
    process.env.GLOWUP_FOUNDATION_MODEL ||
    process.env.GLOWUP_CHAT_MODEL ||
    DEFAULT_BASE_MODEL
  );
}

const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
if (!OPENAI_API_KEY) {
  console.error('❌ OPENAI_API_KEY not set');
  process.exit(1);
}

const openai = new OpenAI({ apiKey: OPENAI_API_KEY });

async function main() {
  const filePath = path.resolve(
    getArgValue('--file') || path.resolve(__dirname, '../../../skincare_finetune.jsonl')
  );
  const baseModel = resolveBaseModel(getArgValue('--base-model'));
  const suffix = (getArgValue('--suffix') || DEFAULT_SUFFIX).replace(/[^a-zA-Z0-9-]/g, '-').slice(0, 64);
  const epochs = Number(getArgValue('--epochs') || DEFAULT_EPOCHS);
  
  if (!fs.existsSync(filePath)) {
    console.error(`❌ Training file not found: ${filePath}`);
    process.exit(1);
  }
  
  const lines = fs.readFileSync(filePath, 'utf-8').trim().split('\n');
  console.log(`📄 File: ${filePath} (${lines.length} examples)`);
  console.log(`🎯 Base model: ${baseModel}`);
  console.log(`🔖 Suffix: ${suffix}`);
  console.log(`🔁 Epochs: ${epochs}\n`);
  
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
    model: baseModel,
    suffix,
    hyperparameters: {
      n_epochs: epochs,
    }
  });
  
  console.log(`✅ Fine-tuning job created!`);
  console.log(`   Job ID: ${job.id}`);
  console.log(`   Model: ${job.model}`);
  console.log(`   Status: ${job.status}`);
  console.log(`   Training file: ${job.training_file}`);
  console.log(`\n💡 Check status with:`);
  console.log(`   node src/scripts/check-finetune.js ${job.id}`);
  console.log(`\n📝 After it succeeds, set:`);
  console.log(`   GLOWUP_FOUNDATION_MODEL=<fine_tuned_model_id>`);
  console.log(`   GLOWUP_CHAT_MODEL=<fine_tuned_model_id>`);
  console.log(`   GLOWUP_INFERENCE_MODEL=<fine_tuned_model_id>`);
}

main().catch(e => {
  console.error('❌ Failed:', e.message);
  process.exit(1);
});
