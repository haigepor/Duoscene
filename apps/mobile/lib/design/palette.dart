import 'package:flutter/material.dart';

/// 语义色与背景材质随 Theme 变化；媒体覆盖层始终使用独立的白色前景。
@immutable
class DSPalette extends ThemeExtension<DSPalette> {
  const DSPalette({
    required this.bg,
    required this.panel,
    required this.subtle,
    required this.line,
    required this.outline,
    required this.primary,
    required this.onPrimary,
    required this.ink,
    required this.muted,
    required this.tint,
    required this.onTint,
    required this.success,
    required this.amber,
    required this.error,
    required this.noticeSurface,
    required this.noticeBorder,
    required this.noticeAccent,
    this.forest = false,
  });
  final Color bg, panel, subtle, line, outline, primary, onPrimary, ink, muted;
  final Color tint, onTint, success, amber, error;
  final Color noticeSurface, noticeBorder, noticeAccent;
  final bool forest;
  static const media = Color(0xFF101216);
  static const onMedia = Colors.white;
  static DSPalette of(BuildContext context) =>
      Theme.of(context).extension<DSPalette>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);
  static const light = DSPalette(
    bg: Color(0xFFF7F8FA),
    panel: Colors.white,
    subtle: Color(0xFFF0F2F6),
    line: Color(0xFFE4E7ED),
    outline: Color(0xFF828D9D),
    primary: Color(0xFF4F67C8),
    onPrimary: Colors.white,
    ink: Color(0xFF202633),
    muted: Color(0xFF626D7D),
    tint: Color(0xFFE9EEFF),
    onTint: Color(0xFF334A9E),
    success: Color(0xFF267252),
    amber: Color(0xFF8C631E),
    error: Color(0xFFAD454A),
    noticeSurface: Color(0xFFFFF0EF),
    noticeBorder: Color(0xFFE7CECD),
    noticeAccent: Color(0xFFAD454A),
  );
  static const dark = DSPalette(
    bg: Color(0xFF15171C),
    panel: Color(0xFF20232B),
    subtle: Color(0xFF2B303A),
    line: Color(0xFF353B47),
    outline: Color(0xFF768193),
    primary: Color(0xFFA9B9FF),
    onPrimary: Color(0xFF1D2B5B),
    ink: Color(0xFFF0F2F7),
    muted: Color(0xFFADB5C3),
    tint: Color(0xFF2C3964),
    onTint: Color(0xFFDEE5FF),
    success: Color(0xFF8FD3B0),
    amber: Color(0xFFE4C186),
    error: Color(0xFFEEA3A7),
    noticeSurface: Color(0xFF42292E),
    noticeBorder: Color(0xFF73545B),
    noticeAccent: Color(0xFFEEA3A7),
  );
  static const woodland = DSPalette(
    bg: Color(0xFF0B1617),
    panel: Color(0xFF172425),
    subtle: Color(0xFF22302F),
    line: Color(0xFF344747),
    outline: Color(0xFF8A9E98),
    primary: Color(0xFFB2EED8),
    onPrimary: Color(0xFF102D23),
    ink: Color(0xFFF3F1E9),
    muted: Color(0xFFA9B6B4),
    tint: Color(0xFF29453E),
    onTint: Color(0xFFD0F4E5),
    success: Color(0xFFB2EED8),
    amber: Color(0xFFF5BE78),
    error: Color(0xFFEEA3A7),
    noticeSurface: Color(0xFF22302F),
    noticeBorder: Color(0xFF43514C),
    noticeAccent: Color(0xFFC4B09B),
    forest: true,
  );
  @override
  DSPalette copyWith() => this;
  @override
  DSPalette lerp(covariant DSPalette? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return DSPalette(
      bg: c(bg, other.bg),
      panel: c(panel, other.panel),
      subtle: c(subtle, other.subtle),
      line: c(line, other.line),
      outline: c(outline, other.outline),
      primary: c(primary, other.primary),
      onPrimary: c(onPrimary, other.onPrimary),
      ink: c(ink, other.ink),
      muted: c(muted, other.muted),
      tint: c(tint, other.tint),
      onTint: c(onTint, other.onTint),
      success: c(success, other.success),
      amber: c(amber, other.amber),
      error: c(error, other.error),
      noticeSurface: c(noticeSurface, other.noticeSurface),
      noticeBorder: c(noticeBorder, other.noticeBorder),
      noticeAccent: c(noticeAccent, other.noticeAccent),
      forest: t < .5 ? forest : other.forest,
    );
  }
}
