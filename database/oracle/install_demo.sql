-- Isolated DEMO install (Demo Donuts 2027). Use a dedicated test schema or PDB only.
--   sqlplus <test_owner>@<test_pdb> @install_demo.sql      (set NLS_LANG=.AL32UTF8 first for Arabic names)
WHENEVER SQLERROR EXIT FAILURE ROLLBACK
SET ECHO ON
@@install/01_budget_tables.sql
@@demo/10_demo_master_tables.sql
@@install/02_adapter_views.sql
@@../common/03_reporting_views.sql
@@install/04_grants.sql
@@demo/20_demo_data.sql
@@validation/90_validate.sql
@@validation/91_validate_demo.sql
