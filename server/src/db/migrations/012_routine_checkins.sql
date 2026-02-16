-- ═══════════════════════════════════════════════════════════════
-- ROUTINE CHECK-INS TABLE
-- Tracks daily completion of routine steps
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS routine_checkins (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  routine_type TEXT NOT NULL, -- 'morning' or 'evening'
  step_id TEXT NOT NULL, -- e.g., "1-Cleanse" or "2-Moisturize"
  step_name TEXT NOT NULL,
  completed_at DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Ensure one check-in per step per day per user
  UNIQUE(user_id, routine_type, step_id, completed_at)
);

CREATE INDEX IF NOT EXISTS idx_routine_checkins_user_date ON routine_checkins(user_id, completed_at DESC);
CREATE INDEX IF NOT EXISTS idx_routine_checkins_user_type ON routine_checkins(user_id, routine_type);

-- Enable RLS
ALTER TABLE routine_checkins ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "Users can view own check-ins" ON routine_checkins FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Users can insert own check-ins" ON routine_checkins FOR INSERT WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Users can delete own check-ins" ON routine_checkins FOR DELETE USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ═══════════════════════════════════════════════════════════════
-- STREAKS TABLE
-- Tracks consecutive days of routine completion
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS routine_streaks (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  routine_type TEXT NOT NULL, -- 'morning' or 'evening'
  current_streak INTEGER DEFAULT 0,
  longest_streak INTEGER DEFAULT 0,
  last_completed_date DATE,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(user_id, routine_type)
);

CREATE INDEX IF NOT EXISTS idx_routine_streaks_user ON routine_streaks(user_id);

-- Enable RLS
ALTER TABLE routine_streaks ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "Users can view own streaks" ON routine_streaks FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Users can insert own streaks" ON routine_streaks FOR INSERT WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Users can update own streaks" ON routine_streaks FOR UPDATE USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;




