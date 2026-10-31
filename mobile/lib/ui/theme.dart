import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;

/// Bộ màu của ứng dụng (xem mobile/DESIGN.md). Truy cập bằng `context.tokens`.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.bg,
    required this.surface,
    required this.text,
    required this.textSub,
    required this.textStrong,
    required this.line,
    required this.primary,
    required this.primaryPressed,
    required this.primaryTint,
    required this.ok,
    required this.okText,
    required this.okTint,
    required this.warn,
    required this.warnText,
    required this.warnTint,
    required this.bad,
    required this.badText,
    required this.badTint,
    required this.chevron,
    required this.tile,
    required this.segTrack,
  });

  final Color bg;
  final Color surface;
  final Color text;
  final Color textSub;
  final Color textStrong;
  final Color line;
  final Color primary;
  final Color primaryPressed;
  final Color primaryTint;
  final Color ok;
  final Color okText;
  final Color okTint;
  final Color warn;
  final Color warnText;
  final Color warnTint;
  final Color bad;
  final Color badText;
  final Color badTint;
  final Color chevron;
  final Color tile;
  final Color segTrack;

  /// Nền màn báo động (cố định cho cả hai chế độ).
  static const Color alarmBg = Color(0xFFB42318);

  static const light = AppTokens(
    bg: Color(0xFFF4F6FA),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF0E1525),
    textSub: Color(0xFF586174),
    textStrong: Color(0xFF33405A),
    line: Color(0xFFE7EAF0),
    primary: Color(0xFF1660D8),
    primaryPressed: Color(0xFF0F4FB8),
    primaryTint: Color(0xFFE4EEFD),
    ok: Color(0xFF16A34A),
    okText: Color(0xFF13804A),
    okTint: Color(0xFFE7F6EE),
    warn: Color(0xFFD97706),
    warnText: Color(0xFFB25E09),
    warnTint: Color(0xFFFFF3E0),
    bad: Color(0xFFC2281E),
    badText: Color(0xFFC2281E),
    badTint: Color(0xFFFDECEC),
    chevron: Color(0xFFA3ABBA),
    tile: Color(0xFFEEF2F8),
    segTrack: Color(0xFFE6EAF1),
  );

  static const dark = AppTokens(
    bg: Color(0xFF0B0F17),
    surface: Color(0xFF161B26),
    text: Color(0xFFE8ECF3),
    textSub: Color(0xFF9AA4B6),
    textStrong: Color(0xFFC3CBDA),
    line: Color(0xFF262D3B),
    primary: Color(0xFF5B9BF5),
    primaryPressed: Color(0xFF3F84E8),
    primaryTint: Color(0xFF1B2A44),
    ok: Color(0xFF34D27B),
    okText: Color(0xFF4ADE90),
    okTint: Color(0xFF14301F),
    warn: Color(0xFFF59E0B),
    warnText: Color(0xFFF5A83A),
    warnTint: Color(0xFF3A2A12),
    bad: Color(0xFFF2685E),
    badText: Color(0xFFF58278),
    badTint: Color(0xFF3B1B19),
    chevron: Color(0xFF677088),
    tile: Color(0xFF212838),
    segTrack: Color(0xFF212838),
  );

  @override
  AppTokens copyWith() => this;

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppTokens(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      text: l(text, other.text),
      textSub: l(textSub, other.textSub),
      textStrong: l(textStrong, other.textStrong),
      line: l(line, other.line),
      primary: l(primary, other.primary),
      primaryPressed: l(primaryPressed, other.primaryPressed),
      primaryTint: l(primaryTint, other.primaryTint),
      ok: l(ok, other.ok),
      okText: l(okText, other.okText),
      okTint: l(okTint, other.okTint),
      warn: l(warn, other.warn),
      warnText: l(warnText, other.warnText),
      warnTint: l(warnTint, other.warnTint),
      bad: l(bad, other.bad),
      badText: l(badText, other.badText),
      badTint: l(badTint, other.badTint),
      chevron: l(chevron, other.chevron),
      tile: l(tile, other.tile),
      segTrack: l(segTrack, other.segTrack),
    );
  }
}

