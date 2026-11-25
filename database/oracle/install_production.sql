-- Production install (no demo data):  sqlplus <schema_owner>@<pdb_service> @install_production.sql
-- PREREQUISITE: edit install/02_adapter_views.sql so the BX_* views read the real Ceevora tables.
WHENEVER SQLERROR EXIT FAILURE ROLLBACK
SET ECHO ON
@@install/01_budget_tables.sql
@@install/02_adapter_views.sql
@@../common/03_reporting_views.sql
@@install/04_grants.sql
@@install/05_seed_config.sql
@@validation/90_validate.sql
