import 'package:decimal/decimal.dart';
import 'package:tally/core/theme.dart';
import 'package:tally/features/activity/activity_provider.dart';
import 'package:tally/features/balances/ui/balances_tab.dart';
import 'package:tally/features/balances/logic/settle.dart';
import 'package:tally/features/balances/providers/balances_provider.dart';
import 'package:tally/features/expenses/providers/categories_provider.dart';
import 'package:tally/features/expenses/providers/expenses_provider.dart';
import 'package:tally/features/expenses/ui/add_expense_screen.dart';
import 'package:tally/features/groups/providers/groups_provider.dart';
import 'package:tally/features/groups/ui/group_detail_screen.dart';
import 'package:tally/features/import/providers/import_providers.dart';
import 'package:tally/features/insights/data/insights_repository.dart';
import 'package:tally/features/insights/logic/insights_range.dart';
import 'package:tally/features/insights/providers/insights_provider.dart';
import 'package:tally/features/insights/ui/insights_screen.dart';
import 'package:tally/features/realtime/group_realtime_provider.dart';
import 'package:tally/features/recurring/providers/recurring_provider.dart';
import 'package:tally/features/recurring/ui/recurring_list_screen.dart';
import 'package:tally/models/activity_entry.dart';
import 'package:tally/models/category.dart';
import 'package:tally/models/expense.dart';
import 'package:tally/models/group.dart';
import 'package:tally/models/group_member.dart';
import 'package:tally/models/member_balance.dart';
import 'package:tally/models/recurring_expense.dart';
import 'package:tally/models/settlement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_supabase.dart';

Decimal dec(String s) => Decimal.parse(s);

const _gid = 'g1';

final _group = Group(
  id: _gid,
  name: 'Apartment',
  joinCode: 'AB452A',
  createdBy: 'u1',
  createdAt: DateTime(2026, 8, 1),
);

final _members = [
  GroupMember(
    id: 'm1',
    groupId: _gid,
    userId: 'u1',
    displayName: 'Ben',
    role: 'owner',
    joinedAt: DateTime(2026, 8, 1),
  ),
  GroupMember(
    id: 'm2',
    groupId: _gid,
    userId: null,
    displayName: 'Sam',
    role: 'member',
    joinedAt: DateTime(2026, 8, 2),
  ),
];

final _expenses = [
  Expense(
    id: 'e1',
    groupId: _gid,
    payerMemberId: 'm1',
    amount: dec('90.00'),
    currency: 'CAD',
    description: 'Groceries',
    occurredOn: DateTime(2026, 8, 12),
    splitType: 'equal',
    createdBy: 'u1',
    createdAt: DateTime(2026, 8, 12),
  ),
];

final _balances = [
  MemberBalance(memberId: 'm1', net: Decimal.zero),
  MemberBalance(memberId: 'm2', net: Decimal.zero),
];

Widget _host(Widget child, List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(theme: AppTheme.light, home: child),
  );
}

void _desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1.0;
}

