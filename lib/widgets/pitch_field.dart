import 'package:flutter/material.dart';

/// 축구장 배경 (시안 A '잔디 결', 2026-09-07 사용자 선택) — 스쿼드 탭·검색 스쿼드·경기 상세 3화면 공용.
///
/// 구성: 가로 깎기 잔디 무늬 9줄(두 톤 교차) + 상단 자연광 + 하단으로 살짝 어두워지는 깊이 +
///       라인 마킹(터치라인·하프라인·센터서클·페널티 박스·골 에어리어).
/// 자식(선수 카드 Stack)은 배경 위에 그대로 올린다.
class PitchField extends StatelessWidget {
  final Widget child;
  final double radius;

  const PitchField({
    Key? key,
    required this.child,
    this.radius = 12,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 6)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CustomPaint(
          painter: _PitchPainter(),
          child: child,
        ),
      ),
    );
  }
}

class _PitchPainter extends CustomPainter {
  static const int _bands = 9;
  static const Color _grassA = Color(0xFF2F7B47);
  static const Color _grassB = Color(0xFF2A7040);
  static const Color _lineColor = Color(0x9EFFFFFF); // 흰색 62%

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;

    // 1) 가로 잔디 결 (두 톤 교차 9줄)
    final bandH = h / _bands;
    for (var i = 0; i < _bands; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, i * bandH, w, bandH + 0.5),
        Paint()..color = i.isEven ? _grassA : _grassB,
      );
    }

    // 2) 상단 자연광
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment.topCenter,
          radius: 0.9,
          colors: [Color(0x1AFFFFFF), Color(0x00FFFFFF)],
          stops: [0.0, 0.6],
        ).createShader(Rect.fromLTWH(-w * 0.1, -h * 0.35, w * 1.2, h * 1.05)),
    );

    // 3) 하단으로 갈수록 어두워지는 깊이
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0x38000000)],
          stops: [0.55, 1.0],
        ).createShader(rect),
    );

    // 4) 라인 마킹
    final line = Paint()
      ..color = _lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final inX = w * 0.05;
    final inY = h * 0.04;
    // 터치라인
    canvas.drawRect(Rect.fromLTRB(inX, inY, w - inX, h - inY), line);
    // 하프라인
    canvas.drawLine(Offset(inX, h / 2), Offset(w - inX, h / 2), line);
    // 센터서클
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.13, line);
    // 페널티 박스 (위·아래, 터치라인과 맞닿은 변은 생략)
    final paW = w * 0.58;
    final paH = h * 0.14;
    _openBox(canvas, line, Rect.fromLTWH((w - paW) / 2, inY, paW, paH), top: true);
    _openBox(canvas, line, Rect.fromLTWH((w - paW) / 2, h - inY - paH, paW, paH), top: false);
    // 골 에어리어
    final gaW = w * 0.28;
    final gaH = h * 0.05;
    _openBox(canvas, line, Rect.fromLTWH((w - gaW) / 2, inY, gaW, gaH), top: true);
    _openBox(canvas, line, Rect.fromLTWH((w - gaW) / 2, h - inY - gaH, gaW, gaH), top: false);
  }

  /// 터치라인 쪽 변을 뺀 ㄷ자 박스
  void _openBox(Canvas canvas, Paint p, Rect r, {required bool top}) {
    final path = Path();
    if (top) {
      path.moveTo(r.left, r.top);
      path.lineTo(r.left, r.bottom);
      path.lineTo(r.right, r.bottom);
      path.lineTo(r.right, r.top);
    } else {
      path.moveTo(r.left, r.bottom);
      path.lineTo(r.left, r.top);
      path.lineTo(r.right, r.top);
      path.lineTo(r.right, r.bottom);
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _PitchPainter oldDelegate) => false;
}
