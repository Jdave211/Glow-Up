-- Add metadata column to chat_messages for storing product cards, etc.
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS metadata JSONB;




