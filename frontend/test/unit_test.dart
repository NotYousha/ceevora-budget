import 'package:ceevora_budget/core/utils/export.dart';
import 'package:ceevora_budget/core/utils/format.dart';
import 'package:ceevora_budget/features/budget_entry/entry_math.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

Decimal d(String s) => Decimal.parse(s);

void main() {
  test('fmtMoney groups exactly without floating point', () {
    expect(fmtMoney('1234567.5'), '1,234,567.50');
    expect(fmtMoney('-1000'), '-1,000.00');
    expect(fmtMoney('0.1'), '0.10');
    expect(fmtMoney('99999999999999.99'), '99,999,999,999,999.99');
    expect(fmtMoney(null), 'N/A');
    expect(fmtPct(null), 'N/A');
    expect(fmtPct('97.78'), '97.78%');
  });

  test('parseAmount validates user input', () {
    expect(parseAmount('1,000.10'), d('1000.10'));
    expect(parseAmount(''), Decimal.zero);
    expect(parseAmount('-5'), isNull);
    expect(parseAmount('1.234'), isNull);
    expect(parseAmount('abc'), isNull);
  });

  test('entry summary follows the P&L formulas', () {
    final s = entrySummary([
      (category: 'SALES', amounts: [d('205000'), d('100')]),
      (category: 'DISCOUNT', amounts: [d('4000'), d('0')]),
      (category: 'RETURN', amounts: [d('1000'), d('0')]),
      (category: 'COGS', amounts: [d('70000'), d('0')]),
      (category: 'OPEX', amounts: [d('80000'), d('0')]),
    ], 2);
    expect(s['NET_SALES'], d('200100'));
    expect(s['GROSS_PROFIT'], d('130100'));
    expect(s['OPERATING_PROFIT'], d('50100'));
  });

  test('Excel and PDF exports produce files', () async {
    final t = ExportTable(
      'R01 Sales Actual vs Budget',
      ['Company: Demo'],
      ['Branch', 'Budget'],
      [
        ['Riyadh', 200000.0],
        ['Jeddah', 150000.0],
      ],
    );
    final xlsx = buildExcel(t);
    expect(xlsx.length, greaterThan(1000));
    expect(String.fromCharCodes(xlsx.sublist(0, 2)), 'PK'); // zip container
    final pdf = await buildPdf(t, PdfPageFormat.a4);
    expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
  });
}
