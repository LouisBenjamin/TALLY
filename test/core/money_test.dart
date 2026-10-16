import 'package:decimal/decimal.dart';
import 'package:tally/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

Decimal d(String s) => Decimal.parse(s);

void main() {
  group('splitEqually', () {
    test('divides evenly when it can', () {
      expect(splitEqually(d('100'), 4), [d('25'), d('25'), d('25'), d('25')]);
    });

    test('first member absorbs the rounding remainder', () {
      final shares = splitEqually(d('100'), 3);
      expect(shares, [d('33.34'), d('33.33'), d('33.33')]);
      expect(shares.reduce((a, b) => a + b), d('100'));
    });

    test('always sums back to the original total (penny-perfect)', () {
      for (final total in ['0.01', '0.10', '10', '10.01', '19.99', '1000.03', '7.77']) {
        for (var n = 1; n <= 7; n++) {
          final shares = splitEqually(d(total), n);
          expect(shares.length, n);
          for (final s in shares) {
            expect(s.scale <= 2, isTrue, reason: 'sub-cent share $s');
          }
          expect(
            shares.reduce((a, b) => a + b),
            d(total),
            reason: 'total=$total n=$n',
          );
        }
      }
    });

    test('a single participant gets the whole amount', () {
      expect(splitEqually(d('42.42'), 1), [d('42.42')]);
    });

    test('zero participants yields an empty list', () {
      expect(splitEqually(d('10'), 0), isEmpty);
    });
  });

  group('percentShare', () {
    test('simple percentage', () {
      expect(percentShare(d('100'), d('25')), d('25.00'));
    });

    test('rounds to whole cents, half-up', () {
      // 12.5% of 100.01 = 12.50125 -> 12.50
      expect(percentShare(d('100.01'), d('12.5')), d('12.50'));
    });

    test('0% and 100%', () {
      expect(percentShare(d('80'), d('0')), d('0.00'));
      expect(percentShare(d('80'), d('100')), d('80.00'));
    });
  });

  group('formatCurrency', () {
    test('defaults to CAD dollar formatting with 2 decimals', () {
      expect(formatCurrency(d('1234.5')), r'$1,234.50');
    });

    test('zero', () {
      expect(formatCurrency(Decimal.zero), r'$0.00');
    });

    test('negative', () {
      expect(formatCurrency(d('-5')), anyOf(r'-$5.00', r'($5.00)'));
    });
  });

  group('toDecimal', () {
    test('parses via string to preserve precision', () {
      expect(toDecimal(0.1), d('0.1'));
      expect(toDecimal(19.99), d('19.99'));
    });
  });
}
