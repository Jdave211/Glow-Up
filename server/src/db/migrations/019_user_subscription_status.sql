-- Persist App Store subscription state on the user record.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS subscription_status TEXT DEFAULT 'inactive',
  ADD COLUMN IF NOT EXISTS subscription_plan TEXT,
  ADD COLUMN IF NOT EXISTS subscription_product_id TEXT,
  ADD COLUMN IF NOT EXISTS subscription_expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS subscription_last_verified_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS subscription_transaction_id TEXT,
  ADD COLUMN IF NOT EXISTS subscription_original_transaction_id TEXT,
  ADD COLUMN IF NOT EXISTS subscription_environment TEXT;

UPDATE users
SET subscription_status = 'inactive'
WHERE subscription_status IS NULL;

ALTER TABLE users
  ALTER COLUMN subscription_status SET DEFAULT 'inactive';

CREATE INDEX IF NOT EXISTS idx_users_subscription_status
  ON users (subscription_status);

CREATE INDEX IF NOT EXISTS idx_users_subscription_expires_at
  ON users (subscription_expires_at);
