import 'package:decimal/decimal.dart';

/// Live grid preview of the P&L. The server recalculates authoritatively on save (backend/app/calc.py).
/// Net sales = sales - discounts - returns; GP = net - COGS; OP = GP - opex.
Map<String, Decimal> entrySummary(
  List<({String category, List<Decimal> amounts})> lines,
  int periods,
) {
  final by = <String, Decimal>{};
  for (final l in lines) {
    by[l.category] =
        (by[l.category] ?? Decimal.zero) +
        l.amounts.take(periods).fold(Decimal.zero, (a, b) => a + b);
  }
  Decimal g(String k) => by[k] ?? Decimal.zero;
  final net = g('SALES') - g('DISCOUNT') - g('RETURN');
  final gp = net - g('COGS');
  return {
    'GROSS_SALES': g('SALES'),
    'NET_SALES': net,
    'COGS': g('COGS'),
    'GROSS_PROFIT': gp,
    'OPEX': g('OPEX'),
    'OPERATING_PROFIT': gp - g('OPEX'),
  };
}
