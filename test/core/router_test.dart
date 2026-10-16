import 'package:flutter_test/flutter_test.dart';
import 'package:tally/core/router.dart';

void main() {
  group('authRedirect', () {
    test('an invite link survives sign-in', () {
      final toLogin = authRedirect(false, Uri.parse('/join?code=AB12CD'))!;
      expect(toLogin, startsWith('/login?from='));
      expect(authRedirect(true, Uri.parse(toLogin)), '/join?code=AB12CD');
    });

    test('plain sign-in lands on /groups', () {
      expect(authRedirect(true, Uri.parse('/login')), '/groups');
    });

    test('ignores a from that leaves the app', () {
      for (final from in ['https://evil.test', '//evil.test', 'groups']) {
        final uri = Uri(path: '/login', queryParameters: {'from': from});
        expect(authRedirect(true, uri), '/groups', reason: from);
      }
    });

    test('no redirect when already where you belong', () {
      expect(authRedirect(true, Uri.parse('/groups')), isNull);
      expect(authRedirect(false, Uri.parse('/login')), isNull);
    });
  });
}
