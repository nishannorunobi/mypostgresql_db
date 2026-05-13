-- 01_create_user.sql — Create the mydocsdb application user (idempotent)

SELECT NOT EXISTS (
    SELECT FROM pg_roles WHERE rolname = :'DOCS_USER'
) AS user_missing \gset

\if :user_missing
    CREATE USER :"DOCS_USER" WITH PASSWORD :'DOCS_PASSWORD';
\else
    ALTER USER :"DOCS_USER" WITH PASSWORD :'DOCS_PASSWORD';
\endif
