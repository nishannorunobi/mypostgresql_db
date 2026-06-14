-- 03_grants.sql — Extensions + grants for the Odoo database (idempotent).
-- Runs as superuser, connected to the odoo database.
-- The odoo role OWNS the database, so it already holds full privileges; the
-- explicit grants below are belt-and-suspenders. Odoo manages its own schema.

-- 'unaccent' powers accent-insensitive search in Odoo (recommended).
CREATE EXTENSION IF NOT EXISTS "unaccent";

GRANT ALL PRIVILEGES ON DATABASE :"ODOO_DB" TO :"ODOO_USER";
GRANT ALL ON SCHEMA public TO :"ODOO_USER";
