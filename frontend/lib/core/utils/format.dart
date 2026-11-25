import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';

/// Parses API money/percent values (sent as strings to keep precision). Null stays null (N/A).
Decimal? dec(Object? v) => v == null ? null : Decimal.parse(v.toString());
Decimal decOr0(Object? v) => dec(v) ?? Decimal.zero;

/// Exact 2-decimal grouping, no float conversion: 1234567.5 -> 1,234,567.50
String fmtMoney(Object? v, {bool blankZero = false}) {
  final d = dec(v);
  if (d == null) return 'N/A';
  if (blankZero && d == Decimal.zero) return '';
  final s = d.toStringAsFixed(2);
  final neg = s.startsWith('-');
  final parts = (neg ? s.substring(1) : s).split('.');
  final buf = StringBuffer();
  final ip = parts[0];
  for (var i = 0; i < ip.length; i++) {
    if (i > 0 && (ip.length - i) % 3 == 0) buf.write(',');
    buf.write(ip[i]);
  }
  return '${neg ? '-' : ''}$buf.${parts[1]}';
}

String fmtPct(Object? v) {
  final d = dec(v);
  return d == null ? 'N/A' : '${d.toStringAsFixed(2)}%';
}

String fmtDate(Object? v, [String locale = 'en']) {
  if (v == null) return '';
  final d = v is DateTime ? v : DateTime.tryParse(v.toString());
  return d == null ? v.toString() : DateFormat.yMMMd(locale).format(d);
}

String fmtDateTime(Object? v, [String locale = 'en']) {
  if (v == null) return '';
  final d = DateTime.tryParse(v.toString());
  return d == null ? v.toString() : DateFormat.yMMMd(locale).add_Hm().format(d);
}

String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Validates a user-typed amount: up to 2 decimals, non-negative.
Decimal? parseAmount(String text) {
  final t = text.replaceAll(',', '').trim();
  if (t.isEmpty) return Decimal.zero;
  if (!RegExp(r'^\d{1,14}(\.\d{0,2})?$').hasMatch(t)) return null;
  return Decimal.parse(t);
}
