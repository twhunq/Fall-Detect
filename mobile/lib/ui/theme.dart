import 'package:flutter/material.dart';

/// Mau trang thai (ok/canh bao/nguy hiem/tat tieng) cho widget tuy chinh.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.ok,
    required this.warn,
    required this.bad,
    required this.muted,
  });

  final Color ok;
  final Color warn;
  final Color bad;
  final Color muted;

  static const light = StatusColors(
    ok: Color(0xFF16A34A),
    warn: Color(0xFFD97706),
    bad: Color(0xFFDC2626),
    muted: Color(0xFF6B7280),
  );

  static const dark = StatusColors(
    ok: Color(0xFF22C55E),
    warn: Color(0xFFF59E0B),
    bad: Color(0xFFF87171),
    muted: Color(0xFF9CA3AF),
  );

  @override
  StatusColors copyWith({Color? ok, Color? warn, Color? bad, Color? muted}) =>
      StatusColors(
        ok: ok ?? this.ok,
        warn: warn ?? this.warn,
        bad: bad ?? this.bad,
        muted: muted ?? this.muted,
      );

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      ok: Color.lerp(ok, other.ok, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      bad: Color.lerp(bad, other.bad, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
    );
  }
}

extension StatusColorsX on BuildContext {
  StatusColors get statusColors =>
      Theme.of(this).extension<StatusColors>() ?? StatusColors.light;
}

class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(
        const ColorScheme(
          brightness: Brightness.light,
          primary: Color(0xFF2563EB),
          onPrimary: Colors.white,
          secondary: Color(0xFF2563EB),
          onSecondary: Colors.white,
          error: Color(0xFFDC2626),
          onError: Colors.white,
          surface: Color(0xFFFFFFFF),
          onSurface: Color(0xFF111827),
          onSurfaceVariant: Color(0xFF6B7280),
          outline: Color(0xFFE5E7EB),
          outlineVariant: Color(0xFFE5E7EB),
        ),
        bg: const Color(0xFFF3F4F6),
        status: StatusColors.light,
      );

  static ThemeData get dark => _build(
        const ColorScheme(
          brightness: Brightness.dark,
          primary: Color(0xFF60A5FA),
          onPrimary: Color(0xFF0F1115),
          secondary: Color(0xFF60A5FA),
          onSecondary: Color(0xFF0F1115),
          error: Color(0xFFF87171),
          onError: Color(0xFF0F1115),
          surface: Color(0xFF181B21),
          onSurface: Color(0xFFE5E7EB),
          onSurfaceVariant: Color(0xFF9CA3AF),
          outline: Color(0xFF2A2F38),
          outlineVariant: Color(0xFF2A2F38),
        ),
        bg: const Color(0xFF0F1115),
        status: StatusColors.dark,
      );

  static ThemeData _build(
    ColorScheme scheme, {
    required Color bg,
    required StatusColors status,
  }) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      extensions: [status],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outline),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outline, space: 1),
    );
  }
}
