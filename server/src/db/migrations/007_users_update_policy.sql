-- Add UPDATE policy for users table so we can mark them as onboarded
-- The previous schema only had SELECT and INSERT policies

DO $$ 
BEGIN
  -- Create UPDATE policy if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'users' AND policyname = 'Users can update own profile'
  ) THEN
    CREATE POLICY "Users can update own profile" ON users FOR UPDATE USING (true);
  END IF;
  
  -- Create DELETE policy if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE tablename = 'users' AND policyname = 'Users can delete own profile'
  ) THEN
    CREATE POLICY "Users can delete own profile" ON users FOR DELETE USING (true);
  END IF;
END $$;

