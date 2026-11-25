-- Budget reporting views. Portable SQL shared by Oracle (install) and the SQLite standalone demo.
-- Keep this file free of dialect-specific syntax: no AS for table aliases, no date arithmetic.

-- Active approved amounts. Pending/rejected revisions never appear because only approved
-- revisions change BUDGET_DETAILS.CURRENT_AMOUNT. BM_ANNUAL_UK guarantees one operating
-- budget per company and year, so this view cannot duplicate amounts.
CREATE OR REPLACE VIEW V_BUDGET_APPROVED AS
SELECT m.COMPANY_ID,
       m.BUDGET_ID,
       m.FIN_YEAR,
       m.VERSION_NO,
       d.BRANCH_ID,
       d.GL_ACCOUNT_ID,
       d.PERIOD_NO,
       d.ORIGINAL_AMOUNT,
       d.CURRENT_AMOUNT AS BUDGET_AMOUNT
FROM BUDGET_MASTER m
JOIN BUDGET_DETAILS d ON d.BUDGET_ID = m.BUDGET_ID
WHERE m.STATUS = 'APPROVED'
  AND m.BUDGET_TYPE = 'OPERATING';

-- Posted actuals per day, signed by the account's normal balance (revenue = credit - debit,
-- contra-revenue / cost = debit - credit). VAT, internal-transfer accounts and internal-transfer /
-- credit-settlement vouchers are excluded. Aggregated per day so joins cannot multiply rows.
CREATE OR REPLACE VIEW V_BUDGET_ACTUAL AS
SELECT h.COMPANY_ID,
       COALESCE(l.BRANCH_ID, h.BRANCH_ID) AS BRANCH_ID,
       l.GL_ACCOUNT_ID,
       p.FIN_YEAR,
       p.PERIOD_NO,
       h.JV_DATE,
       SUM(CASE WHEN g.NORMAL_BALANCE = 'C' THEN l.CREDIT - l.DEBIT ELSE l.DEBIT - l.CREDIT END) AS ACTUAL_AMOUNT
FROM BX_JV_HEADER h
JOIN BX_JV_DETAILS l ON l.JV_ID = h.JV_ID
JOIN BX_GL_ACCOUNT g ON g.GL_ACCOUNT_ID = l.GL_ACCOUNT_ID
JOIN BX_FIN_PERIOD p ON p.COMPANY_ID = h.COMPANY_ID
                    AND h.JV_DATE BETWEEN p.START_DATE AND p.END_DATE
WHERE h.STATUS = 'POSTED'
  AND g.BUDGET_CATEGORY IS NOT NULL
  AND g.IS_VAT = 'N'
  AND g.IS_INTERNAL_TRANSFER = 'N'
  AND h.JV_TYPE NOT IN ('INTERNAL_TRANSFER', 'CREDIT_SETTLEMENT')
GROUP BY h.COMPANY_ID, COALESCE(l.BRANCH_ID, h.BRANCH_ID), l.GL_ACCOUNT_ID, p.FIN_YEAR, p.PERIOD_NO, h.JV_DATE;

-- Monthly budget vs actual including unbudgeted actuals. UNION ALL + GROUP BY (not a join)
-- so each side is counted exactly once. Revenue variance = actual - budget; cost variance = budget - actual.
CREATE OR REPLACE VIEW V_BUDGET_VARIANCE AS
SELECT x.COMPANY_ID,
       x.FIN_YEAR,
       x.PERIOD_NO,
       x.BRANCH_ID,
       x.GL_ACCOUNT_ID,
       g.GL_CODE,
       g.BUDGET_CATEGORY,
       SUM(x.BUDGET_AMOUNT) AS BUDGET_AMOUNT,
       SUM(x.ACTUAL_AMOUNT) AS ACTUAL_AMOUNT,
       CASE WHEN g.BUDGET_CATEGORY = 'SALES'
            THEN SUM(x.ACTUAL_AMOUNT) - SUM(x.BUDGET_AMOUNT)
            ELSE SUM(x.BUDGET_AMOUNT) - SUM(x.ACTUAL_AMOUNT) END AS VARIANCE_AMOUNT,
       CASE WHEN SUM(x.BUDGET_COUNT) = 0 THEN 'Y' ELSE 'N' END AS IS_UNBUDGETED
FROM (
  SELECT COMPANY_ID, FIN_YEAR, PERIOD_NO, BRANCH_ID, GL_ACCOUNT_ID,
         BUDGET_AMOUNT, 0 AS ACTUAL_AMOUNT, 1 AS BUDGET_COUNT
  FROM V_BUDGET_APPROVED
  UNION ALL
  SELECT COMPANY_ID, FIN_YEAR, PERIOD_NO, BRANCH_ID, GL_ACCOUNT_ID,
         0, ACTUAL_AMOUNT, 0
  FROM V_BUDGET_ACTUAL
) x
JOIN BX_GL_ACCOUNT g ON g.GL_ACCOUNT_ID = x.GL_ACCOUNT_ID
GROUP BY x.COMPANY_ID, x.FIN_YEAR, x.PERIOD_NO, x.BRANCH_ID, x.GL_ACCOUNT_ID, g.GL_CODE, g.BUDGET_CATEGORY;
