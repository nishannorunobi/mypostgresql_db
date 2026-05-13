-- 02_create_database.sql — Create the mydocsdb database (idempotent)
-- Run as superuser (postgres). Idempotency guarded by the calling script.

CREATE DATABASE :"DOCS_DB"
    OWNER      :"DOCS_USER"
    ENCODING   'UTF8'
    LC_COLLATE 'en_US.utf8'
    LC_CTYPE   'en_US.utf8'
    TEMPLATE   template0;

COMMENT ON DATABASE :"DOCS_DB" IS 'mydocs — Plane project management database';
