-- Guest catalogue: multiple photos per item (up to 10, first = cover).
-- Run after guest_catalogue.sql. Safe to run more than once.
ALTER TABLE catalogue_items
    ADD COLUMN IF NOT EXISTS image_urls JSONB NOT NULL DEFAULT '[]'::jsonb;

-- Carry over the single photo saved before this change
UPDATE catalogue_items
SET image_urls = jsonb_build_array(image_url)
WHERE image_url IS NOT NULL
  AND image_urls = '[]'::jsonb;
