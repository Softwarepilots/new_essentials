-- Walkie-talkie voice messages between admins and staff.
-- An admin's message goes to all staff (and other admins see it); a staff
-- member's message goes to the admins.
CREATE TABLE IF NOT EXISTS walkie_messages (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    audience    VARCHAR(20) NOT NULL,          -- all_staff | admins
    audio_url   TEXT NOT NULL,                 -- /media/walkie/<uuid>.<ext>
    duration_ms INTEGER NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS walkie_messages_created_at_idx
    ON walkie_messages (created_at DESC);

-- Who has listened to which message
CREATE TABLE IF NOT EXISTS walkie_message_heard (
    message_id UUID NOT NULL REFERENCES walkie_messages(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    heard_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (message_id, user_id)
);
