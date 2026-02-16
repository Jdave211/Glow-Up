-- Add onboarded flag to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS onboarded BOOLEAN DEFAULT false;

-- Create index for quick lookup
CREATE INDEX IF NOT EXISTS idx_users_onboarded ON users(onboarded);