extension AppTokensX on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppTokens>() ?? AppTokens.light;
}

/// Kiểu chữ dùng chung; luôn qua đây để đồng nhất cỡ chữ/độ đậm.
class AppText {
  const AppText._();

  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static const largeTitle = TextStyle(
      fontSize: 30, height: 36 / 30, fontWeight: FontWeight.w700, letterSpacing: -0.6);
  static const hero = TextStyle(
      fontSize: 28, height: 34 / 28, fontWeight: FontWeight.w700, letterSpacing: -0.56);
  static const section =
      TextStyle(fontSize: 13, height: 18 / 13, fontWeight: FontWeight.w600);
  static const rowTitle =
      TextStyle(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w600);
  static const rowSub = TextStyle(fontSize: 14, height: 20 / 14);
}

class AppTheme {
  const AppTheme._();

  static const String fontFamily = 'BeVietnamPro';

  static ThemeData get light => _build(AppTokens.light, Brightness.light);
  static ThemeData get dark => _build(AppTokens.dark, Brightness.dark);

  static ThemeData _build(AppTokens t, Brightness b) {
    final scheme = ColorScheme(
      brightness: b,
      primary: t.primary,
      onPrimary: b == Brightness.light ? Colors.white : const Color(0xFF0B0F17),
      secondary: t.primary,
      onSecondary: b == Brightness.light ? Colors.white : const Color(0xFF0B0F17),
      primaryContainer: t.primaryTint,
      onPrimaryContainer: t.primary,
      error: t.bad,
      onError: Colors.white,
      surface: t.surface,
      onSurface: t.text,
      onSurfaceVariant: t.textSub,
      outline: t.line,
      outlineVariant: t.line,
      surfaceContainerHighest: t.tile,
    );
    final radius12 = BorderRadius.circular(12);
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: radius12, borderSide: BorderSide(color: c, width: w));
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      fontFamily: fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.bg,
      canvasColor: t.bg,
      splashFactory: InkRipple.splashFactory,
      splashColor: t.primary.withValues(alpha: 0.06),
      highlightColor: t.primary.withValues(alpha: 0.05),
      extensions: [t],
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
      dividerTheme: DividerThemeData(color: t.line, thickness: 1, space: 1),
      textTheme: ThemeData(brightness: b, fontFamily: fontFamily).textTheme.apply(
            bodyColor: t.text,
            displayColor: t.text,
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: t.bg,
        foregroundColor: t.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontFamily: fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: s.contains(WidgetState.selected) ? t.primary : t.textSub,
            )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              size: 24,
              color: s.contains(WidgetState.selected) ? t.primary : t.textSub,
            )),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: t.line,
          disabledForegroundColor: t.textSub,
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(borderRadius: radius12),
          textStyle: const TextStyle(
              fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.primary,
          minimumSize: const Size(48, 48),
          side: BorderSide(color: t.line),
          shape: RoundedRectangleBorder(borderRadius: radius12),
          textStyle: const TextStyle(
              fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.primary,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: radius12),
          textStyle: const TextStyle(
              fontFamily: fontFamily, fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? t.primary
            : (b == Brightness.light ? const Color(0xFFD5DAE3) : const Color(0xFF3A4254))),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: TextStyle(color: t.textSub),
        hintStyle: TextStyle(color: t.chevron),
        border: border(t.line),
        enabledBorder: border(t.line),
        disabledBorder: border(t.line),
        focusedBorder: border(t.primary, 1.5),
        errorBorder: border(t.bad),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: b == Brightness.light ? const Color(0xFF1C2535) : const Color(0xFF2A3347),
        contentTextStyle: const TextStyle(
            fontFamily: fontFamily, fontSize: 14, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: radius12),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: t.primary),
    );
  }
}
