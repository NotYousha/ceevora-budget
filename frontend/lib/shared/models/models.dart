import 'package:decimal/decimal.dart';

import '../../core/utils/format.dart';

typedef Json = Map<String, dynamic>;

int _int(Object? v) => v is int ? v : int.parse(v.toString());

class AppUser {
  final String username, fullName, role;
  final int companyId;
  final List<String> permissions;
  final List<int> branchIds;
  AppUser.fromJson(Json j)
    : username = j['username'],
      fullName = j['full_name'],
      role = j['role'],
      companyId = _int(j['company_id']),
      permissions = List<String>.from(j['permissions']),
      branchIds = (j['branch_ids'] as List).map(_int).toList();
}

class Company {
  final int id;
  final String code, name, currency;
  final String? nameAr;
  Company.fromJson(Json j)
    : id = _int(j['company_id']),
      code = j['company_code'],
      name = j['company_name'],
      nameAr = j['company_name_ar'],
      currency = j['base_currency'];
}

class Branch {
  final int id;
  final String code, name;
  final String? nameAr;
  Branch.fromJson(Json j)
    : id = _int(j['branch_id']),
      code = j['branch_code'],
      name = j['branch_name'],
      nameAr = j['branch_name_ar'];
  String label(bool ar) => ar && nameAr != null ? nameAr! : name;
}

class GlAccount {
  final int id;
  final String code, name, category;
  final String? nameAr;
  GlAccount.fromJson(Json j)
    : id = _int(j['gl_account_id']),
      code = j['gl_code'],
      name = j['gl_name'],
      nameAr = j['gl_name_ar'],
      category = j['budget_category'] ?? j['category'];
  String label(bool ar) => ar && nameAr != null ? nameAr! : name;
}

class Period {
  final int no;
  final String name;
  final String startDate, endDate;
  Period.fromJson(Json j)
    : no = _int(j['period_no']),
      name = j['period_name'],
      startDate = '${j['start_date']}',
      endDate = '${j['end_date']}';
}

class Budget {
  final int id, companyId, finYear, versionNo, rowVersion;
  final String budgetNo,
      budgetName,
      status,
      currency,
      allocationMethod,
      startDate,
      endDate,
      createdBy,
      createdAt;
  final String? remarks, updatedBy, updatedAt, submittedBy;
  Budget.fromJson(Json j)
    : id = _int(j['budget_id']),
      companyId = _int(j['company_id']),
      finYear = _int(j['fin_year']),
      versionNo = _int(j['version_no']),
      rowVersion = _int(j['row_version']),
      budgetNo = j['budget_no'],
      budgetName = j['budget_name'],
      status = j['status'],
      currency = j['currency_code'],
      allocationMethod = j['allocation_method'],
      startDate = '${j['start_date']}'.substring(0, 10),
      endDate = '${j['end_date']}'.substring(0, 10),
      createdBy = j['created_by'],
      createdAt = '${j['created_at']}',
      remarks = j['remarks'],
      updatedBy = j['updated_by'],
      updatedAt = j['updated_at']?.toString(),
      submittedBy = j['submitted_by'];
  bool get isDraft => status == 'DRAFT';
}

class EntryLine {
  final GlAccount account;
  final List<Decimal> amounts;
  EntryLine(this.account, this.amounts);
  EntryLine.fromJson(Json j)
    : account = GlAccount.fromJson(j),
      amounts = (j['amounts'] as List).map(decOr0).toList();
  Decimal get total => amounts.fold(Decimal.zero, (a, b) => a + b);
  Json toJson() => {
    'gl_account_id': account.id,
    'amounts': amounts.map((a) => a.toStringAsFixed(2)).toList(),
  };
}

class BudgetEntry {
  final Budget budget;
  final int branchId;
  final List<Period> periods;
  final List<EntryLine> lines;
  BudgetEntry.fromJson(Json j)
    : budget = Budget.fromJson(j['budget']),
      branchId = _int(j['branch_id']),
      periods = (j['periods'] as List).map((p) => Period.fromJson(p)).toList(),
      lines = (j['lines'] as List).map((l) => EntryLine.fromJson(l)).toList();
}

class ApprovalHistory {
  final String action, actionBy, actionAt;
  final String? prevStatus, newStatus, remarks, rejectionReason;
  final int versionNo;
  ApprovalHistory.fromJson(Json j)
    : action = j['action'],
      actionBy = j['action_by'],
      actionAt = '${j['action_at']}',
      prevStatus = j['previous_status'],
      newStatus = j['new_status'],
      remarks = j['remarks'],
      rejectionReason = j['rejection_reason'],
      versionNo = _int(j['version_no']);
}

class RevisionHistory {
  final int id, periodNo, branchId, baseVersion;
  final int? versionNo;
  final String branchName, glCode, glName, status, reason, revisedBy, revisedAt;
  final String? branchNameAr, glNameAr, rejectionReason, approvedBy, approvedAt;
  final Decimal original, previous, revised, difference;
  final Decimal? pct;
  RevisionHistory.fromJson(Json j)
    : id = _int(j['revision_id']),
      periodNo = _int(j['period_no']),
      branchId = _int(j['branch_id']),
      baseVersion = _int(j['base_version_no']),
      versionNo = j['version_no'] == null ? null : _int(j['version_no']),
      branchName = j['branch_name'],
      branchNameAr = j['branch_name_ar'],
      glCode = j['gl_code'],
      glName = j['gl_name'],
      glNameAr = j['gl_name_ar'],
      status = j['status'],
      reason = j['reason'],
      revisedBy = j['revised_by'],
      revisedAt = '${j['revised_at']}',
      rejectionReason = j['rejection_reason'],
      approvedBy = j['approved_by'],
      approvedAt = j['approved_at']?.toString(),
      original = decOr0(j['original_amount']),
      previous = decOr0(j['previous_approved_amount']),
      revised = decOr0(j['revised_amount']),
      difference = decOr0(j['difference_amount']),
      pct = dec(j['difference_pct']);
}

/// Report / grid payload with dynamic columns (R01-R06 share one framework).
class ReportColumn {
  final String key, label, type;
  ReportColumn(this.key, this.label, this.type);
  ReportColumn.fromJson(Json j)
    : key = j['key'],
      label = j['label'],
      type = j['type'];
}

class ReportData {
  final String code,
      title,
      company,
      currency,
      branches,
      periodLabel,
      generatedAt;
  final List<ReportColumn> columns;
  final List<Json> rows;
  final Json? totals;
  final int totalRows, page, pageSize;
  final bool provisional;
  ReportData.fromJson(Json j)
    : code = j['code'],
      title = j['title'],
      company = j['company'],
      currency = j['currency'],
      branches = j['branches'],
      periodLabel = j['period_label'],
      generatedAt = '${j['generated_at']}',
      columns = (j['columns'] as List)
          .map((c) => ReportColumn.fromJson(c))
          .toList(),
      rows = List<Json>.from(j['rows']),
      totals = j['totals'],
      totalRows = _int(j['total_rows']),
      page = _int(j['page']),
      pageSize = _int(j['page_size']),
      provisional = j['provisional'] == true;
}
