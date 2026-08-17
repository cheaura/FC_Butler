import 'package:flutter/material.dart';

/// Panenka 브랜드 로고 (앱 아이콘과 동일한 P+칩킥 궤적 이미지).
/// 스플래시·로그인·동의·매크로 앱바의 축구공 아이콘 대체 (2026-08-17 사용자 지시).
class PanenkaLogo extends StatelessWidget {
  final double size;
  const PanenkaLogo({Key? key, this.size = 80}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: Image.asset(
        'assets/icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (c, e, s) =>
            Icon(Icons.sports_soccer, size: size, color: Colors.white),
      ),
    );
  }
}
