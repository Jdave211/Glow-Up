-- Canonical subscription records per user (source of truth).
CREATE TABLE IF NOT EXISTS subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  subscription_active BOOLEAN NOT NULL DEFAULT FALSE,
  subscription_status TEXT NOT NULL DEFAULT 'inactive',
  subscription_type TEXT CHECK (
    subscription_type IN ('weekly', 'monthly') OR subscription_type IS NULL
  ),
  subscription_started_at TIMESTAMPTZ,
  subscription_expires_at TIMESTAMPTZ,
  subscription_product_id TEXT,
  subscription_last_verified_at TIMESTAMPTZ,
  subscription_transaction_id TEXT,
  subscription_original_transaction_id TEXT,
  subscription_environment TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT subscriptions_user_unique UNIQUE (user_id)
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_active
  ON subscriptions (subscription_active);

CREATE INDEX IF NOT EXISTS idx_subscriptions_status
  ON subscriptions (subscription_status);

CREATE INDEX IF NOT EXISTS idx_subscriptions_expires_at
  ON subscriptions (subscription_expires_at);

CREATE INDEX IF NOT EXISTS idx_subscriptions_last_verified_at
  ON subscriptions (subscription_last_verified_at);

CREATE OR REPLACE FUNCTION update_subscriptions_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_subscriptions_timestamp ON subscriptions;
CREATE TRIGGER trigger_update_subscriptions_timestamp
  BEFORE UPDATE ON subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION update_subscriptions_timestamp();

-- Backfill from users subscription snapshot columns.
INSERT INTO subscriptions (
  user_id,
  subscription_active,
  subscription_status,
  subscription_type,
  subscription_started_at,
  subscription_expires_at,
  subscription_product_id,
  subscription_last_verified_at,
  subscription_transaction_id,
  subscription_original_transaction_id,
  subscription_environment
)
SELECT
  u.id AS user_id,
  CASE
    WHEN COALESCE(LOWER(u.subscription_status), 'inactive') = 'active'
      AND (u.subscription_expires_at IS NULL OR u.subscription_expires_at > NOW())
    THEN TRUE
    ELSE FALSE
  END AS subscription_active,
  CASE
    WHEN COALESCE(LOWER(u.subscription_status), 'inactive') = 'active'
      AND (u.subscription_expires_at IS NULL OR u.subscription_expires_at > NOW())
    THEN 'active'
    ELSE 'inactive'
  END AS subscription_status,
  CASE
    WHEN LOWER(COALESCE(u.subscription_plan, '')) LIKE '%week%' THEN 'weekly'
    WHEN LOWER(COALESCE(u.subscription_plan, '')) LIKE '%month%' THEN 'monthly'
    ELSE NULL
  END AS subscription_type,
  CASE
    WHEN COALESCE(LOWER(u.subscription_status), 'inactive') = 'active'
      THEN COALESCE(u.subscription_last_verified_at, NOW())
    ELSE NULL
  END AS subscription_started_at,
  u.subscription_expires_at,
  u.subscription_product_id,
  u.subscription_last_verified_at,
  u.subscription_transaction_id,
  u.subscription_original_transaction_id,
  u.subscription_environment
FROM users u
WHERE
  COALESCE(LOWER(u.subscription_status), 'inactive') = 'active'
  OR u.subscription_plan IS NOT NULL
  OR u.subscription_product_id IS NOT NULL
  OR u.subscription_expires_at IS NOT NULL
  OR u.subscription_last_verified_at IS NOT NULL
  OR u.subscription_transaction_id IS NOT NULL
  OR u.subscription_original_transaction_id IS NOT NULL
  OR u.subscription_environment IS NOT NULL
ON CONFLICT (user_id) DO UPDATE
SET
  subscription_active = EXCLUDED.subscription_active,
  subscription_status = EXCLUDED.subscription_status,
  subscription_type = EXCLUDED.subscription_type,
  subscription_started_at = EXCLUDED.subscription_started_at,
  subscription_expires_at = EXCLUDED.subscription_expires_at,
  subscription_product_id = EXCLUDED.subscription_product_id,
  subscription_last_verified_at = EXCLUDED.subscription_last_verified_at,
  subscription_transaction_id = EXCLUDED.subscription_transaction_id,
  subscription_original_transaction_id = EXCLUDED.subscription_original_transaction_id,
  subscription_environment = EXCLUDED.subscription_environment,
  updated_at = NOW();
