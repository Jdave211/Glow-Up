const DEFAULT_GLOWUP_FINETUNED_MODEL = 'ft:gpt-4o-2024-08-06:dave:glowup-chat-v3:D6qlO5WY';

function readEnv(key: string): string | null {
  const raw = process.env[key];
  if (!raw) return null;
  const value = raw.trim();
  return value.length > 0 ? value : null;
}

export function resolveGlowupModel(...priorityKeys: string[]): string {
  for (const key of priorityKeys) {
    const value = readEnv(key);
    if (value) return value;
  }
  return (
    readEnv('GLOWUP_FOUNDATION_MODEL') ||
    readEnv('GLOWUP_CHAT_MODEL') ||
    DEFAULT_GLOWUP_FINETUNED_MODEL
  );
}

// Distilled from looksmaxxing_final_finetune.pdf in the project root.
export const FOUNDATIONAL_LOOKSMAX_GUIDANCE = `
- Use a photo-first pipeline: ground recommendations in visible findings and user goals.
- Keep skincare primary; include hair/teeth/lifestyle as secondary enhancements only.
- Personalize by skin tone, sensitivity, age cues, budget, and routine consistency.
- Favor incremental, realistic improvements over extreme transformations.
- Be explicit about uncertainty when image quality, lighting, or makeup limits confidence.
- Do not diagnose conditions; escalate suspicious lesions or persistent severe concerns to a dermatologist.
- For melanin-rich skin and hyperpigmentation, prioritize photoprotection and gentle anti-inflammatory actives.
- Respect safety constraints for pregnancy/breastfeeding and avoid unsafe at-home procedural advice.
- Keep recommendations objective and non-shaming; avoid prescriptive beauty scoring language.
- For product guidance, ensure claims are grounded in ingredient function and user context.
`.trim();

