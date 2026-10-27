-- Guest catalogue: items the admin publishes (like a WhatsApp Business
-- catalogue) that guests see in the guest app after checking in.
CREATE TABLE IF NOT EXISTS catalogue_items (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(200)  NOT NULL,
    description TEXT,
    price       NUMERIC(14,2),           -- optional, like WhatsApp catalogues
    image_url   TEXT,                    -- relative /media/... path
    is_active   BOOLEAN       NOT NULL DEFAULT TRUE,
    sort_order  INTEGER       NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_catalogue_items_active
    ON catalogue_items (is_active, sort_order, created_at DESC);
