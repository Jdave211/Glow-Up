-- ═══════════════════════════════════════════════════════════════
-- Ensure cart_items has FK to products for Supabase relationships
-- ═══════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE constraint_name = 'cart_items_product_id_fkey'
      AND table_name = 'cart_items'
  ) THEN
    ALTER TABLE cart_items
    ADD CONSTRAINT cart_items_product_id_fkey
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE constraint_name = 'cart_items_user_id_fkey'
      AND table_name = 'cart_items'
  ) THEN
    ALTER TABLE cart_items
    ADD CONSTRAINT cart_items_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
  END IF;
END $$;




