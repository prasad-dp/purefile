import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

/// PureFile design tokens. F19b: the layer above the locked teal palette is
/// crafted in the iOS design language — grouped inset surfaces, hairline
/// separators, SF-style type tracking, soft depth, unhurried motion.
abstract final class PfColors {
  // Brand — Pure Teal (locked).
  static const Color primaryLight = Color(0xFF0F766E);
  static const Color primaryDark = Color(0xFF5EEAD4);
  static const Color onPrimaryDark = Color(0xFF042F2E);
  static const Color primaryContainerLight = Color(0xFFCCFBF1);
  static const Color primaryContainerDark = Color(0xFF134E4A);
  static const Color onPrimaryContainerLight = Color(0xFF042F2E);
  static const Color onPrimaryContainerDark = Color(0xFFCCFBF1);

  /// Brand gradient (icon, headers, hero): teal → sky.
  static const List<Color> brandGradient = [
    Color(0xFF0F766E),
    Color(0xFF0284C7)
  ];

  // Tool category colors (locked).
  static const Color categoryPdf = Color(0xFFE11D48);
  static const Color categoryImage = Color(0xFF7C3AED);
  static const Color categoryZip = Color(0xFFD97706);
  static const Color categoryScan = Color(0xFF059669);
  static const Color categoryOcr = Color(0xFF2563EB);
  static const Color categorySign = Color(0xFFDB2777);
  static const Color categoryVault = Color(0xFF475569);

  // Semantic.
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFDC2626);
  static const Color info = Color(0xFF0284C7);

  // iOS-grouped surfaces (F19b): systemGroupedBackground + secondary.
  static const Color surfaceLight = Color(0xFFF2F2F7);
  static const Color surfaceDark = Color(0xFF000000);
  static const Color cardLight = Colors.white;
  static const Color cardDark = Color(0xFF1C1C1E);
  static const Color separatorLight = Color(0x1F000000);
  static const Color separatorDark = Color(0x33FFFFFF);

  /// The signature brand gradient — teal → sky.
  static LinearGradient get heroGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: brandGradient,
      );

  /// Hairline divider color for grouped lists.
  static Color separator(bool isDark) =>
      isDark ? separatorDark : separatorLight;
}

/// Shared motion tokens: one curve family + durations so the whole app moves
/// identically — quick enough to feel responsive, soft landings everywhere.
abstract final class PfMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 380);
  static const Curve ease = Curves.easeOutCubic;
  static const Curve spring = Curves.easeOutBack;
}

/// Haptic helpers: light, consistent feedback. Exception-safe — missing
/// platform channels (tests, desktop) never throw.
abstract final class PfHaptics {
  static void tap() => _safe(() => HapticFeedback.selectionClick());
  static void success() => _safe(() => HapticFeedback.mediumImpact());
  static void warning() => _safe(() => HapticFeedback.heavyImpact());

  static void _safe(VoidCallback fn) {
    try {
      fn();
    } catch (_) {}
  }
}

/// SF-style type treatment: display-grade tracking on big titles, tight
/// leading, weight-first hierarchy (iOS type scale flavor).
TextTheme _pfTextTheme(TextTheme base, Color onSurface) => base.copyWith(
      headlineMedium: base.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800, letterSpacing: -0.8, color: onSurface),
      headlineSmall: base.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700, letterSpacing: -0.5, color: onSurface),
      titleLarge: base.titleLarge?.copyWith(
          fontWeight: FontWeight.w700, letterSpacing: -0.4, color: onSurface),
      titleMedium: base.titleMedium?.copyWith(
          fontWeight: FontWeight.w600, letterSpacing: -0.2, color: onSurface),
      titleSmall: base.titleSmall?.copyWith(
          fontWeight: FontWeight.w600, letterSpacing: -0.1, color: onSurface),
    );

/// Material 3 theme wearing iOS clothes: grouped surfaces, soft cards,
/// crafted dialogs and sheets, unified motion.
abstract final class PfTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: PfColors.primaryLight,
      brightness: brightness,
      primary: isLight ? PfColors.primaryLight : PfColors.primaryDark,
      onPrimary: isLight ? Colors.white : PfColors.onPrimaryDark,
      primaryContainer: isLight
          ? PfColors.primaryContainerLight
          : PfColors.primaryContainerDark,
      onPrimaryContainer: isLight
          ? PfColors.onPrimaryContainerLight
          : PfColors.onPrimaryContainerDark,
      error: PfColors.error,
      secondaryContainer: isLight
          ? const Color(0xFFE0F2F1)
          : const Color(0xFF0E3B37),
      surfaceContainerHighest:
          isLight ? const Color(0xFFE5E5EA) : const Color(0xFF2C2C2E),
    );

    final radius = BorderRadius.circular(20);
    final chipRadius = BorderRadius.circular(12);
    final onSurface = scheme.onSurface;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          isLight ? PfColors.surfaceLight : PfColors.surfaceDark,
      textTheme: _pfTextScheme(isLight),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: isLight ? PfColors.cardLight : PfColors.cardDark,
        shape: RoundedRectangleBorder(borderRadius: radius),
        // iOS cards float by light, not by border hairlines — a whisper of
        // shadow only in light mode (dark cards read via their fill).
        shadowColor: Colors.black.withValues(alpha: isLight ? 0.06 : 0.0),
      ),
      dividerTheme: DividerThemeData(
        color: PfColors.separator(isLight),
        thickness: 0.5,
        space: 0.5,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: onSurface,
        ),
        iconTheme: IconThemeData(color: scheme.primary),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isLight ? PfColors.cardLight : PfColors.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: onSurface,
        ),
        contentTextStyle: TextStyle(
          fontSize: 14,
          height: 1.35,
          color: scheme.onSurfaceVariant,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          minimumSize: const Size(0, 50),
          elevation: 0,
          textStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          minimumSize: const Size(0, 50),
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.35)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor:
            isLight ? const Color(0xFFE9E9EE) : const Color(0xFF1C1C1E),
        border: OutlineInputBorder(
            borderRadius: chipRadius, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: chipRadius, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: chipRadius,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      progressIndicatorTheme:
          ProgressIndicatorThemeData(color: scheme.primary),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: chipRadius),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : (isLight ? Colors.white : const Color(0xFF8E8E93)),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (isLight ? PfColors.success : PfColors.primaryDark)
              : (isLight ? const Color(0xFFD1D1D6) : const Color(0xFF39393D)),
        ),
      ),
      splashFactory: NoSplash.splashFactory,
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Applies the SF-style tracking to both brightnesses' base type.
  static TextTheme _pfTextScheme(bool isLight) {
    final base = isLight
        ? Typography.material2014().black
        : Typography.material2014().white;
    return _pfTextTheme(base, isLight ? const Color(0xFF0B0B0F) : Colors.white);
  }
}
