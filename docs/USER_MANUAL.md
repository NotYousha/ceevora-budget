# User manual

Sign in with your company code, username and password. Use **العربية / English** (top bar) to switch language;
Arabic switches the whole screen to right-to-left. The left menu only shows what your role allows.

## 01 Budget Master
* **New** clears the form. Fill Budget No., Name, Financial Year (dates fill from the year), Currency (defaults to
  the company currency), Allocation Method and Remarks, then **Save**.
* **Search** finds budgets by number or name. **Budget Entry** opens the lines. **Submit** sends a DRAFT for approval.
* **View History** shows Approval History (01A) and Revision History (01B), filterable by version, exportable to Excel.
* Only one operating budget per financial year is allowed. After approval the header is read-only; use Revision.

## 02 Budget Entry
1. **Search** a budget, then pick a **Branch**. Account columns stay fixed while months scroll horizontally.
2. **Add Account** (searchable list of active posting accounts) / **Remove Account** (select a row by its description first).
3. Type monthly amounts (Tab moves between cells). Invalid cells turn red and block Save.
4. **Copy Previous Month** copies the column to the left into the selected month for every row.
   **Copy to All Months** copies the selected cell across its row.
5. The bar under the grid recalculates Net Sales, COGS, Gross Profit, Opex and Operating Profit as you type.
6. **Save**, then **Submit**. **Cancel** discards unsaved changes. **Excel** exports the grid.

## 03 Approval (Finance Manager)
Select a submitted budget to see branch and company totals. **View Details** opens the lines read-only.
**Approve** freezes original amounts as version 1. **Reject** requires remarks and returns the budget to DRAFT.
With segregation of duties on, you cannot approve a budget you submitted.

## 04 Revision
Search an approved budget, choose Branch, Period and GL account. The screen shows the original and current approved
amounts; enter the Proposed Amount and a Reason, then **Save Revision** (status PENDING). Finance Managers tick
pending rows and **Approve Revision** or **Reject Revision**. Only approved revisions change reported budgets, and
each approval increases the budget version. Originals never change.

## 05 Dashboard
Filter by year, period or a date range, branch, category and GL account. KPIs show budget, actual, variance
(green favourable, red unfavourable) and achievement. Tap a branch bar or a row in the table to drill down to GL
accounts and then to posted vouchers.

## 06 Daily Performance / 07 Daily P&L
Choose the business date (and branch, or all branches for a consolidated row). Daily Performance shows daily and
month-to-date net sales against budget, the remaining monthly target and the average daily sales still needed.
Daily P&L shows gross sales to operating profit for the day or month to date. An orange **PROVISIONAL** banner
means unposted vouchers exist, so actuals may still change.

## Management Reports (R01 to R06)
Pick a report and period type (daily, MTD, monthly, YTD, yearly, custom), optional branch and category. Click a
column header to sort; page with the arrows. **Excel** downloads all rows; **PDF / Print** opens a print preview
with company, branch, period, currency, title and generation date.

## Administration
Tick permissions per role and switch segregation of duties on or off, then **Save**.
