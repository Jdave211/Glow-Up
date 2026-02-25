#!/usr/bin/env node
/**
 * Build fine-tuning data from looksmaxxing_final_finetune.pdf
 * and optionally start a fine-tuning job.
 *
 * Examples:
 *   node src/scripts/finetune-looksmax-pdf.js --prepare-only
 *   node src/scripts/finetune-looksmax-pdf.js --upload
 *   node src/scripts/finetune-looksmax-pdf.js --upload --base-model ft:... --epochs 2
 */

require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const OpenAI = require('openai').default;

const ROOT_DIR = path.resolve(__dirname, '..', '..', '..');
const DEFAULT_PDF_PATH = path.join(ROOT_DIR, 'looksmaxxing_final_finetune.pdf');
const DEFAULT_TEXT_PATH = path.join(ROOT_DIR, 'looksmaxxing_final_finetune.extracted.txt');
const DEFAULT_JSONL_PATH = path.join(ROOT_DIR, 'looksmaxxing_pdf_finetune.jsonl');

const DEFAULT_BASE_MODEL = 'gpt-4.1-mini-2025-04-14';
const DEFAULT_SUFFIX = 'glowup-looksmax-v1';
const DEFAULT_EPOCHS = 2;
const DEFAULT_MAX_EXAMPLES = 120;

const SYSTEM_PROMPT = `You are GlowUp AI, an objective and practical glow-up assistant.

You prioritize:
- Photo-led, measurable recommendations
- Clear routines users can actually follow
- Actionable technique and product guidance
- Safe, non-extreme recommendations

Output style:
- Crisp markdown with short sections
- Specific and realistic next actions
- No fluff, no judgement`;

const USER_PROMPT_TEMPLATES = [
  'Give me an objective glow-up plan focused on {topic}.',
  'Based on proven looksmaxxing fundamentals, what should I improve first for {topic}?',
  'I want practical, measurable upgrades for {topic}. What do I do this week?',
  'Help me improve my appearance for {topic} without overcomplicating the routine.',
  'What are the highest leverage actions for {topic} right now?'
];

function getArgValue(flag) {
  const idx = process.argv.indexOf(flag);
  if (idx === -1) return null;
  const next = process.argv[idx + 1];
  return next && !next.startsWith('--') ? next : null;
}

function hasFlag(flag) {
  return process.argv.includes(flag);
}

function detectTopic(text) {
  const lower = text.toLowerCase();
  const topicMatchers = [
    { topic: 'Skin Clarity', keywords: ['acne', 'pimple', 'pores', 'breakout', 'irritation', 'pigmentation', 'dark spot'] },
    { topic: 'Hair Quality', keywords: ['hair', 'scalp', 'thinning', 'frizz', 'dandruff', 'volume', 'hairline'] },
    { topic: 'Teeth and Smile', keywords: ['teeth', 'smile', 'whitening', 'gum', 'oral', 'breath', 'dental'] },
    { topic: 'Face Definition', keywords: ['bloating', 'jawline', 'face fat', 'definition', 'swelling'] },
    { topic: 'Lifestyle Optimization', keywords: ['sleep', 'stress', 'hydration', 'sugar', 'diet', 'sodium', 'exercise'] },
    { topic: 'Routine Consistency', keywords: ['routine', 'daily', 'weekly', 'consistency', 'habit', 'tracking'] }
  ];

  for (const matcher of topicMatchers) {
    if (matcher.keywords.some((keyword) => lower.includes(keyword))) {
      return matcher.topic;
    }
  }
  return 'General Looksmaxxing';
}

function cleanLine(line) {
  return line
    .replace(/\s+/g, ' ')
    .replace(/[^\x20-\x7E]/g, ' ')
    .trim();
}

function sanitizeText(raw) {
  return raw
    .replace(/\r/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .replace(/[ \t]+\n/g, '\n')
    .trim();
}

function extractTextFromPdf(pdfPath, textOutPath) {
  if (!fs.existsSync(pdfPath)) {
    throw new Error(`PDF not found at ${pdfPath}`);
  }

  execFileSync('pdftotext', ['-layout', '-nopgbrk', pdfPath, textOutPath], {
    stdio: 'ignore'
  });

  if (!fs.existsSync(textOutPath)) {
    throw new Error('pdftotext did not generate output text.');
  }

  return fs.readFileSync(textOutPath, 'utf8');
}

function splitIntoParagraphs(text) {
  return text
    .split(/\n\s*\n+/)
    .map(cleanLine)
    .filter((line) => line.length >= 80)
    .filter((line) => /[A-Za-z]/.test(line))
    .filter((line) => !/^page\s+\d+/i.test(line));
}

function chunkParagraphs(paragraphs, maxChars = 900) {
  const chunks = [];
  let current = '';

  for (const paragraph of paragraphs) {
    if (!current) {
      current = paragraph;
      continue;
    }

    if ((current.length + paragraph.length + 2) <= maxChars) {
      current += '\n' + paragraph;
    } else {
      chunks.push(current);
      current = paragraph;
    }
  }

  if (current) chunks.push(current);
  return chunks;
}

function chunkToBulletPoints(chunk, maxBullets = 5) {
  const sentenceCandidates = chunk
    .replace(/\n+/g, ' ')
    .split(/(?<=[.!?])\s+/)
    .map(cleanLine)
    .filter((line) => line.length >= 35 && line.length <= 220);

  const selected = sentenceCandidates.slice(0, maxBullets);
  if (selected.length === 0) {
    return ['- Keep routines simple, measurable, and consistent week to week.'];
  }

  return selected.map((line) => `- ${line}`);
}

function buildAssistantAnswer(chunk, topic) {
  const bullets = chunkToBulletPoints(chunk, 4).join('\n');
  return `## ${topic} Priorities

${bullets}

## This Week Plan

1. Apply one change at a time and keep it stable for 14 days.
2. Track outcomes with photos under the same lighting and angle.
3. Pair technique changes with realistic products you can sustain.

## Guardrails

- Avoid extreme protocols or over-layering actives.
- If irritation appears, reduce frequency and simplify the routine.
- Prioritize consistency over intensity.`;
}

function buildExamples(chunks, maxExamples) {
  const examples = [];

  for (let i = 0; i < chunks.length && examples.length < maxExamples; i += 1) {
    const chunk = chunks[i];
    const topic = detectTopic(chunk);
    const template = USER_PROMPT_TEMPLATES[i % USER_PROMPT_TEMPLATES.length];
    const userPrompt = template.replace('{topic}', topic.toLowerCase());
    const assistant = buildAssistantAnswer(chunk, topic);

    examples.push({
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        { role: 'user', content: userPrompt },
        { role: 'assistant', content: assistant }
      ]
    });
  }

  // Add one product-linking behavior example so model preserves product guidance style.
  examples.push({
    messages: [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: 'I need product recommendations but I want affordable options and direct links.' },
      {
        role: 'assistant',
        content: `## Smart Product Match

I will prioritize quality picks from reliable and affordable sources, then attach direct product links so you can buy where you prefer.

## How I Rank Picks

- Fit for your skin/hair/teeth goals
- Ingredient quality and tolerance
- Price-to-performance value
- Availability from trusted retailers`
      }
    ]
  });

  return examples;
}

