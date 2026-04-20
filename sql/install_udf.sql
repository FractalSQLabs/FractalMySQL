-- mysql-fractalsql UDF registration.
--
-- Prerequisite: fractalsql.so has been placed in MySQL's plugin
-- directory (see `mysql_config --plugindir`, typically
-- /usr/lib/mysql/plugin/). The release .deb / .rpm packages do this
-- for you; on Windows the MSI drops fractalsql.dll into
--   C:\Program Files\MySQL\MySQL Server <VER>\lib\plugin\
-- and the same CREATE FUNCTION statements apply.
--
-- Run once, as a user with CREATE FUNCTION privilege:
--   mysql -u root -p < sql/install_udf.sql
--
-- Or from an interactive session:
--   SOURCE /usr/share/mysql-fractalsql/install_udf.sql;
--
-- The statements are idempotent — each DROP FUNCTION IF EXISTS pairs
-- with its CREATE FUNCTION so re-running the script upgrades the UDF
-- registrations cleanly.

DROP FUNCTION IF EXISTS fractal_search;
DROP FUNCTION IF EXISTS fractalsql_edition;
DROP FUNCTION IF EXISTS fractalsql_version;

-- Signature:
--   fractal_search(vector_csv  TEXT,
--                  query_csv   TEXT,
--                  k           INT,
--                  params      TEXT  -- JSON object
--                 ) RETURNS STRING   -- JSON document
--
-- One .so covers MySQL 8.0 / 8.4 LTS / 9.x — the UDF ABI has been
-- stable since 8.0.0, so CREATE FUNCTION registers identically across
-- all supported majors.
CREATE FUNCTION fractal_search RETURNS STRING
SONAME 'fractalsql.so';

-- Edition / version helpers — zero-arg UDFs that return string
-- literals baked into the shared object.
CREATE FUNCTION fractalsql_edition RETURNS STRING
SONAME 'fractalsql.so';

CREATE FUNCTION fractalsql_version RETURNS STRING
SONAME 'fractalsql.so';

-- Verify installation:
--   SELECT fractalsql_edition(), fractalsql_version();
--   SELECT name, dl FROM mysql.func;
--
-- Example call + JSON_EXTRACT slice:
--
--   SET @corpus = '[[1,0,0],[0,1,0],[0,0,1],[0.5,0.5,0]]';
--   SET @query  = '[0.6,0.6,0]';
--   SET @params = '{"iterations":30,"population_size":50,"walk":0.5}';
--
--   SELECT
--     JSON_EXTRACT(r, '$.best_point')    AS best_point,
--     JSON_EXTRACT(r, '$.top_k[0].idx')  AS top_hit,
--     JSON_EXTRACT(r, '$.top_k[0].dist') AS top_dist
--   FROM (
--     SELECT CONVERT(fractal_search(@corpus, @query, 3, @params)
--                    USING utf8mb4) AS r
--   ) t;
--
-- Why the CONVERT wrapper: MySQL 8.0+ tags UDF STRING returns with
-- CHARACTER SET 'binary', and JSON_EXTRACT refuses binary-charset
-- strings with ERROR 3144. Re-tagging as utf8mb4 is a no-op on the
-- underlying bytes (the payload is pure ASCII JSON) and unblocks the
-- JSON functions. MariaDB's JSON_EXTRACT is permissive and accepts
-- the raw UDF return without a CONVERT.