void main() {
  setUpAll(initTestSupabase);

  testWidgets('InsightsScreen renders a category breakdown', (tester) async {
    _desktop(tester);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(
      const InsightsScreen(groupId: _gid),
      [
        insightsProvider((groupId: _gid, range: InsightsRange.monthToDate))
            .overrideWith((ref) async => [
                  CategorySpend(name: 'Rent', icon: 'home', total: dec('1000')),
                  CategorySpend(
                      name: 'Groceries',
                      icon: 'shopping_cart',
                      total: dec('250')),
                ]),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('InsightsScreen switches the range via the dropdown',
      (tester) async {
    _desktop(tester);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(
      const InsightsScreen(groupId: _gid),
      [
        insightsProvider((groupId: _gid, range: InsightsRange.monthToDate))
            .overrideWith((ref) async =>
                [CategorySpend(name: 'Rent', icon: 'home', total: dec('1000'))]),
        insightsProvider((groupId: _gid, range: InsightsRange.yearToDate))
            .overrideWith((ref) async => [
                  CategorySpend(
                      name: 'Flights', icon: 'flight', total: dec('4200')),
                ]),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('Rent'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<InsightsRange>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year to date').last);
    await tester.pumpAndSettle();

    expect(find.text('Flights'), findsOneWidget);
    expect(find.text('Rent'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('InsightsScreen shows an empty message with no spend',
      (tester) async {
    _desktop(tester);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(
      const InsightsScreen(groupId: _gid),
      [
        insightsProvider((groupId: _gid, range: InsightsRange.monthToDate))
            .overrideWith((ref) async => <CategorySpend>[]),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('No spending'), findsOneWidget);
  });

  testWidgets('RecurringListScreen renders templates with cadence',
      (tester) async {
    _desktop(tester);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(
      const RecurringListScreen(groupId: _gid),
      [
        membersProvider(_gid).overrideWith((ref) async => _members),
        recurringProvider(_gid).overrideWith((ref) async => [
              RecurringExpense(
                id: 'r1',
                groupId: _gid,
                payerMemberId: 'm1',
                amount: dec('1000'),
                currency: 'CAD',
                description: 'Rent',
                splitType: 'equal',
                frequency: 'monthly',
                intervalCount: 1,
                nextOccurrence: DateTime(2026, 10, 1),
                active: true,
              ),
            ]),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('Rent'), findsOneWidget);
    expect(find.textContaining('Every month'), findsOneWidget);
  });

  testWidgets('RecurringListScreen shows its empty state', (tester) async {
    _desktop(tester);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(
      const RecurringListScreen(groupId: _gid),
      [
        membersProvider(_gid).overrideWith((ref) async => _members),
        recurringProvider(_gid)
            .overrideWith((ref) async => <RecurringExpense>[]),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('No recurring expenses'), findsOneWidget);
  });

  testWidgets('AddExpenseScreen builds the new-expense form', (tester) async {
    _desktop(tester);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(
      const AddExpenseScreen(groupId: _gid),
      [
        membersProvider(_gid).overrideWith((ref) async => _members),
        categoriesProvider(_gid).overrideWith((ref) async => [
              const Category(id: 'c1', name: 'Food', icon: 'fork-knife'),
            ]),
        merchantRulesProvider(_gid).overrideWith((ref) async => []),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('Add expense'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    // Split type selector + a participant row per member.
    expect(find.text('Equally'), findsOneWidget);
    expect(find.text('Ben'), findsWidgets);
    expect(find.text('Sam'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('GroupDetailScreen renders its five tabs', (tester) async {
    _desktop(tester);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(
      const GroupDetailScreen(groupId: _gid),
      [
        groupProvider(_gid).overrideWith((ref) async => _group),
        membersProvider(_gid).overrideWith((ref) async => _members),
        expensesProvider(_gid).overrideWith((ref) async => _expenses),
        balancesProvider(_gid).overrideWith((ref) async => _balances),
        settlementsProvider(_gid).overrideWith((ref) async => [
              Settlement(
                id: 's1',
                fromMemberId: 'm2',
                toMemberId: 'm1',
                amount: dec('45.00'),
                occurredOn: DateTime(2026, 8, 20),
              ),
            ]),
        activityProvider(_gid).overrideWith((ref) async => [
              ActivityEntry(
                id: 'a1',
                summary: 'Ben added "Groceries"',
                amount: dec('90.00'),
                createdAt: DateTime.utc(2026, 8, 12, 18),
              ),
            ]),
        groupRealtimeProvider(_gid).overrideWithValue(null),
        categoriesProvider(_gid).overrideWith((ref) async => const [
              Category(id: 'c1', name: 'Food', icon: 'fork-knife'),
            ]),
        merchantRulesProvider(_gid).overrideWith((ref) async => []),
      ],
    ));
    await tester.pumpAndSettle();
    expect(find.text('Apartment'), findsOneWidget);
    expect(find.text('Expenses'), findsOneWidget);
    expect(find.text('Balances'), findsOneWidget);
    expect(find.text('Members'), findsOneWidget);
    expect(find.text('Labels'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);

    // Import is an app-bar action rather than its own tab, deliberately: the
    // tab count above is what this test exists to pin.
    expect(find.byTooltip('Import statement'), findsOneWidget);

    await tester.tap(find.text('Balances'));
    await tester.pumpAndSettle();
    expect(find.text('All settled up'), findsOneWidget);
    expect(find.text('Sam paid Ben'), findsOneWidget);
    expect(find.text('Record a payment'), findsOneWidget);

    await tester.tap(find.text('Members'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Members ('), findsOneWidget);
    expect(find.text('AB452A'), findsOneWidget);
    // Sam can be removed; Ben is the owner, so he deletes the group instead.
    expect(find.text('Remove'), findsOneWidget);

    await tester.tap(find.text('Labels'));
    await tester.pumpAndSettle();
    expect(find.text('Food'), findsOneWidget);

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Ben added "Groceries"'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PaymentDialog prefills a suggestion and validates', (tester) async {
    _desktop(tester);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(
      Scaffold(
        body: PaymentDialog(
          groupId: _gid,
          members: _members,
          suggested: DebtTransfer(
              fromMemberId: 'm2', toMemberId: 'm1', amount: dec('30.50')),
        ),
      ),
      const [],
    ));
    await tester.pumpAndSettle();
    FilledButton save() => tester.widget(find.widgetWithText(FilledButton, 'Save'));

    expect(find.text('30.50'), findsOneWidget);
    expect(save().onPressed, isNotNull);

    // A partial payment is just a smaller amount.
    await tester.enterText(find.byType(TextField), '10');
    await tester.pump();
    expect(save().onPressed, isNotNull);

    await tester.enterText(find.byType(TextField), '0');
    await tester.pump();
    expect(save().onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
