-- 01_create_user.sql — Create the application DB user (idempotent)

SELECT NOT EXISTS (
    SELECT FROM pg_roles WHERE rolname = :'UMS_USER'
) AS user_missing \gset

\if :user_missing
    CREATE USER :"UMS_USER" WITH PASSWORD :'UMS_PASSWORD';
\else
    ALTER USER :"UMS_USER" WITH PASSWORD :'UMS_PASSWORD';
\endif
