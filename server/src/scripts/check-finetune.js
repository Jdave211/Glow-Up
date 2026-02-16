#!/usr/bin/env node
/**
 * Check the status of a fine-tuning job.
 * Usage: node check-finetune.js <job_id>
 */

require('dotenv').config();
const OpenAI = require('openai').default;

async function main() {
  const jobId = process.argv[2];
  
  if (!jobId) {
    // List recent jobs if no ID provided
    const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
    console.log('📋 Recent fine-tuning jobs:\n');
    const jobs = await openai.fineTuning.jobs.list({ limit: 5 });
    for (const job of jobs.data) {
      const model = job.fine_tuned_model || '(training...)';
      console.log(`  ${job.id}`);
      console.log(`    Status: ${job.status}`);
      console.log(`    Base:   ${job.model}`);
      console.log(`    Output: ${model}`);
      console.log(`    Created: ${new Date(job.created_at * 1000).toLocaleString()}`);
      console.log('');
    }
    return;
  }

  const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  const job = await openai.fineTuning.jobs.retrieve(jobId);

  console.log(`\n🎯 Fine-Tuning Job: ${job.id}`);
  console.log(`   Status:          ${job.status}`);
  console.log(`   Base Model:      ${job.model}`);
  console.log(`   Fine-tuned Model: ${job.fine_tuned_model || '(not ready yet)'}`);
  console.log(`   Created:         ${new Date(job.created_at * 1000).toLocaleString()}`);
  if (job.finished_at) {
    console.log(`   Finished:        ${new Date(job.finished_at * 1000).toLocaleString()}`);
  }
  if (job.trained_tokens) {
    console.log(`   Trained Tokens:  ${job.trained_tokens.toLocaleString()}`);
  }
  if (job.error?.message) {
    console.log(`   ❌ Error:        ${job.error.message}`);
  }

  if (job.status === 'succeeded' && job.fine_tuned_model) {
    console.log(`\n✅ Your fine-tuned model is ready!`);
    console.log(`   Model ID: ${job.fine_tuned_model}`);
    console.log(`\n   Update your server to use this model in .env:`);
    console.log(`   GLOWUP_MODEL=${job.fine_tuned_model}`);
  }

  // Show recent events
  console.log('\n📜 Recent events:');
  const events = await openai.fineTuning.jobs.listEvents(jobId, { limit: 10 });
  for (const event of events.data.reverse()) {
    const time = new Date(event.created_at * 1000).toLocaleTimeString();
    console.log(`   [${time}] ${event.message}`);
  }
}

main().catch(err => {
  console.error('❌ Error:', err.message || err);
});




