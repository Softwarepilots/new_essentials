-- Where each site is on the map, pinned by an admin. Lets the supervisor
-- live-location map show whether a supervisor is at a site.
ALTER TABLE sites
    ADD COLUMN IF NOT EXISTS latitude            DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS longitude           DOUBLE PRECISION,
    -- A supervisor within this distance of the pin counts as "at the site"
    ADD COLUMN IF NOT EXISTS location_radius_m   INTEGER NOT NULL DEFAULT 150,
    ADD COLUMN IF NOT EXISTS location_updated_at TIMESTAMPTZ;
