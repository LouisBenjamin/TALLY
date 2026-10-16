import 'package:flutter/material.dart';

/// Spacing scale (4px grid). Use these instead of bare numbers in padding/gaps.
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// Corner radii. Generous on purpose: the app should feel friendly, not boxy.
abstract final class Radii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 20.0;
  static const xl = 28.0;
}

/// Tabular figures so amounts line up in lists and don't jitter as they change.
const kTabularFigures = [FontFeature.tabularFigures()];

/// Colours Material's ColorScheme has no slot for. Negative money uses
/// colorScheme.error; positive money ("you're owed") uses [positive].
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({required this.positive});

  final Color positive;

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  @override
  AppColors copyWith({Color? positive}) =>
      AppColors(positive: positive ?? this.positive);

  @override
  AppColors lerp(AppColors? other, double t) => other == null
      ? this
      : AppColors(positive: Color.lerp(positive, other.positive, t)!);
}

class AppTheme {
  static const _turquoise = Color(0xFF3EE0CF);

  // Every text/background pair below is checked to at least WCAG AA (4.5:1).
  static final dark = _build(
    ColorScheme.fromSeed(seedColor: _turquoise, brightness: Brightness.dark)
        .copyWith(
      primary: _turquoise,
      onPrimary: const Color(0xFF00201D),
      primaryContainer: const Color(0xFF0E3B37),
      onPrimaryContainer: const Color(0xFFA6F5EC),
      surface: const Color(0xFF0B0F0F),
      onSurface: const Color(0xFFE8F0EF),
      onSurfaceVariant: const Color(0xFFA1B2B0),
      surfaceContainerLowest: const Color(0xFF070A0A),
      surfaceContainerLow: const Color(0xFF101515),
      surfaceContainer: const Color(0xFF141A1A),
      surfaceContainerHigh: const Color(0xFF1B2222),
      surfaceContainerHighest: const Color(0xFF232B2B),
      outline: const Color(0xFF6B7C7A),
      outlineVariant: const Color(0xFF2B3535),
      error: const Color(0xFFFF8A80),
      onError: const Color(0xFF3B0907),
    ),
    const AppColors(positive: Color(0xFF5EE39A)),
  );

  static final light = _build(
    ColorScheme.fromSeed(seedColor: _turquoise).copyWith(
      primary: const Color(0xFF0A7F75),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFB9F2EA),
      onPrimaryContainer: const Color(0xFF00332E),
      surface: const Color(0xFFF6FAF9),
      onSurface: const Color(0xFF0E1514),
      onSurfaceVariant: const Color(0xFF4A5B59),
      error: const Color(0xFFBA1A1A),
    ),
    const AppColors(positive: Color(0xFF0F6E33)),
  );

  static ThemeData _build(ColorScheme cs, AppColors app) {
    final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(999));
    const buttonSize = Size(64, 48); // 48px keeps touch targets comfortable.
    // Component textStyles don't inherit ThemeData.fontFamily, so name it.
    const buttonText = TextStyle(
      fontFamily: 'PlusJakartaSans',
      fontWeight: FontWeight.w700,
      fontSize: 15,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      fontFamily: 'PlusJakartaSans',
      scaffoldBackgroundColor: cs.surface,
      extensions: [app],
      // Stronger than Material's default so keyboard focus is easy to spot.
      focusColor: cs.primary.withValues(alpha: 0.24),
      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'PlusJakartaSans',
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: cs.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: cs.surfaceContainer,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
          side: BorderSide(color: cs.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          shape: pill,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          shape: pill,
          textStyle: buttonText,
          side: BorderSide(color: cs.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: buttonSize,
          shape: pill,
          textStyle: buttonText,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        highlightElevation: 0,
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        shape: pill,
        extendedTextStyle: buttonText,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.xl),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: cs.outlineVariant,
        labelStyle: const TextStyle(
          fontFamily: 'PlusJakartaSans',
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerTheme: DividerThemeData(color: cs.outlineVariant, space: 1),
    );
  }
}
