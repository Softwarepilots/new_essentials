-- Whether each supervisor's location sharing is working, reported by their
-- phone during work hours. Lets admins see (and be alerted) when a supervisor
-- turns off GPS, removes the location permission, or logs out.
CREATE TABLE IF NOT EXISTS supervisor_location_status (
    user_id    UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    state      VARCHAR(30) NOT NULL,   -- ok | gps_off | permission_denied | logged_out
    changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
