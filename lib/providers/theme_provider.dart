import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Panenka 브랜드 팔레트 (2026-08-17 스토어 출시 대비 개편)
/// 방향: fc-info류 "순수 다크 + 카드형 회색 + 네온 포인트" 색감.
/// 포인트 색은 사용자 선택(2026-08-17): 네온 퍼플 — FC 계열 앱과 차별화.
class PanenkaColors {
  static const Color accent = Color(0xFFA78BFA); // 네온 퍼플 (다크 포인트)
  static const Color accentDeep = Color(0xFF7C3AED); // 진한 퍼플 (라이트 포인트·CTA)
  static const Color darkBg = Color(0xFF100F1A); // 다크 배경 (거의 검정, 퍼플 기미)
  static const Color darkCard = Color(0xFF1C1928); // 다크 카드
  static const Color darkNav = Color(0xFF141220); // 다크 하단탭
  static const Color brandDeep = Color(0xFF2A1B54); // 브랜드 그라데이션 시작
  static const Color brandDeep2 = Color(0xFF100F1A); // 브랜드 그라데이션 끝
  static const Color lightBg = Color(0xFFF6F5FA);
}

class ThemeProvider with ChangeNotifier {
  bool _isDarkMode = true;  // 기본값 다크테마 (브랜드 기본)

  bool get isDarkMode => _isDarkMode;

  ThemeProvider() {
    _loadThemePreference();
  }

  // 저장된 테마 설정 불러오기
  Future<void> _loadThemePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool('isDarkMode') ?? true;  // 기본값 다크테마
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
      await prefs.setBool('isDarkMode', _isDarkMode);
    } catch (e) {
      print('[ThemeProvider] 테마 설정 저장 실패: $e');
    }
  }

  ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: PanenkaColors.accentDeep,
      scaffoldBackgroundColor: PanenkaColors.lightBg,
      cardColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: PanenkaColors.lightBg,
        foregroundColor: Color(0xFF1A202A),
        elevation: 0,
      ),
      colorScheme: const ColorScheme.light(
        primary: PanenkaColors.accentDeep,
        secondary: PanenkaColors.accentDeep,
        surface: Colors.white,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: PanenkaColors.accentDeep.withOpacity(0.14),
        iconTheme: MaterialStateProperty.resolveWith((states) =>
            IconThemeData(
                color: states.contains(MaterialState.selected)
                    ? PanenkaColors.accentDeep
                    : Colors.grey.shade600)),
        labelTextStyle: MaterialStateProperty.resolveWith((states) =>
            TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: states.contains(MaterialState.selected)
                    ? PanenkaColors.accentDeep
                    : Colors.grey.shade600)),
      ),
      cardTheme: CardTheme(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: PanenkaColors.accentDeep,
          foregroundColor: Colors.white,
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
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: PanenkaColors.accentDeep, width: 2),
        ),
      ),
    );
  }

  ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: PanenkaColors.accent,
      scaffoldBackgroundColor: PanenkaColors.darkBg,
      cardColor: PanenkaColors.darkCard,
      appBarTheme: const AppBarTheme(
        backgroundColor: PanenkaColors.darkBg,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      colorScheme: const ColorScheme.dark(
        primary: PanenkaColors.accent,
        secondary: PanenkaColors.accent,
        surface: PanenkaColors.darkCard,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: PanenkaColors.darkNav,
        indicatorColor: PanenkaColors.accent.withOpacity(0.16),
        iconTheme: MaterialStateProperty.resolveWith((states) =>
            IconThemeData(
                color: states.contains(MaterialState.selected)
                    ? PanenkaColors.accent
                    : Colors.grey.shade500)),
        labelTextStyle: MaterialStateProperty.resolveWith((states) =>
            TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: states.contains(MaterialState.selected)
                    ? PanenkaColors.accent
                    : Colors.grey.shade500)),
      ),
      cardTheme: CardTheme(
        color: PanenkaColors.darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: PanenkaColors.accent,
          foregroundColor: Colors.white,
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
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: PanenkaColors.accent, width: 2),
        ),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white70),
        titleLarge: TextStyle(color: Colors.white),
      ),
    );
  }
}
