-- 03_create_tables.sql — Full schema for UMS (idempotent with IF NOT EXISTS)
-- Run connected to the UMS_DB database as the application user or superuser.

-- ── Extensions ────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "pg_trgm";    -- trigram indexes for LIKE search

-- ── Roles table ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS roles (
    id   SERIAL      PRIMARY KEY,
    name VARCHAR(30) NOT NULL UNIQUE
);

COMMENT ON TABLE  roles      IS 'Application roles — ROLE_USER, ROLE_MODERATOR, ROLE_ADMIN';
COMMENT ON COLUMN roles.name IS 'Must match ERole enum values in the Spring app';

-- ── Users table ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    username     VARCHAR(50)  NOT NULL UNIQUE,
    email        VARCHAR(100) NOT NULL UNIQUE,
    password     VARCHAR(255) NOT NULL,
    enabled      BOOLEAN      NOT NULL DEFAULT TRUE,
    first_name   VARCHAR(80),
    last_name    VARCHAR(80),
    phone_number VARCHAR(20),
    created_at   TIMESTAMP,
    updated_at   TIMESTAMP,
    created_by   VARCHAR(100),
    updated_by   VARCHAR(100),
    version      BIGINT       NOT NULL DEFAULT 0
);

COMMENT ON TABLE  users          IS 'Application user accounts';
COMMENT ON COLUMN users.password IS 'BCrypt-hashed password — never store plain text';
COMMENT ON COLUMN users.version  IS 'Optimistic locking version counter (JPA @Version)';

-- ── User ↔ Role junction ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_roles (
    user_id UUID    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id INTEGER NOT NULL REFERENCES roles(id),
    PRIMARY KEY (user_id, role_id)
);

COMMENT ON TABLE user_roles IS 'Many-to-many: users ↔ roles';

-- ── Audit log ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS audit_logs (
    id          BIGSERIAL    PRIMARY KEY,
    action      VARCHAR(20)  NOT NULL,
    entity_type VARCHAR(50)  NOT NULL,
    entity_id   VARCHAR(100),
    user_id     VARCHAR(100),
    username    VARCHAR(100),
    old_value   TEXT,
    new_value   TEXT,
    ip_address  VARCHAR(45),
    request_id  VARCHAR(100),
    timestamp   TIMESTAMP    NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  audit_logs        IS 'Immutable audit trail — do not UPDATE or DELETE rows';
COMMENT ON COLUMN audit_logs.action IS 'CREATE | UPDATE | DELETE | READ';

-- ── Indexes ───────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_user_email         ON users(email);
CREATE INDEX IF NOT EXISTS idx_user_username      ON users(username);
CREATE INDEX IF NOT EXISTS idx_user_username_trgm ON users USING gin (username gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_user_email_trgm    ON users USING gin (email    gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_user   ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_ts     ON audit_logs(timestamp DESC);

-- ── Grants ────────────────────────────────────────────────────────────────────
GRANT CONNECT ON DATABASE :"UMS_DB" TO :"UMS_USER";
GRANT USAGE   ON SCHEMA public      TO :"UMS_USER";
GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES    IN SCHEMA public TO :"UMS_USER";
GRANT USAGE, SELECT
    ON ALL SEQUENCES IN SCHEMA public TO :"UMS_USER";
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO :"UMS_USER";
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT                  ON SEQUENCES TO :"UMS_USER";
