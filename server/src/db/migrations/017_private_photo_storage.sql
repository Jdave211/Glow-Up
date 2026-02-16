-- Private storage bucket for onboarding/check-in images.
-- Raw photos remain in private object storage; DB stores object paths only.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'glowup-private-photos',
  'glowup-private-photos',
  false,
  6291456,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
)
ON CONFLICT (id) DO NOTHING;
