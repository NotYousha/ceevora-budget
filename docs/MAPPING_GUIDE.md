# Production mapping guide

The production Ceevora table names, key types and COA classification were **not supplied**. The module therefore
reads all ERP data through eight adapter views (`database/oracle/install/02_adapter_views.sql`). In the demo they
read isolated `DM_*` tables. For production, rewrite only the `FROM` / column expressions of these views; keep the
output column names and meanings.

| Adapter view | Required columns | Meaning / rule |
|---|---|---|
| `BX_COMPANY` | COMPANY_ID, COMPANY_CODE, COMPANY_NAME, COMPANY_NAME_AR, BASE_CURRENCY | One row per legal company in the PDB |
| `BX_BRANCH` | BRANCH_ID, COMPANY_ID, BRANCH_CODE, BRANCH_NAME, BRANCH_NAME_AR, IS_ACTIVE ('Y'/'N') | |
| `BX_GL_ACCOUNT` | GL_ACCOUNT_ID, COMPANY_ID, GL_CODE, GL_NAME, GL_NAME_AR, ACCOUNT_TYPE, **BUDGET_CATEGORY**, EXPENSE_GROUP, **NORMAL_BALANCE** ('D'/'C'), IS_POSTING, IS_ACTIVE, **IS_VAT**, **IS_INTERNAL_TRANSFER** | BUDGET_CATEGORY must be SALES, DISCOUNT, RETURN, COGS, OPEX or NULL (not budgetable). Derive from the COA hierarchy/classification, e.g. a CASE over account group codes. Only posting + active + categorised accounts can be budgeted |
| `BX_FIN_PERIOD` | COMPANY_ID, FIN_YEAR, PERIOD_NO, PERIOD_NAME, START_DATE, END_DATE | Periods must not overlap (validation script checks) |
| `BX_JV_HEADER` | JV_ID, COMPANY_ID, BRANCH_ID, JV_NO, JV_DATE (TRUNC), JV_TYPE, STATUS, DESCRIPTION | STATUS must map to 'POSTED' for posted and 'DRAFT' for unposted (drives the provisional flag). JV_TYPE must map internal transfers to 'INTERNAL_TRANSFER' and credit-sale settlements to 'CREDIT_SETTLEMENT' |
| `BX_JV_DETAILS` | JV_ID, LINE_NO, GL_ACCOUNT_ID, BRANCH_ID (nullable: header branch used), DEBIT, CREDIT, NARRATION | |
| `BX_USERS` | USER_ID, USERNAME, FULL_NAME, PASSWORD_HASH, ROLE_CODE, COMPANY_ID, ALL_BRANCHES, IS_ACTIVE | See authentication below |
| `BX_USER_BRANCH` | USER_ID, BRANCH_ID | Branch authorisation when ALL_BRANCHES = 'N' |

## Decisions the Ceevora team must make before integration

1. **Authentication.** The demo verifies PBKDF2 hashes in `BX_USERS.PASSWORD_HASH`. Production should use the
   existing Ceevora identity provider (SSO / existing token). Replace `login()` in `backend/app/main.py` or accept
   the existing Ceevora token and map it to a username. Not implemented because the identity contract was not supplied.
2. **Role mapping.** Map Ceevora roles to ADMIN, ACCOUNTANT, FINANCE_MANAGER, BRANCH_MANAGER in `BX_USERS.ROLE_CODE`.
3. **Sales exclusion rules.** Confirm how internal transfers, credit settlements and VAT are posted. If they are
   identified by account rather than voucher type, set the account flags instead.
4. **Key types.** The scripts use `NUMBER` keys. If Ceevora uses VARCHAR2/RAW keys, change BRANCH_ID /
   GL_ACCOUNT_ID / COMPANY_ID types in `01_budget_tables.sql` before installing.
5. **Cross-schema grants.** If BX views read tables owned by another schema, that owner must grant
   `SELECT ... WITH GRANT OPTION` to the budget schema owner, or `04_grants.sql` fails for those views.
6. **Tenant registry.** Point `CEEVORA_TENANTS_FILE` at a registry generated from the existing Ceevora database
   registry (one entry per customer PDB, credentials referenced by environment variable name).

## Validation after mapping
Run `database/oracle/validation/90_validate.sql`. Then compare one month of `V_BUDGET_ACTUAL` net sales per branch
with the ERP's own sales report; differences point to category, sign or exclusion mapping errors.
