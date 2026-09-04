import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Panenka 색상 프리셋 체계 (2026-09-04 도입, 사용자 승인 시안 기준)
//
// 60:30:10 역할 색:
//   bg/card(60)  본문 배경·카드
//   band(30)     상단 헤더·하단 알약 바·일시정지 버튼·주요 버튼 바탕
//   accent(10)   경기 중 띠·시간·스코어·상대 점수·선택 탭·로고 테두리·D-day·
//                주요 버튼 글자 — 이 자리 외에는 쓰지 않음
//   win          승 숫자·배지·최근 20경기 승 칸 (강조색과 다른 차분한 한색)
//   lose         패 숫자·배지·패 칸·중지 버튼 (테라코타 계열)
//   sub          모드·티어·점수·순위 아이콘, 주 계정 테두리 (눌린 보조 톤)
//
// 프리셋은 다크 값만 정의한다. 라이트는 띠·강조만 가져와 흰 카드 위에 자동
// 파생하며, 흰 바탕 위 글자색은 대비 4.5:1이 될 때까지 자동으로 어둡게 내린다
// (사용자 조건: "글자가 안 보이는 완전 오류가 절대 없어야").
// 프리셋과 무관하게 고정되는 색: TOP3 금은동, 선수 등급 배지, 티어 로고,
// 히트맵 파랑·빨강, 온라인 초록 점.
// ─────────────────────────────────────────────────────────────────────────────

/// 프리셋 1종의 다크 기준 색 정의
@immutable
class PanenkaPreset {
  final String id;
  final String name;
  final String note;
  final Color bg;
  final Color card;
  final Color band;
  final Color accent;
  final Color sub;
  final Color win;
  final Color lose;
  final Color liveBg;

  const PanenkaPreset({
    required this.id,
    required this.name,
    required this.note,
    required this.bg,
    required this.card,
    required this.band,
    required this.accent,
    required this.sub,
    required this.win,
    required this.lose,
    required this.liveBg,
  });
}

/// 사용자 선택 가능한 프리셋 6종 (순서 = 더보기 › 색상 화면 나열 순서)
/// 수치는 참고 이미지 ex4 실측 채도·명도 기준 (띠 s26 l21 · 승 s32 l66 · 패 s33 l42 · 강조 s82 l71)
const List<PanenkaPreset> kPanenkaPresets = [
  PanenkaPreset(
    id: 'purple',
    name: '퍼플',
    note: '기본',
    bg: Color(0xFF1B1B1D),
    card: Color(0xFF222124),
    band: Color(0xFF2F2843),
    accent: Color(0xFF9278F2),
    sub: Color(0xFFBFB1E7),
    win: Color(0xFF8DA6C4),
    lose: Color(0xFF8E5648),
    liveBg: Color(0xFF322B46),
  ),
  PanenkaPreset(
    id: 'navy',
    name: '네이비 골드',
    note: '남색 띠 · 금색 강조',
    bg: Color(0xFF1D1B1E),
    card: Color(0xFF222023),
    band: Color(0xFF293744),
    accent: Color(0xFFF2D178),
    sub: Color(0xFFB2CDE8),
    win: Color(0xFF8CA9C4),
    lose: Color(0xFF8E5E48),
    liveBg: Color(0xFF2C3A47),
  ),
  PanenkaPreset(
    id: 'green',
    name: '딥그린 오렌지',
    note: '짙은 초록 띠 · 주황 강조',
    bg: Color(0xFF1B1D1D),
    card: Color(0xFF212424),
    band: Color(0xFF284340),
    accent: Color(0xFFF2A778),
    sub: Color(0xFFB1E7D7),
    win: Color(0xFF8DC4B4),
    lose: Color(0xFF8E5448),
    liveBg: Color(0xFF2B4642),
  ),
  PanenkaPreset(
    id: 'blue',
    name: '미드나잇 스카이',
    note: '푸른 밤 띠 · 하늘색 강조',
    bg: Color(0xFF1B1C1D),
    card: Color(0xFF212324),
    band: Color(0xFF283643),
    accent: Color(0xFF78CAF2),
    sub: Color(0xFFB1CDE7),
    win: Color(0xFF8DABC4),
    lose: Color(0xFF8E4F48),
    liveBg: Color(0xFF2B3A46),
  ),
  PanenkaPreset(
    id: 'brown',
    name: '브라운 옐로우',
    note: '갈색 띠 · 노랑 강조',
    bg: Color(0xFF1D1C1B),
    card: Color(0xFF242221),
    band: Color(0xFF433128),
    accent: Color(0xFFF2D978),
    sub: Color(0xFFB1CFE7),
    win: Color(0xFF8DABC4),
    lose: Color(0xFF8E5648),
    liveBg: Color(0xFF46342B),
  ),
  PanenkaPreset(
    id: 'coral',
    name: '플럼 코랄',
    note: '자두색 띠 · 코랄 강조',
    bg: Color(0xFF1D1B1C),
    card: Color(0xFF242122),
    band: Color(0xFF432836),
    accent: Color(0xFFF2A178),
    sub: Color(0xFFB1E7E0),
    win: Color(0xFF8DC4BD),
    lose: Color(0xFF8E4D48),
    liveBg: Color(0xFF462B38),
  ),
];

