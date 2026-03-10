-- Add explicit subscription period tracking (Apple IAP style).
-- Corresponds to StoreKit.Product.SubscriptionPeriod (unit + value).

ALTER TABLE subscriptions
  ADD COLUMN IF NOT EXISTS subscription_period_unit TEXT,
  ADD COLUMN IF NOT EXISTS subscription_period_value INTEGER;

-- No backfill possible without product reference; defaults are null.
