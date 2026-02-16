-- Skin insights table
CREATE TABLE IF NOT EXISTS skin_insights (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  skin_score NUMERIC,
  hydration TEXT,
  protection TEXT,
  texture TEXT,
  notes TEXT,
  source TEXT DEFAULT 'app',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_skin_insights_user_id ON skin_insights(user_id);
CREATE INDEX IF NOT EXISTS idx_skin_insights_created_at ON skin_insights(created_at DESC);

ALTER TABLE skin_insights ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "Skin insights readable by all" ON skin_insights FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Skin insights insertable by all" ON skin_insights FOR INSERT WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Skin insights updatable by all" ON skin_insights FOR UPDATE USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "Skin insights deletable by all" ON skin_insights FOR DELETE USING (true);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;




