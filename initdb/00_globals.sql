--
-- PostgreSQL database cluster dump
--

\restrict bRmMscayTB8Wdju1AcTEvvoozLnEyyFjZdGa3JRQcTvtKbpfjuNbEbCCmdm9dy2

SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

--
-- Roles
--

CREATE ROLE docs_user;
ALTER ROLE docs_user WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS PASSWORD 'SCRAM-SHA-256$4096:49Za1T27JQceBXg6SaQq1w==$3wL7j8twuMQxtosZ3Bvv/C8mflVlOND0wvGCkH+RdHA=:mMp3z1z17UwRXA27QlrSIa4imcpSXIl88n+UiM+cr6g=';
CREATE ROLE postgres;
ALTER ROLE postgres WITH SUPERUSER INHERIT CREATEROLE CREATEDB LOGIN REPLICATION BYPASSRLS;
CREATE ROLE ums_user;
ALTER ROLE ums_user WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS PASSWORD 'SCRAM-SHA-256$4096:l0eCcc0pKNkkZreac0h8dw==$SnAVG6AVy5xCHMwK2yZd2v/mLlp1GrXjcEWfFfDiM5I=:mp1agZrNaCu2tf+M0vsog7EGkXyhuWBjUXt7oudOKc4=';

--
-- User Configurations
--








\unrestrict bRmMscayTB8Wdju1AcTEvvoozLnEyyFjZdGa3JRQcTvtKbpfjuNbEbCCmdm9dy2

--
-- PostgreSQL database cluster dump complete
--

