-- ═══════════════════════════════════════════════════════════════════════════
-- Recovery Companion — Supabase PostgreSQL Schema
-- ═══════════════════════════════════════════════════════════════════════════
-- Run this in the Supabase SQL editor or via psql.
-- Row Level Security (RLS) is enabled on all user-facing tables so that
-- users can only ever access their own data.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- EXTENSIONS
-- ─────────────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- fuzzy text search on entries


-- ─────────────────────────────────────────────────────────────────────────
-- ENUM TYPES
-- ─────────────────────────────────────────────────────────────────────────
CREATE TYPE recovery_type AS ENUM ('addiction', 'mental_health', 'both');

CREATE TYPE challenge_type AS ENUM (
    'urges',
    'anxiety',
    'loneliness',
    'stress',
    'medication_fatigue',
    'stigma'
);

CREATE TYPE badge_type AS ENUM (
    'first_entry',
    'streak_7',
    'streak_30',
    'streak_90',
    'streak_365',
    'milestone_custom'
);


-- ─────────────────────────────────────────────────────────────────────────
-- USERS — extended profile (complements Supabase Auth)
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_profiles (
    id                      UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name            TEXT,
    recovery_type           recovery_type NOT NULL DEFAULT 'both',
    goals                   TEXT[],                          -- free-form goal strings
    challenges              challenge_type[],                -- selected challenge tags
    therapist_email         TEXT,                            -- escalation contact
    rehab_contact_email     TEXT,                            -- escalation contact
    timezone                TEXT DEFAULT 'UTC',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_user_profiles_updated_at
    BEFORE UPDATE ON user_profiles
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ─────────────────────────────────────────────────────────────────────────
-- CONSENT FLAGS
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_consents (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id                     UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    email_reminders             BOOLEAN NOT NULL DEFAULT FALSE,
    therapist_escalation        BOOLEAN NOT NULL DEFAULT FALSE,
    rehab_escalation            BOOLEAN NOT NULL DEFAULT FALSE,
    data_analytics              BOOLEAN NOT NULL DEFAULT FALSE,
    consented_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id)
);

CREATE TRIGGER trg_user_consents_updated_at
    BEFORE UPDATE ON user_consents
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ─────────────────────────────────────────────────────────────────────────
-- JOURNAL ENTRIES
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS journal_entries (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    text            TEXT NOT NULL,
    mood_score      SMALLINT CHECK (mood_score BETWEEN 1 AND 10),
    chroma_id       TEXT,                     -- reference to ChromaDB document id
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_journal_user_created ON journal_entries (user_id, created_at DESC);


-- ─────────────────────────────────────────────────────────────────────────
-- AI INSIGHTS (persisted per journal entry)
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ai_insights (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    journal_entry_id    UUID REFERENCES journal_entries(id) ON DELETE SET NULL,
    detected_emotion    TEXT,
    pattern_insight     TEXT,
    recommendations     TEXT[],
    alternative_suggestions TEXT[],
    encouragement       TEXT,
    relapse_risk_level  TEXT CHECK (relapse_risk_level IN ('low', 'moderate', 'high')),
    raw_response        JSONB,                -- full LLM response for auditing
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_insights_user ON ai_insights (user_id, created_at DESC);


-- ─────────────────────────────────────────────────────────────────────────
-- PROGRESS & STREAKS
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_progress (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    current_streak      INT NOT NULL DEFAULT 0,
    longest_streak      INT NOT NULL DEFAULT 0,
    total_entries       INT NOT NULL DEFAULT 0,
    last_entry_date     DATE,
    sobriety_start_date DATE,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id)
);

CREATE TRIGGER trg_user_progress_updated_at
    BEFORE UPDATE ON user_progress
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ─────────────────────────────────────────────────────────────────────────
-- BADGES / REWARDS
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_badges (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id     UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    badge       badge_type NOT NULL,
    label       TEXT NOT NULL,
    awarded_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, badge)
);


-- ─────────────────────────────────────────────────────────────────────────
-- NOTIFICATION / EMAIL LOG (audit trail)
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notification_log (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
    type            TEXT NOT NULL,        -- 'reminder' | 'inactivity' | 'escalation'
    recipient_email TEXT NOT NULL,
    subject         TEXT,
    status          TEXT NOT NULL,        -- 'sent' | 'failed'
    error_message   TEXT,
    sent_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ─────────────────────────────────────────────────────────────────────────
-- ROW LEVEL SECURITY
-- ─────────────────────────────────────────────────────────────────────────
ALTER TABLE user_profiles       ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_consents       ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_entries     ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_insights         ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_progress       ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_badges         ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_log    ENABLE ROW LEVEL SECURITY;

-- Helpers: user can only see their own rows
CREATE POLICY "own_profile"     ON user_profiles    FOR ALL USING (auth.uid() = id);
CREATE POLICY "own_consents"    ON user_consents     FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "own_journals"    ON journal_entries   FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "own_insights"    ON ai_insights       FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "own_progress"    ON user_progress     FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "own_badges"      ON user_badges       FOR ALL USING (auth.uid() = user_id);
CREATE POLICY "own_notif_log"   ON notification_log  FOR ALL USING (auth.uid() = user_id);
