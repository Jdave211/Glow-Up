-- Order tracking persisted in DB
CREATE TABLE IF NOT EXISTS order_tracking (
  order_id TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  retailer TEXT NOT NULL DEFAULT 'ulta',
  status TEXT NOT NULL,
  tracking_url TEXT NOT NULL,
  estimated_delivery TIMESTAMPTZ,
  events JSONB NOT NULL DEFAULT '[]'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_order_tracking_user_updated
  ON order_tracking(user_id, updated_at DESC);

-- Distributed checkout lock
CREATE TABLE IF NOT EXISTS checkout_locks (
  lock_name TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  acquired_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_checkout_locks_expires
  ON checkout_locks(expires_at);

CREATE OR REPLACE FUNCTION try_acquire_checkout_lock(
  p_lock_name TEXT,
  p_owner_id TEXT,
  p_ttl_seconds INT DEFAULT 600
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
  v_now TIMESTAMPTZ := NOW();
  v_expires TIMESTAMPTZ := NOW() + make_interval(secs => p_ttl_seconds);
  v_owner TEXT;
BEGIN
  INSERT INTO checkout_locks(lock_name, owner_id, acquired_at, expires_at, updated_at)
  VALUES (p_lock_name, p_owner_id, v_now, v_expires, v_now)
  ON CONFLICT (lock_name) DO UPDATE
    SET owner_id = EXCLUDED.owner_id,
        acquired_at = EXCLUDED.acquired_at,
        expires_at = EXCLUDED.expires_at,
        updated_at = v_now
  WHERE checkout_locks.expires_at <= v_now
     OR checkout_locks.owner_id = p_owner_id;

  SELECT owner_id INTO v_owner
  FROM checkout_locks
  WHERE lock_name = p_lock_name;

  RETURN v_owner = p_owner_id;
END;
$$;

CREATE OR REPLACE FUNCTION release_checkout_lock(
  p_lock_name TEXT,
  p_owner_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM checkout_locks
  WHERE lock_name = p_lock_name
    AND owner_id = p_owner_id;

  RETURN FOUND;
END;
$$;

ALTER TABLE order_tracking ENABLE ROW LEVEL SECURITY;
ALTER TABLE checkout_locks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Order tracking viewable by owner" ON order_tracking;
DROP POLICY IF EXISTS "Order tracking insertable" ON order_tracking;
DROP POLICY IF EXISTS "Order tracking updatable" ON order_tracking;
DROP POLICY IF EXISTS "Order tracking deletable" ON order_tracking;

CREATE POLICY "Order tracking viewable by owner" ON order_tracking FOR SELECT USING (true);
CREATE POLICY "Order tracking insertable" ON order_tracking FOR INSERT WITH CHECK (true);
CREATE POLICY "Order tracking updatable" ON order_tracking FOR UPDATE USING (true);
CREATE POLICY "Order tracking deletable" ON order_tracking FOR DELETE USING (true);

DROP POLICY IF EXISTS "Checkout locks viewable" ON checkout_locks;
DROP POLICY IF EXISTS "Checkout locks insertable" ON checkout_locks;
DROP POLICY IF EXISTS "Checkout locks updatable" ON checkout_locks;
DROP POLICY IF EXISTS "Checkout locks deletable" ON checkout_locks;

CREATE POLICY "Checkout locks viewable" ON checkout_locks FOR SELECT USING (true);
CREATE POLICY "Checkout locks insertable" ON checkout_locks FOR INSERT WITH CHECK (true);
CREATE POLICY "Checkout locks updatable" ON checkout_locks FOR UPDATE USING (true);
CREATE POLICY "Checkout locks deletable" ON checkout_locks FOR DELETE USING (true);
