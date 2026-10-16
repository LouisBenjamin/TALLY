import 'package:tally/core/supabase_client.dart';
import 'package:tally/features/auth/ui/login_screen.dart';
import 'package:tally/features/expenses/ui/add_expense_screen.dart';
import 'package:tally/features/groups/ui/group_detail_screen.dart';
import 'package:tally/features/groups/ui/group_settings_screen.dart';
import 'package:tally/features/groups/ui/groups_list_screen.dart';
import 'package:tally/features/groups/ui/join_by_link_screen.dart';
import 'package:tally/features/import/ui/import_screen.dart';
import 'package:tally/features/insights/ui/insights_screen.dart';
import 'package:tally/features/labels/ui/labels_screen.dart';
import 'package:tally/features/recurring/ui/add_recurring_screen.dart';
import 'package:tally/features/recurring/ui/recurring_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthNotifier();
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: notifier,
    redirect: (context, state) =>
        authRedirect(supabase.auth.currentSession != null, state.uri),
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      // Invite deep link: /join?code=XXXXXX. Auth redirect runs first, so the
      // user is always signed in by the time this builds.
      GoRoute(
        path: '/join',
        builder: (_, state) =>
            JoinByLinkScreen(code: state.uri.queryParameters['code']),
      ),
      GoRoute(
        path: '/groups',
        builder: (_, __) => const GroupsListScreen(),
        routes: [
          GoRoute(
            path: ':groupId',
            builder: (_, state) => GroupDetailScreen(
              groupId: state.pathParameters['groupId']!,
            ),
            routes: [
              GoRoute(
                path: 'expenses/new',
                builder: (_, state) => AddExpenseScreen(
                  groupId: state.pathParameters['groupId']!,
                ),
              ),
              GoRoute(
                path: 'expenses/:expenseId/edit',
                builder: (_, state) => AddExpenseScreen(
                  groupId: state.pathParameters['groupId']!,
                  expenseId: state.pathParameters['expenseId'],
                ),
              ),
              GoRoute(
                path: 'insights',
                builder: (_, state) => InsightsScreen(
                  groupId: state.pathParameters['groupId']!,
                ),
              ),
              GoRoute(
                path: 'settings',
                builder: (_, state) => GroupSettingsScreen(
                  groupId: state.pathParameters['groupId']!,
                ),
              ),
              GoRoute(
                path: 'recurring',
                builder: (_, state) => RecurringListScreen(
                  groupId: state.pathParameters['groupId']!,
                ),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (_, state) => AddRecurringScreen(
                      groupId: state.pathParameters['groupId']!,
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'import',
                builder: (_, state) => ImportScreen(
                  groupId: state.pathParameters['groupId']!,
                ),
                routes: [
                  // Rules became tags and moved onto the Labels tab; keep the
                  // old path alive as a redirect for anyone with it bookmarked.
                  GoRoute(
                    path: 'rules',
                    redirect: (_, state) =>
                        '/groups/${state.pathParameters['groupId']}/labels',
                  ),
                ],
              ),
              GoRoute(
                path: 'labels',
                builder: (_, state) => LabelsScreen(
                  groupId: state.pathParameters['groupId']!,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

// Signed-out users go to /login carrying where they were headed (?from=), so an
// invite link like /join?code=X survives sign-in instead of landing on /groups.
String? authRedirect(bool isLoggedIn, Uri uri) {
  final isGoingToLogin = uri.path == '/login';
  if (!isLoggedIn && !isGoingToLogin) {
    return Uri(path: '/login', queryParameters: {'from': uri.toString()})
        .toString();
  }
  if (isLoggedIn && isGoingToLogin) {
    final from = uri.queryParameters['from'];
    // Only in-app paths: '//host' would be read as another origin.
    final safe = from != null && from.startsWith('/') && !from.startsWith('//');
    return safe ? from : '/groups';
  }
  return null;
}

// Bridges Supabase auth state changes into GoRouter's Listenable interface.
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier() {
    _sub = supabase.auth.onAuthStateChange.listen((_) => notifyListeners());
  }

  late final dynamic _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