// ───────────────────────── 색 계산 유틸 (라이트 파생용) ─────────────────────────

/// WCAG 상대 휘도
double _luminance(Color c) => c.computeLuminance();

/// 두 색의 대비비 (1~21)
double panenkaContrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// [bg] 위에 글자로 올릴 때 대비 [target] 이상이 될 때까지 명도만 조정한다
/// (색상은 유지). 밝은 바탕이면 검정 쪽으로, 어두운 바탕이면 흰색 쪽으로 섞는다.
/// 채움색(배지·버튼)은 건드리지 않고 글자색에만 적용한다.
Color panenkaInkOn(Color color, Color bg, {double target = 4.5}) {
  final toward = _luminance(bg) > 0.4 ? Colors.black : Colors.white;
  var c = color;
  var t = 0.0;
  while (panenkaContrast(c, bg) < target && t < 0.95) {
    t += 0.03;
    c = Color.lerp(color, toward, t)!;
  }
  return c;
}

/// 채움색 위에 올릴 글자색 — 검정/흰색 중 대비가 더 큰 쪽 자동 선택
Color panenkaOnFill(Color fill) {
  const dark = Color(0xFF14161C);
  return panenkaContrast(dark, fill) >= panenkaContrast(Colors.white, fill)
      ? dark
      : Colors.white;
}

/// 앱 전역에서 쓰는 역할 색 묶음. `PanenkaTokens.of(context)`로 접근.
@immutable
class PanenkaTokens extends ThemeExtension<PanenkaTokens> {
  /// 본문 배경 (60)
  final Color bg;
  /// 카드 배경 (60)
  final Color card;
  /// 띠색 (30): 헤더·하단 알약 바·일시정지 버튼·주요 버튼 바탕
  final Color band;
  /// 띠 위 글자색 (항상 밝은색)
  final Color bandInk;
  /// 본문 글자색
  final Color ink;
  /// 보조 글자색 (라벨·캡션)
  final Color mute;
  /// 띠 위에 올리는 강조색 (선택 탭·로고 테두리·D-day·주요 버튼 글자)
  final Color accentBand;
  /// 카드 위에 올리는 강조색 (경기 중 띠·시간·스코어·상대 점수). 라이트는 대비 보정됨
  final Color accentInk;
  /// 강조색 연한 바탕 (카드 위)
  final Color accentSoft;
  /// 강조색 연한 바탕 (띠 위, 선택 탭 인디케이터)
  final Color accentSoftBand;
  /// 보조 아이콘·주 계정 테두리 (카드 위, 라이트는 대비 보정됨)
  final Color subInk;
  /// 승리 채움색 (배지·타일)
  final Color win;
  /// 승리 글자색 (카드 위, 라이트는 대비 보정됨)
  final Color winInk;
  /// 패배 채움색 (배지·타일·중지 버튼)
  final Color lose;
  /// 패배 글자색 (카드 위, 라이트는 대비 보정됨)
  final Color loseInk;
  /// 무승부 채움색 (중립 회색)
  final Color draw;
  /// 경기 중 띠 배경
  final Color liveBg;
  /// 경기 중 띠 왼쪽 테두리
  final Color liveEdge;
  /// 카드 위 연한 면 (승무패 상자 등)
  final Color soft;
  /// 구분선 (약)
  final Color line;
  /// 구분선 (강)
  final Color lineStrong;

  const PanenkaTokens({
    required this.bg,
    required this.card,
    required this.band,
    required this.bandInk,
    required this.ink,
    required this.mute,
    required this.accentBand,
    required this.accentInk,
    required this.accentSoft,
    required this.accentSoftBand,
    required this.subInk,
    required this.win,
    required this.winInk,
    required this.lose,
    required this.loseInk,
    required this.draw,
    required this.liveBg,
    required this.liveEdge,
    required this.soft,
    required this.line,
    required this.lineStrong,
  });

