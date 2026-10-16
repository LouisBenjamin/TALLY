import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';

// Parse any num to Decimal. Use this everywhere — never pass double amounts
// to Supabase. Convert at the boundary (DB read → model → UI).
Decimal toDecimal(num value) => Decimal.parse(value.toString());

String formatCurrency(Decimal amount, {String currency = 'CAD'}) {
  return NumberFormat.currency(
    locale: 'en_CA',
    symbol: r'$',
    decimalDigits: 2,
  ).format(amount.toDouble());
}

// percent of amount, rounded half-up to whole cents. e.g. 12.5% of 100.01 -> 12.50
Decimal percentShare(Decimal amount, Decimal percent) =>
    (amount * percent / Decimal.fromInt(100))
        .toDecimal(scaleOnInfinitePrecision: 10)
        .round(scale: 2);

// Equal split with penny-perfect rounding: first member absorbs any remainder.
// Returns list of share amounts aligned 1-to-1 with [count] members.
List<Decimal> splitEqually(Decimal total, int count) {
  if (count <= 0) return [];
  // floor to whole cents: 10.01 / 2 is exactly 5.005, which no column can store.
  final each = (total / Decimal.fromInt(count))
      .toDecimal(scaleOnInfinitePrecision: 10)
      .floor(scale: 2);
  final remainder = total - each * Decimal.fromInt(count);
  return [
    each + remainder, // first member gets any rounding remainder
    for (var i = 1; i < count; i++) each,
  ];
}
