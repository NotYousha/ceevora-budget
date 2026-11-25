import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../models/models.dart';

String newIdempotencyKey() {
  final r = Random.secure();
  return List.generate(24, (_) => r.nextInt(16).toRadixString(16)).join();
}

/// Typed access to every Budget API endpoint.
class BudgetRepository {
  final ApiClient api;
  BudgetRepository(this.api);

  Future<Json> login(String tenant, String user, String password) => api.post(
    '/auth/login',
    {'tenant': tenant, 'username': user, 'password': password},
  );

  // lookups
  Future<List<Branch>> branches() async =>
      (await api.get<List>('/lookups/branches'))
          .map((b) => Branch.fromJson(b))
          .toList();
  Future<List<int>> years() async =>
      List<int>.from(await api.get<List>('/lookups/years'));
  Future<List<Period>> periods(int year) async => (await api.get<List>(
    '/lookups/periods',
    {'year': year},
  )).map((p) => Period.fromJson(p)).toList();
  Future<List<GlAccount>> glAccounts({String? q, String? category}) async =>
      (await api.get<List>('/lookups/gl-accounts', {
        'q': q,
        'category': category,
      })).map((g) => GlAccount.fromJson(g)).toList();

  // master
  Future<({List<Budget> items, int total})> search({
    String? q,
    int? year,
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    final r = await api.get<Json>('/budgets', {
      'q': q,
      'year': year,
      'status': status,
      'page': page,
      'page_size': pageSize,
    });
    return (
      items: (r['items'] as List).map((b) => Budget.fromJson(b)).toList(),
      total: r['total'] as int,
    );
  }

  Future<Budget> get(int id) async =>
      Budget.fromJson(await api.get<Json>('/budgets/$id'));
  Future<Budget> create(Json body) async => Budget.fromJson(
    await api.post<Json>('/budgets', body, idempotencyKey: newIdempotencyKey()),
  );
  Future<Budget> update(int id, Json body) async =>
      Budget.fromJson(await api.put<Json>('/budgets/$id', body));

  // entry
  Future<BudgetEntry> entry(int id, int branchId) async => BudgetEntry.fromJson(
    await api.get<Json>('/budgets/$id/entry', {'branch_id': branchId}),
  );
  Future<BudgetEntry> saveEntry(
    int id,
    int branchId,
    int rowVersion,
    List<EntryLine> lines,
  ) async => BudgetEntry.fromJson(
    await api.put<Json>('/budgets/$id/entry', {
      'branch_id': branchId,
      'row_version': rowVersion,
      'lines': lines.map((l) => l.toJson()).toList(),
    }),
  );

  // workflow
  Future<Json> summary(int id) => api.get<Json>('/budgets/$id/summary');
  Future<Budget> submit(int id, int rv, [String? remarks]) async =>
      Budget.fromJson(
        await api.post<Json>('/budgets/$id/submit', {
          'row_version': rv,
          'remarks': remarks,
        }, idempotencyKey: newIdempotencyKey()),
      );
  Future<Budget> approve(int id, int rv, [String? remarks]) async =>
      Budget.fromJson(
        await api.post<Json>('/budgets/$id/approve', {
          'row_version': rv,
          'remarks': remarks,
        }, idempotencyKey: newIdempotencyKey()),
      );
  Future<Budget> reject(int id, int rv, String reason) async => Budget.fromJson(
    await api.post<Json>('/budgets/$id/reject', {
      'row_version': rv,
      'reason': reason,
    }, idempotencyKey: newIdempotencyKey()),
  );

  // history
  Future<List<ApprovalHistory>> approvalHistory(int id, {int? version}) async =>
      (await api.get<List>('/budgets/$id/approval-history', {
        'version': version,
      })).map((h) => ApprovalHistory.fromJson(h)).toList();
  Future<List<RevisionHistory>> revisionHistory(
    int id, {
    int? version,
    String? status,
  }) async => (await api.get<List>('/budgets/$id/revision-history', {
    'version': version,
    'status': status,
  })).map((h) => RevisionHistory.fromJson(h)).toList();

  // revisions
  Future<Json> revisionLine(int id, int branchId, int glId, int periodNo) =>
      api.get<Json>('/budgets/$id/revision-line', {
        'branch_id': branchId,
        'gl_account_id': glId,
        'period_no': periodNo,
      });
  Future<Json> requestRevision(int id, Json body, String idemKey) =>
      api.post<Json>('/budgets/$id/revisions', body, idempotencyKey: idemKey);
  Future<Json> approveRevisions(List<int> ids, [String? remarks]) =>
      api.post<Json>('/revisions/approve', {
        'revision_ids': ids,
        'remarks': remarks,
      }, idempotencyKey: newIdempotencyKey());
  Future<Json> rejectRevisions(List<int> ids, String reason) => api.post<Json>(
    '/revisions/reject',
    {'revision_ids': ids, 'reason': reason},
    idempotencyKey: newIdempotencyKey(),
  );

  // analytics
  Future<Json> dashboard(Json q) => api.get<Json>('/dashboard', q);
  Future<List> drillGl(Json q) => api.get<List>('/drilldown/gl', q);
  Future<Json> drillTransactions(Json q) =>
      api.get<Json>('/drilldown/transactions', q);
  Future<Json> dailyPerformance(Json q) =>
      api.get<Json>('/daily/performance', q);
  Future<Json> dailyPl(Json q) => api.get<Json>('/daily/pl', q);
  Future<ReportData> report(String code, Json q) async =>
      ReportData.fromJson(await api.get<Json>('/reports/$code', q));

  // admin
  Future<Json> permissions() => api.get<Json>('/admin/permissions');
  Future<Json> savePermissions(Map<String, List<String>> matrix) =>
      api.put<Json>('/admin/permissions', {'matrix': matrix});
  Future<Json> saveSettings(bool sod) =>
      api.put<Json>('/admin/settings', {'sod_enforced': sod});
}

final repoProvider = Provider<BudgetRepository>(
  (ref) => BudgetRepository(ref.watch(apiProvider)),
);