  /// 다크: 프리셋 값을 그대로 쓰되, 글자용 색은 카드 대비 4.5:1까지 밝게 보정
  factory PanenkaTokens.dark(PanenkaPreset p) => PanenkaTokens(
        bg: p.bg,
        card: p.card,
        band: p.band,
        bandInk: const Color(0xFFF2F1EC),
        ink: const Color(0xFFF2F1EC),
        mute: const Color(0xFFA5A3AD),
        accentBand: p.accent,
        accentInk: panenkaInkOn(p.accent, p.card),
        accentSoft: p.accent.withOpacity(0.18),
        accentSoftBand: p.accent.withOpacity(0.18),
        subInk: panenkaInkOn(p.sub, p.card, target: 3.0),
        win: p.win,
        winInk: panenkaInkOn(p.win, p.card),
        lose: p.lose,
        loseInk: panenkaInkOn(p.lose, p.card), // 테라코타는 글자로 쓸 때만 밝게 보정
        draw: const Color(0xFF5B5B62),
        liveBg: p.liveBg,
        liveEdge: p.accent,
        soft: Colors.white.withOpacity(0.06),
        line: Colors.white.withOpacity(0.06),
        lineStrong: Colors.white.withOpacity(0.30),
      );

  /// 라이트: 띠·강조만 가져오고 바탕은 흰색 계열, 글자색은 대비 보장
  factory PanenkaTokens.light(PanenkaPreset p) {
    const card = Colors.white;
    final bg = Color.lerp(const Color(0xFFF7F7F9), p.band, 0.06)!;
    return PanenkaTokens(
      bg: bg,
      card: card,
      band: p.band,
      bandInk: const Color(0xFFF2F1EC),
      ink: const Color(0xFF1A1D24),
      mute: const Color(0xFF6B7080),
      accentBand: p.accent,
      accentInk: panenkaInkOn(p.accent, card),
      accentSoft: Color.lerp(Colors.white, p.accent, 0.16)!,
      accentSoftBand: p.accent.withOpacity(0.18),
      subInk: panenkaInkOn(p.sub, card),
      win: p.win,
      winInk: panenkaInkOn(p.win, card),
      lose: p.lose,
      loseInk: panenkaInkOn(p.lose, card),
      draw: const Color(0xFF8A8F9A),
      liveBg: Color.lerp(Colors.white, p.accent, 0.18)!,
      liveEdge: panenkaInkOn(p.accent, card, target: 3.0),
      soft: Colors.black.withOpacity(0.045),
      line: Colors.black.withOpacity(0.07),
      lineStrong: Colors.black.withOpacity(0.20),
    );
  }

  static PanenkaTokens of(BuildContext context) =>
      Theme.of(context).extension<PanenkaTokens>() ??
      PanenkaTokens.dark(kPanenkaPresets.first);

  /// 승리 채움 위 글자색
  Color get onWin => panenkaOnFill(win);
  /// 강조 채움 위 글자색
  Color get onAccentInk => panenkaOnFill(accentInk);

  @override
  PanenkaTokens copyWith({
    Color? bg,
    Color? card,
    Color? band,
    Color? bandInk,
    Color? ink,
    Color? mute,
    Color? accentBand,
    Color? accentInk,
    Color? accentSoft,
    Color? accentSoftBand,
    Color? subInk,
    Color? win,
    Color? winInk,
    Color? lose,
    Color? loseInk,
    Color? draw,
    Color? liveBg,
    Color? liveEdge,
    Color? soft,
    Color? line,
    Color? lineStrong,
  }) =>
      PanenkaTokens(
        bg: bg ?? this.bg,
        card: card ?? this.card,
        band: band ?? this.band,
        bandInk: bandInk ?? this.bandInk,
        ink: ink ?? this.ink,
        mute: mute ?? this.mute,
        accentBand: accentBand ?? this.accentBand,
        accentInk: accentInk ?? this.accentInk,
        accentSoft: accentSoft ?? this.accentSoft,
        accentSoftBand: accentSoftBand ?? this.accentSoftBand,
        subInk: subInk ?? this.subInk,
        win: win ?? this.win,
        winInk: winInk ?? this.winInk,
        lose: lose ?? this.lose,
        loseInk: loseInk ?? this.loseInk,
        draw: draw ?? this.draw,
        liveBg: liveBg ?? this.liveBg,
        liveEdge: liveEdge ?? this.liveEdge,
        soft: soft ?? this.soft,
        line: line ?? this.line,
        lineStrong: lineStrong ?? this.lineStrong,
      );

