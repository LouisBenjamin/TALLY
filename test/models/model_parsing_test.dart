import 'package:decimal/decimal.dart';
import 'package:tally/models/activity_entry.dart';
import 'package:tally/models/expense.dart';
import 'package:tally/models/expense_split.dart';
import 'package:tally/models/group.dart';
import 'package:tally/models/group_member.dart';
import 'package:tally/models/import_result.dart';
import 'package:tally/models/member_balance.dart';
import 'package:tally/models/merchant_rule.dart';
import 'package:tally/models/recurring_expense.dart';
import 'package:tally/models/settlement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Expense.fromJson', () {
    test('parses a numeric amount arriving as a String without precision loss',
        () {
      final e = Expense.fromJson({
        'id': 'e1',
        'group_id': 'g1',
        'payer_member_id': 'm1',
        'amount': '19.99',
        'currency': 'CAD',
        'category_id': null,
        'description': 'Dinner',
        'occurred_on': '2026-08-15',
        'split_type': 'equal',
        'created_by': 'u1',
        'created_at': '2026-08-15T12:00:00Z',
      });
      expect(e.amount, Decimal.parse('19.99'));
      expect(e.categoryId, isNull);
      expect(e.occurredOn, DateTime(2026, 8, 15));
    });

    test('parses a numeric amount arriving as a num', () {
      final e = Expense.fromJson({
        'id': 'e1',
        'group_id': 'g1',
        'payer_member_id': 'm1',
        'amount': 20,
        'currency': 'CAD',
        'description': '',
        'occurred_on': '2026-08-15',
        'split_type': 'exact',
        'created_by': 'u1',
        'created_at': '2026-08-15T12:00:00Z',
      });
      expect(e.amount, Decimal.parse('20'));
    });
  });

  group('GroupMember.fromJson', () {
    test('real user takes display_name from the joined profiles row', () {
      final m = GroupMember.fromJson({
        'id': 'm1',
        'group_id': 'g1',
        'user_id': 'u1',
        'role': 'owner',
        'joined_at': '2026-08-01T00:00:00Z',
        'profiles': {'display_name': 'Ben'},
      });
      expect(m.isGuest, isFalse);
      expect(m.displayName, 'Ben');
    });

    test('real user with a missing profile falls back to "User"', () {
      final m = GroupMember.fromJson({
        'id': 'm1',
        'group_id': 'g1',
        'user_id': 'u1',
        'role': 'member',
        'joined_at': '2026-08-01T00:00:00Z',
        'profiles': null,
      });
      expect(m.displayName, 'User');
    });

    test('guest takes display_name straight off the row', () {
      final m = GroupMember.fromJson({
        'id': 'm2',
        'group_id': 'g1',
        'user_id': null,
        'display_name': 'Sam',
        'role': 'member',
        'joined_at': '2026-08-01T00:00:00Z',
      });
      expect(m.isGuest, isTrue);
      expect(m.displayName, 'Sam');
    });
  });

  group('MemberBalance.fromJson', () {
    test('null net becomes zero', () {
      final b = MemberBalance.fromJson({'member_id': 'm1', 'net': null});
      expect(b.net, Decimal.zero);
    });

    test('string net parses', () {
      final b = MemberBalance.fromJson({'member_id': 'm1', 'net': '-12.34'});
      expect(b.net, Decimal.parse('-12.34'));
    });
  });

  group('ExpenseSplit.fromJson', () {
    test('percent split carries share_percent', () {
      final s = ExpenseSplit.fromJson({
        'member_id': 'm1',
        'share_amount': '45.00',
        'share_percent': '50',
      });
      expect(s.shareAmount, Decimal.parse('45.00'));
      expect(s.sharePercent, Decimal.parse('50'));
    });

    test('non-percent split has a null share_percent', () {
      final s = ExpenseSplit.fromJson({
        'member_id': 'm1',
        'share_amount': '45.00',
        'share_percent': null,
      });
      expect(s.sharePercent, isNull);
    });
  });

  group('Group.fromJson', () {
    test('maps join_code and created_by', () {
      final g = Group.fromJson({
        'id': 'g1',
        'name': 'Apartment',
        'join_code': 'AB452A',
        'created_by': 'u1',
        'created_at': '2026-08-01T00:00:00Z',
      });
      expect(g.joinCode, 'AB452A');
      expect(g.createdBy, 'u1');
    });
  });

  group('RecurringExpense', () {
    RecurringExpense make(String freq, int interval) => RecurringExpense.fromJson({
          'id': 'r1',
          'group_id': 'g1',
          'payer_member_id': 'm1',
          'amount': '1000',
          'currency': 'CAD',
          'description': 'Rent',
          'split_type': 'equal',
          'frequency': freq,
          'interval_count': interval,
          'next_occurrence': '2026-10-01',
          'active': true,
        });

    test('cadence: singular for interval 1', () {
      expect(make('daily', 1).cadence, 'Every day');
      expect(make('weekly', 1).cadence, 'Every week');
      expect(make('monthly', 1).cadence, 'Every month');
    });

    test('cadence: plural for interval > 1', () {
      expect(make('weekly', 2).cadence, 'Every 2 weeks');
      expect(make('monthly', 3).cadence, 'Every 3 months');
    });

    test('unknown frequency defaults to months', () {
      expect(make('yearly', 1).cadence, 'Every month');
    });
  });

  group('MerchantRule.fromJson', () {
    test('parses a full row', () {
      final rule = MerchantRule.fromJson({
        'id': 'r1',
        'group_id': 'g1',
        'pattern': 'COSTCO WHOLESALE',
        'match_type': 'contains',
        'action': 'share',
        'priority': 10,
        'category_id': 'c1',
      });
      expect(rule.pattern, 'COSTCO WHOLESALE');
      expect(rule.matchType, 'contains');
      expect(rule.priority, 10);
      expect(rule.categoryId, 'c1');
      expect(rule.isSkip, isFalse);
    });

    test('a skip rule with no category', () {
      final rule = MerchantRule.fromJson({
        'id': 'r2',
        'group_id': 'g1',
        'pattern': 'SILVER GOBLIN',
        'match_type': 'contains',
        'action': 'skip',
        'priority': 100,
        'category_id': null,
      });
      expect(rule.isSkip, isTrue);
      expect(rule.categoryId, isNull);
    });

    test('falls back to defaults on missing optional columns', () {
      final rule = MerchantRule.fromJson({
        'id': 'r3',
        'group_id': 'g1',
        'pattern': 'COSTCO',
      });
      expect(rule.matchType, 'contains');
      expect(rule.action, 'share');
      expect(rule.priority, 100);
    });
  });

  group('ImportResult.fromJson', () {
    test('parses the RPC payload', () {
      final result = ImportResult.fromJson({
        'inserted': 12,
        'skipped': 3,
        'skipped_fingerprints': ['aa', 'bb', 'cc'],
      });
      expect(result.inserted, 12);
      expect(result.skipped, 3);
      expect(result.skippedFingerprints, ['aa', 'bb', 'cc']);
      expect(result.summary, 'Imported 12 · 3 already existed');
    });

    // Postgres renders an empty text[] as [], but be defensive about nulls.
    test('handles an empty skip list', () {
      final result = ImportResult.fromJson({
        'inserted': 4,
        'skipped': 0,
        'skipped_fingerprints': <String>[],
      });
      expect(result.skippedFingerprints, isEmpty);
      expect(result.summary, 'Imported 4');
    });
  });

  group('Settlement.fromJson', () {
    test('parses members, amount and date', () {
      final s = Settlement.fromJson({
        'id': 's1',
        'group_id': 'g1',
        'from_member': 'm2',
        'to_member': 'm1',
        'amount': 12.5,
        'occurred_on': '2026-10-01',
      });
      expect(s.fromMemberId, 'm2');
      expect(s.toMemberId, 'm1');
      expect(s.amount, Decimal.parse('12.5'));
      expect(s.occurredOn, DateTime(2026, 10, 1));
    });
  });

  group('ActivityEntry.fromJson', () {
    test('amount is optional', () {
      final a = ActivityEntry.fromJson({
        'id': 'a1',
        'summary': 'Sam joined the group',
        'amount': null,
        'created_at': '2026-10-01T12:00:00Z',
      });
      expect(a.amount, isNull);
      expect(a.summary, 'Sam joined the group');
    });
  });
}