function writeJsonl(examples, outPath) {
  const lines = examples.map((row) => JSON.stringify(row)).join('\n') + '\n';
  fs.writeFileSync(outPath, lines, 'utf8');
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

async function uploadAndCreateFineTuneJob(outPath, baseModel, suffix, epochs) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    throw new Error('OPENAI_API_KEY is not set');
  }

  const openai = new OpenAI({ apiKey });
  const file = await openai.files.create({
    file: fs.createReadStream(outPath),
    purpose: 'fine-tune'
  });

  const job = await openai.fineTuning.jobs.create({
    training_file: file.id,
    model: baseModel,
    suffix,
    hyperparameters: {
      n_epochs: epochs
    }
  });

  return { file, job };
}

async function main() {
  const pdfPath = path.resolve(getArgValue('--pdf') || DEFAULT_PDF_PATH);
  const textOutPath = path.resolve(getArgValue('--text-out') || DEFAULT_TEXT_PATH);
  const outPath = path.resolve(getArgValue('--out') || DEFAULT_JSONL_PATH);
  const maxExamples = Number(getArgValue('--max-examples') || DEFAULT_MAX_EXAMPLES);
  const baseModel = resolveBaseModel(getArgValue('--base-model'));
  const suffix = (getArgValue('--suffix') || DEFAULT_SUFFIX).replace(/[^a-zA-Z0-9-]/g, '-').slice(0, 64);
  const epochs = Number(getArgValue('--epochs') || DEFAULT_EPOCHS);
  const prepareOnly = hasFlag('--prepare-only');
  const upload = hasFlag('--upload') && !prepareOnly;

  console.log('Preparing looksmax fine-tune data...');
  console.log(`PDF: ${pdfPath}`);

  const rawText = extractTextFromPdf(pdfPath, textOutPath);
  const cleanTextValue = sanitizeText(rawText);
  const paragraphs = splitIntoParagraphs(cleanTextValue);
  const chunks = chunkParagraphs(paragraphs, 900);
  const examples = buildExamples(chunks, maxExamples);

  if (examples.length < 10) {
    throw new Error(`Generated only ${examples.length} examples. Need at least 10 for stable fine-tuning.`);
  }

  writeJsonl(examples, outPath);

  console.log(`Extracted text saved: ${textOutPath}`);
  console.log(`Training JSONL saved: ${outPath}`);
  console.log(`Examples generated: ${examples.length}`);

  if (!upload) {
    console.log('\nRun with --upload to start fine-tuning.');
    console.log(`Example: node src/scripts/finetune-looksmax-pdf.js --upload --base-model ${baseModel}`);
    return;
  }

  console.log('\nUploading training file and creating fine-tuning job...');
  console.log(`Base model: ${baseModel}`);
  console.log(`Epochs: ${epochs}`);
  console.log(`Suffix: ${suffix}`);

  const { file, job } = await uploadAndCreateFineTuneJob(outPath, baseModel, suffix, epochs);

  console.log('\nFine-tuning job created.');
  console.log(`File ID: ${file.id}`);
  console.log(`Job ID: ${job.id}`);
  console.log(`Status: ${job.status}`);
  console.log(`Model (base): ${job.model}`);
  console.log('\nCheck status with:');
  console.log(`node src/scripts/check-finetune.js ${job.id}`);
  console.log('\nWhen complete, set:');
  console.log('GLOWUP_FOUNDATION_MODEL=<fine_tuned_model_id>');
  console.log('GLOWUP_CHAT_MODEL=<fine_tuned_model_id>');
  console.log('GLOWUP_INFERENCE_MODEL=<fine_tuned_model_id>');
}

main().catch((error) => {
  console.error(`Failed: ${error.message}`);
  process.exit(1);
});
