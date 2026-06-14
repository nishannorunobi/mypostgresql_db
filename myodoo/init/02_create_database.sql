-- 02_create_database.sql — Create the Odoo database, owned by the odoo role (idempotent).
-- Run as superuser (postgres). Idempotency guarded by the calling script.
-- NOTE: only needed if you provision the DB up front and initialize Odoo via the
-- CLI (odoo -d myodoo -i base). If you prefer Odoo's web "Create Database" wizard,
-- skip this (use startdb.sh --role-only) and let Odoo create the DB itself.

CREATE DATABASE :"ODOO_DB"
    OWNER      :"ODOO_USER"
    ENCODING   'UTF8'
    LC_COLLATE 'en_US.utf8'
    LC_CTYPE   'en_US.utf8'
    TEMPLATE   template0;

COMMENT ON DATABASE :"ODOO_DB" IS 'myodoo — Odoo Community eCommerce database';
