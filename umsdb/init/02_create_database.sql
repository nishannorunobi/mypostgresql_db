-- 02_create_database.sql — Create the application database (idempotent)
-- Run as superuser (postgres). Cannot use DO $$ inside a transaction for CREATE DATABASE,
-- so the calling script guards the idempotency check before running this file.

CREATE DATABASE :"UMS_DB"
    OWNER      :"UMS_USER"
    ENCODING   'UTF8'
    LC_COLLATE 'en_US.utf8'
    LC_CTYPE   'en_US.utf8'
    TEMPLATE   template0;

COMMENT ON DATABASE :"UMS_DB" IS 'User Management System — application database';
