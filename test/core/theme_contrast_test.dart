import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tally/core/theme.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final (name, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark)]) {
    test('$name theme text pairs meet WCAG AA (4.5:1)', () {
      final cs = theme.colorScheme;
      final positive = theme.extension<AppColors>()!.positive;
      final pairs = {
        'onSurface/surface': (cs.onSurface, cs.surface),
        'onSurfaceVariant/surface': (cs.onSurfaceVariant, cs.surface),
        'onSurfaceVariant/card': (cs.onSurfaceVariant, cs.surfaceContainer),
        'primary/surface': (cs.primary, cs.surface),
        'onPrimary/primary': (cs.onPrimary, cs.primary),
        'onPrimaryContainer/primaryContainer':
            (cs.onPrimaryContainer, cs.primaryContainer),
        'positive/card': (positive, cs.surfaceContainer),
        'error/card': (cs.error, cs.surfaceContainer),
        'onSurface/dialog': (cs.onSurface, cs.surfaceContainerHigh),
      };
      pairs.forEach((label, p) {
        expect(contrast(p.$1, p.$2), greaterThanOrEqualTo(4.5), reason: label);
      });
    });
  }
}
