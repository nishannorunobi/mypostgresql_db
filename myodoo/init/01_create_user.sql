-- 01_create_user.sql — Create the Odoo application role (idempotent).
-- Odoo REQUIRES the CREATEDB privilege: it creates and manages its own
-- databases (via the web DB manager and for duplicate/backup operations).

SELECT NOT EXISTS (
    SELECT FROM pg_roles WHERE rolname = :'ODOO_USER'
) AS user_missing \gset

\if :user_missing
    CREATE USER :"ODOO_USER" WITH PASSWORD :'ODOO_PASSWORD' CREATEDB;
\else
    ALTER USER :"ODOO_USER" WITH PASSWORD :'ODOO_PASSWORD' CREATEDB;
\endif