  @override
  PanenkaTokens lerp(ThemeExtension<PanenkaTokens>? other, double t) {
    if (other is! PanenkaTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return PanenkaTokens(
      bg: l(bg, other.bg),
      card: l(card, other.card),
      band: l(band, other.band),
      bandInk: l(bandInk, other.bandInk),
      ink: l(ink, other.ink),
      mute: l(mute, other.mute),
      accentBand: l(accentBand, other.accentBand),
      accentInk: l(accentInk, other.accentInk),
      accentSoft: l(accentSoft, other.accentSoft),
      accentSoftBand: l(accentSoftBand, other.accentSoftBand),
      subInk: l(subInk, other.subInk),
      win: l(win, other.win),
      winInk: l(winInk, other.winInk),
      lose: l(lose, other.lose),
      loseInk: l(loseInk, other.loseInk),
      draw: l(draw, other.draw),
      liveBg: l(liveBg, other.liveBg),
      liveEdge: l(liveEdge, other.liveEdge),
      soft: l(soft, other.soft),
      line: l(line, other.line),
      lineStrong: l(lineStrong, other.lineStrong),
    );
  }
}

class ThemeProvider with ChangeNotifier {
  static const String _kDarkKey = 'isDarkMode';
  static const String _kPresetKey = 'colorPreset';

  bool _isDarkMode = true; // 기본값 다크테마 (브랜드 기본)
  PanenkaPreset _preset = kPanenkaPresets.first;

  bool get isDarkMode => _isDarkMode;
  PanenkaPreset get preset => _preset;

  ThemeProvider() {
    _loadThemePreference();
  }

  // 저장된 테마·프리셋 설정 불러오기
  Future<void> _loadThemePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool(_kDarkKey) ?? true; // 기본값 다크테마
      final id = prefs.getString(_kPresetKey);
      _preset = kPanenkaPresets.firstWhere((p) => p.id == id,
          orElse: () => kPanenkaPresets.first);
      notifyListeners();
    } catch (e) {
      print('[ThemeProvider] 테마 설정 로드 실패: $e');
    }
  }

  // 테마 토글 및 저장
  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kDarkKey, _isDarkMode);
    } catch (e) {
      print('[ThemeProvider] 테마 설정 저장 실패: $e');
    }
  }

  // 색상 프리셋 선택 및 저장 (더보기 › 색상)
  Future<void> setPreset(PanenkaPreset preset) async {
    if (_preset.id == preset.id) return;
    _preset = preset;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPresetKey, preset.id);
    } catch (e) {
      print('[ThemeProvider] 색상 프리셋 저장 실패: $e');
    }
  }

  ThemeData get lightTheme {
    final t = PanenkaTokens.light(_preset);
    final primary = t.accentInk;
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: primary,
      scaffoldBackgroundColor: t.bg,
      cardColor: t.card,
      appBarTheme: AppBarTheme(
        backgroundColor: t.bg,
        foregroundColor: const Color(0xFF1A202A),
        elevation: 0,
      ),
      colorScheme: ColorScheme.light(
        primary: primary,
        secondary: primary,
        surface: t.card,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.card,
        indicatorColor: primary.withOpacity(0.14),
        iconTheme: MaterialStateProperty.resolveWith((states) =>
            IconThemeData(
                color: states.contains(MaterialState.selected)
                    ? primary
                    : Colors.grey.shade600)),
        labelTextStyle: MaterialStateProperty.resolveWith((states) =>
            TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: states.contains(MaterialState.selected)
                    ? primary
                    : Colors.grey.shade600)),
      ),
      cardTheme: CardTheme(
        color: t.card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: t.onAccentInk,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
      extensions: [t],
    );
  }

  ThemeData get darkTheme {
    final t = PanenkaTokens.dark(_preset);
    final primary = t.accentInk;
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: primary,
      scaffoldBackgroundColor: t.bg,
      cardColor: t.card,
      appBarTheme: AppBarTheme(
        backgroundColor: t.bg,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      colorScheme: ColorScheme.dark(
        primary: primary,
        secondary: primary,
        surface: t.card,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.band,
        indicatorColor: primary.withOpacity(0.16),
        iconTheme: MaterialStateProperty.resolveWith((states) =>
            IconThemeData(
                color: states.contains(MaterialState.selected)
                    ? primary
                    : Colors.grey.shade500)),
        labelTextStyle: MaterialStateProperty.resolveWith((states) =>
            TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: states.contains(MaterialState.selected)
                    ? primary
                    : Colors.grey.shade500)),
      ),
      cardTheme: CardTheme(
        color: t.card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: t.onAccentInk,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.grey[800]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white70),
        titleLarge: TextStyle(color: Colors.white),
      ),
      extensions: [t],
    );
  }
}
