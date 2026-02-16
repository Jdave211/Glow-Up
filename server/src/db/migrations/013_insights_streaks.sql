-- ═══════════════════════════════════════════════════════════════
-- ADD STREAK COLUMNS TO SKIN_INSIGHTS
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE skin_insights
ADD COLUMN IF NOT EXISTS morning_streak INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS evening_streak INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS longest_morning_streak INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS longest_evening_streak INTEGER DEFAULT 0;




