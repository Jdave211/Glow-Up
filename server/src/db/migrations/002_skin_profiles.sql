-- ═══════════════════════════════════════════════════════════════
-- SKIN PROFILES TABLE - Complete Onboarding Data + Image Analysis
-- Run this in Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════
-- SKIN_PROFILES TABLE
-- Stores all onboarding data and image analysis results
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS skin_profiles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE UNIQUE,
  
  -- Basic Info
  name TEXT,
  
  -- Skin Data
  skin_type TEXT NOT NULL DEFAULT 'normal', -- normal, oily, dry, combination, sensitive
  skin_tone DECIMAL(3,2) DEFAULT 0.5, -- 0.0 (fair) to 1.0 (deep)
  skin_tone_label TEXT, -- fair, light, medium, deep, etc.
  skin_goals TEXT[] DEFAULT '{}', -- glass_skin, clear_skin, brightening, anti_aging, etc.
  skin_concerns TEXT[] DEFAULT '{}', -- acne, aging, dark_spots, texture, redness, dryness
  sunscreen_usage TEXT DEFAULT 'sometimes', -- daily, sometimes, rarely
  fragrance_free BOOLEAN DEFAULT false,
  
  -- Hair Data
  hair_type TEXT NOT NULL DEFAULT 'straight', -- straight, wavy, curly, coily
  hair_concerns TEXT[] DEFAULT '{}', -- frizz, breakage, oily_scalp, thinning, color_damage
  wash_frequency TEXT DEFAULT '2_3_weekly', -- daily, 2_3_weekly, weekly, biweekly, monthly
  scalp_sensitivity BOOLEAN DEFAULT false,
  
  -- Budget & Lifestyle
  budget TEXT DEFAULT 'medium', -- low, medium, high
  
  -- Reminders
  routine_reminders BOOLEAN DEFAULT true,
  reminder_time TEXT DEFAULT 'morning', -- morning, evening, both
  photo_check_ins BOOLEAN DEFAULT true,
  
  -- ═══════════════════════════════════════════════════════════════
  -- IMAGE ANALYSIS RESULTS (from AI inference)
  -- ═══════════════════════════════════════════════════════════════
  
  -- Photo URLs (stored in Supabase Storage or external)
  photo_front_url TEXT,
  photo_left_url TEXT,
  photo_right_url TEXT,
  photo_scalp_url TEXT,
  
  -- AI Analysis Results (JSONB for flexibility)
  image_analysis JSONB DEFAULT '{}'::jsonb,
  /*
    Expected structure:
    {
      "analyzed_at": "2024-01-28T12:00:00Z",
      "model_version": "1.0",
      "skin": {
        "detected_tone": "medium",
        "detected_type": "combination",
        "oiliness_score": 0.6,
        "hydration_score": 0.4,
        "texture_score": 0.7,
        "concerns_detected": ["acne_mild", "hyperpigmentation_light"],
        "redness_areas": ["cheeks"],
        "pore_visibility": "moderate"
      },
      "hair": {
        "detected_type": "wavy",
        "frizz_level": "moderate",
        "damage_indicators": ["split_ends"],
        "scalp_condition": "healthy"
      },
      "confidence_scores": {
        "skin_analysis": 0.85,
        "hair_analysis": 0.78
      },
      "recommendations_from_analysis": [
        "niacinamide for oil control",
        "vitamin c for hyperpigmentation"
      ]
    }
  */
  
  -- Derived/Computed Fields
  analysis_confidence DECIMAL(3,2), -- Overall confidence of image analysis
  last_analysis_at TIMESTAMPTZ,
  
  -- Metadata
  onboarding_completed BOOLEAN DEFAULT false,
  onboarding_completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_skin_profiles_user ON skin_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_skin_profiles_skin_type ON skin_profiles(skin_type);
CREATE INDEX IF NOT EXISTS idx_skin_profiles_concerns ON skin_profiles USING GIN(skin_concerns);

-- ═══════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY (idempotent)
-- ═══════════════════════════════════════════════════════════════
ALTER TABLE skin_profiles ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'skin_profiles' AND policyname = 'Skin profiles viewable by owner') THEN
    CREATE POLICY "Skin profiles viewable by owner" ON skin_profiles FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'skin_profiles' AND policyname = 'Skin profiles insertable') THEN
    CREATE POLICY "Skin profiles insertable" ON skin_profiles FOR INSERT WITH CHECK (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'skin_profiles' AND policyname = 'Skin profiles updatable') THEN
    CREATE POLICY "Skin profiles updatable" ON skin_profiles FOR UPDATE USING (true);
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════
-- PHOTO CHECK-INS TABLE (for biweekly progress tracking)
-- ═══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS photo_check_ins (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  skin_profile_id UUID REFERENCES skin_profiles(id) ON DELETE CASCADE,
  
  -- Photos
  photo_front_url TEXT,
  photo_left_url TEXT,
  photo_right_url TEXT,
  
  -- Analysis comparison
  image_analysis JSONB DEFAULT '{}'::jsonb,
  comparison_to_baseline JSONB DEFAULT '{}'::jsonb,
  /*
    Expected structure:
    {
      "improvements": ["hydration_improved", "acne_reduced"],
      "concerns": ["new_redness_detected"],
      "recommendation_changes": [
        {"action": "add", "product_type": "calming_serum", "reason": "new redness"},
        {"action": "remove", "product_type": "strong_retinol", "reason": "irritation risk"}
      ]
    }
  */
  
  -- User feedback
  user_notes TEXT,
  irritation_reported BOOLEAN DEFAULT false,
  improvement_reported BOOLEAN DEFAULT false,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_photo_check_ins_user ON photo_check_ins(user_id);
CREATE INDEX IF NOT EXISTS idx_photo_check_ins_profile ON photo_check_ins(skin_profile_id);

ALTER TABLE photo_check_ins ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'photo_check_ins' AND policyname = 'Check-ins viewable by owner') THEN
    CREATE POLICY "Check-ins viewable by owner" ON photo_check_ins FOR SELECT USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'photo_check_ins' AND policyname = 'Check-ins insertable') THEN
    CREATE POLICY "Check-ins insertable" ON photo_check_ins FOR INSERT WITH CHECK (true);
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════
-- FUNCTION: Update timestamp on profile changes
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION update_skin_profile_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_skin_profile_timestamp ON skin_profiles;
CREATE TRIGGER trigger_update_skin_profile_timestamp
  BEFORE UPDATE ON skin_profiles
  FOR EACH ROW
  EXECUTE FUNCTION update_skin_profile_timestamp();


