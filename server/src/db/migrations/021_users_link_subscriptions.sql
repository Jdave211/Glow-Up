-- Move subscription details off users; keep only active flag + FK to subscriptions.
-- Users: keep `subscription_active` as the only subscription-related state.
-- Details live in `subscriptions`, linked via `users.subscription_id`.

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS subscription_active BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS subscription_id UUID;

-- Link users -> subscriptions for quick joins and integrity.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.table_constraints tc
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND tc.table_name = 'users'
      AND tc.constraint_name = 'users_subscription_id_fkey'
  ) THEN
    ALTER TABLE users
      ADD CONSTRAINT users_subscription_id_fkey
      FOREIGN KEY (subscription_id)
      REFERENCES subscriptions(id)
      ON DELETE SET NULL;
  END IF;
END
$$;

-- Backfill linkage + active state from subscriptions table.
UPDATE users u
SET
  subscription_active = COALESCE(s.subscription_active, FALSE),
  subscription_id = s.id
FROM subscriptions s
WHERE s.user_id = u.id;

-- Drop legacy snapshot columns from users (details now live in subscriptions).
ALTER TABLE users
  DROP COLUMN IF EXISTS subscription_status,
  DROP COLUMN IF EXISTS subscription_plan,
  DROP COLUMN IF EXISTS subscription_product_id,
  DROP COLUMN IF EXISTS subscription_expires_at,
  DROP COLUMN IF EXISTS subscription_last_verified_at,
  DROP COLUMN IF EXISTS subscription_transaction_id,
  DROP COLUMN IF EXISTS subscription_original_transaction_id,
  DROP COLUMN IF EXISTS subscription_environment;

CREATE INDEX IF NOT EXISTS idx_users_subscription_active
  ON users (subscription_active);

