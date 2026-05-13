-- 03_grants.sql — Grant all privileges to docs_user (idempotent)
-- Tables are created by Plane's Django migrator, not here.
-- This runs after the DB is created, connected to mydocsdb.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

GRANT CONNECT ON DATABASE :"DOCS_DB" TO :"DOCS_USER";
GRANT USAGE   ON SCHEMA public        TO :"DOCS_USER";
GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES    IN SCHEMA public TO :"DOCS_USER";
GRANT USAGE, SELECT
    ON ALL SEQUENCES IN SCHEMA public TO :"DOCS_USER";

-- Ensure future tables created by Plane's migrator are also accessible
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES    TO :"DOCS_USER";
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT                  ON SEQUENCES TO :"DOCS_USER";
