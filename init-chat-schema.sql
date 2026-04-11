-- Chat schema: created automatically on first docker compose up.
--
-- NOTE: The core tables (disasters, image_pairs, locations) are created by
-- the backend data-loading step, not here.  The vlm_assessments FK to
-- locations(id) is added as a deferred ALTER so this script succeeds even
-- when locations does not exist yet.
CREATE SCHEMA IF NOT EXISTS chat;

CREATE TABLE IF NOT EXISTS chat.conversations (
    id          SERIAL PRIMARY KEY,
    title       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS chat.vlm_assessments (
    id           SERIAL PRIMARY KEY,
    location_id  BIGINT,
    damage_level TEXT,
    confidence   DOUBLE PRECISION,
    description  TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS chat.messages (
    id               SERIAL PRIMARY KEY,
    conversation_id  INT NOT NULL REFERENCES chat.conversations(id) ON DELETE CASCADE,
    turn_index       INT NOT NULL,
    role             TEXT NOT NULL,
    content          TEXT NOT NULL,
    is_humanized     BOOLEAN NOT NULL DEFAULT false,
    assessment_id    INT REFERENCES chat.vlm_assessments(id) ON DELETE SET NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Add the FK from vlm_assessments -> locations once locations exists.
-- This is a no-op if the constraint already exists or locations hasn't
-- been created yet (the constraint will simply be skipped).
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables
               WHERE table_schema = 'public' AND table_name = 'locations')
       AND NOT EXISTS (
           SELECT 1 FROM information_schema.table_constraints
           WHERE constraint_name = 'vlm_assessments_location_id_fk'
             AND table_schema = 'chat')
    THEN
        ALTER TABLE chat.vlm_assessments
            ADD CONSTRAINT vlm_assessments_location_id_fk
            FOREIGN KEY (location_id) REFERENCES locations(id) ON DELETE CASCADE;
    END IF;
END
$$;
