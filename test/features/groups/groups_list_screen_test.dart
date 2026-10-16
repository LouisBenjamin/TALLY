import 'package:tally/core/theme.dart';
import 'package:tally/features/groups/providers/groups_provider.dart';
import 'package:tally/features/groups/ui/groups_list_screen.dart';
import 'package:tally/models/group_summary.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

GroupSummary s(String id, String name, {String net = '0'}) => GroupSummary(
      id: id,
      name: name,
      joinCode: 'CODE$id',
      photoUrl: null, // avoid Image.network in widget tests
      myMemberId: 'm$id',
      myNet: Decimal.parse(net),
    );

Future<void> pumpAt(
  WidgetTester tester,
  Size size, {
  required List<GroupSummary> groups,
  Object? error,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        groupSummariesProvider.overrideWith((ref) async {
          if (error != null) throw error;
          return groups;
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const GroupsListScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final groups = [for (var i = 0; i < 6; i++) s('$i', 'Group $i')];

  testWidgets('groups render as a square-tile grid', (tester) async {
    await pumpAt(tester, const Size(375, 900), groups: groups);
    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent;
    expect(delegate.childAspectRatio, 1);
  });

  testWidgets('empty state shown when there are no groups', (tester) async {
    await pumpAt(tester, const Size(1440, 900), groups: const []);
    expect(find.text('No groups yet'), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
  });

  testWidgets('every group card is rendered', (tester) async {
    await pumpAt(tester, const Size(1200, 2000), groups: groups);
    expect(find.text('Group 0'), findsOneWidget);
    expect(find.text('Group 5'), findsOneWidget);
  });

  testWidgets('status line reflects who owes what', (tester) async {
    await pumpAt(
      tester,
      const Size(1200, 2000),
      groups: [
        s('a', 'Owed to me', net: '25.00'),
        s('b', 'I owe', net: '-10.50'),
        s('c', 'Even', net: '0'),
      ],
    );
    expect(find.textContaining("You're owed"), findsOneWidget);
    expect(find.textContaining('You owe'), findsOneWidget);
    expect(find.text('Settled up'), findsOneWidget);
  });

  testWidgets('a failed load shows a friendly error with retry',
      (tester) async {
    await pumpAt(tester, const Size(375, 900),
        groups: const [], error: Exception('PostgrestException(boom)'));
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('PostgrestException'), findsNothing);
  });

  testWidgets('empty state offers create and join', (tester) async {
    await pumpAt(tester, const Size(375, 900), groups: const []);
    expect(find.text('Create a group'), findsOneWidget);
    expect(find.text('Join with a code'), findsOneWidget);
  });
}
