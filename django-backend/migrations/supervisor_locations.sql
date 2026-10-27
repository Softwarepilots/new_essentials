-- Supervisor live location: one row per supervisor holding only their latest
-- position (no route history is kept). Written by the supervisor's phone
-- during working hours only; read by admins.
CREATE TABLE IF NOT EXISTS supervisor_locations (
    user_id     UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    latitude    DOUBLE PRECISION NOT NULL,
    longitude   DOUBLE PRECISION NOT NULL,
    accuracy_m  REAL,
    recorded_at TIMESTAMPTZ NOT NULL,   -- when the phone took the fix
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
