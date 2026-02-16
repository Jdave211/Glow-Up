-- Align routines.profile_id FK with the active onboarding profile table.
-- Legacy schema referenced profiles(id), but onboarding writes to skin_profiles(id).

DO $$
DECLARE
  fk_target TEXT;
BEGIN
  SELECT c.confrelid::regclass::text
  INTO fk_target
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
  WHERE t.relname = 'routines'
    AND c.conname = 'routines_profile_id_fkey'
  LIMIT 1;

  IF fk_target IS NOT NULL AND fk_target <> 'skin_profiles' THEN
    ALTER TABLE routines DROP CONSTRAINT routines_profile_id_fkey;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    WHERE t.relname = 'routines'
      AND c.conname = 'routines_profile_id_fkey'
  ) THEN
    ALTER TABLE routines
      ADD CONSTRAINT routines_profile_id_fkey
      FOREIGN KEY (profile_id) REFERENCES skin_profiles(id) ON DELETE CASCADE;
  END IF;
END $$;
