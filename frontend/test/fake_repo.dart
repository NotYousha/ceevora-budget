import 'package:ceevora_budget/core/network/api_client.dart';
import 'package:ceevora_budget/shared/models/models.dart';
import 'package:ceevora_budget/shared/repositories/budget_repository.dart';
import 'package:dio/dio.dart';

Json budgetJson({int id = 1, String status = 'SUBMITTED', int rv = 3}) => {
  'budget_id': id,
  'company_id': 1,
  'budget_no': 'BUD-2028-001',
  'budget_name': 'Plan 2028',
  'budget_type': 'OPERATING',
  'fin_year': 2028,
  'start_date': '2028-01-01',
  'end_date': '2028-12-31',
  'currency_code': 'SAR',
  'allocation_method': 'CALENDAR_DAYS',
  'status': status,
  'version_no': 0,
  'remarks': null,
  'row_version': rv,
  'submitted_by': 'accountant',
  'created_by': 'accountant',
  'created_at': '2026-11-25T09:00:00',
  'updated_by': null,
  'updated_at': null,
};

const loginJson = {
  'token': 't',
  'expires_at': '2099-01-01T00:00:00+00:00',
  'user': {
    'user_id': 3,
    'username': 'fmanager',
    'full_name': 'Faisal',
    'role': 'FINANCE_MANAGER',
    'company_id': 1,
    'tenant': 'DEMO',
    'permissions': [
      'BUDGET_VIEW',
      'BUDGET_APPROVE',
      'REVISION_APPROVE',
      'DASHBOARD_VIEW',
      'REPORT_VIEW',
    ],
    'branch_ids': [1, 2, 3],
  },
  'company': {
    'company_id': 1,
    'company_code': 'DEMO',
    'company_name': 'Demo Donuts Co.',
    'company_name_ar': 'شركة',
    'base_currency': 'SAR',
  },
};

Json bva(String b, String a) => {
  'budget': b,
  'actual': a,
  'variance': '-10000.00',
  'achievement_pct': '97.78',
  'favourable': false,
};

/// In-memory stand-in for the REST API; records write calls for assertions.
class FakeRepo extends BudgetRepository {
  FakeRepo() : super(ApiClient(Dio()));
  final calls = <String>[];

  @override
  Future<Json> login(String tenant, String user, String password) async {
    calls.add('login:$tenant:$user');
    if (password != 'Demo@2027') {
      throw ApiException(
        401,
        'INVALID_CREDENTIALS',
        'Invalid tenant, username or password',
      );
    }
    return Map<String, dynamic>.from(loginJson);
  }

  @override
  Future<List<Branch>> branches() async => [
    Branch.fromJson({
      'branch_id': 1,
      'branch_code': 'RUH',
      'branch_name': 'Riyadh',
      'branch_name_ar': 'الرياض',
    }),
  ];
  @override
  Future<List<int>> years() async => [2027];
  @override
  Future<List<Period>> periods(int year) async => [
    Period.fromJson({
      'period_no': 1,
      'period_name': 'Jan-2027',
      'start_date': '2027-01-01',
      'end_date': '2027-01-31',
    }),
  ];
  @override
  Future<List<GlAccount>> glAccounts({String? q, String? category}) async => [];

  @override
  Future<({List<Budget> items, int total})> search({
    String? q,
    int? year,
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async => (items: [Budget.fromJson(budgetJson())], total: 1);

  @override
  Future<Json> summary(int id) async => {
    'budget': budgetJson(),
    'branches': [
      {
        'branch_id': 1,
        'branch_name': 'Riyadh',
        'branch_name_ar': 'الرياض',
        'NET_SALES': '200000.00',
      },
    ],
    'company': {'NET_SALES': '200000.00'},
  };

  @override
  Future<Budget> reject(int id, int rv, String reason) async {
    calls.add('reject:$id:$rv:$reason');
    return Budget.fromJson(budgetJson(status: 'DRAFT', rv: rv + 1));
  }

  @override
  Future<Json> dashboard(Json q) async => {
    'date_from': '2027-01-01',
    'date_to': '2027-12-31',
    'provisional': true,
    'kpis': {
      'net_sales': bva('450000.00', '440000.00'),
      'expenses': bva('1.00', '1.00'),
      'gross_profit': bva('1.00', '1.00'),
      'operating_profit': bva('1.00', '1.00'),
    },
    'branches': [
      {
        'branch_id': 1,
        'branch_name': 'Riyadh',
        'branch_name_ar': 'الرياض',
        'sales_budget': '200000.00',
        'sales_actual': '185000.00',
        'expense_budget': '1',
        'expense_actual': '1',
        'utilization_pct': '100.00',
        'profit_budget': '1',
        'profit_actual': '1',
      },
    ],
    'trend': [
      {
        'period_no': 1,
        'sales_budget': '450000',
        'sales_actual': '440000',
        'profit_budget': '1',
        'profit_actual': '1',
      },
    ],
    'expense_categories': [
      {'group': 'Staff', 'budget': '10', 'actual': '9'},
    ],
  };
}
