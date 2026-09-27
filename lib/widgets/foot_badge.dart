import 'package:flutter/material.dart';
import '../models/foot_stat.dart';
import '../models/work_rate.dart';

/// 양발 발 모양 + 공격/수비 참여도 화살표 (2026-09-28 — 웹 static/user/foot_wr.js와 같은 좌표·색).
///
/// - 발: 자체 제작 축구화 밑창(스터드) 두 짝, 왼쪽=왼발. 주발 금색 #FFD54F(숫자 짙은 갈색),
///   약발 짙은 회색 #3f434a(숫자 흰색), 둘 다 흰 테두리. 양발 5·5 카드도 주발 쪽만 금색 (사용자 확정).
/// - 참여도: 빨강 ▲ 공격 / 파랑 ▼ 수비, 머리 36%·몸통 64%, 두 숫자는 세로 50%로 수평 정렬.

// ── 축구화 밑창 윤곽 (viewBox 70×100, 오른발 기준 — 왼발은 좌우 대칭) ──
const double _soleW = 70, _soleH = 100;
const List<List<double>> _soleR = [
  // [x, y] 이동 1개 + 3차 베지어 12개 (웹 SOLE_R과 동일)
  [35, 99],
  [22.2, 99, 15.2, 92, 15.2, 82],
  [15.2, 70, 18.7, 62, 17.5, 52],
  [16.3, 40, 9.3, 32, 10.5, 22],
  [11.7, 9, 22.2, 2, 36.2, 2],
  [51.3, 2, 60.7, 10, 60.7, 24],
  [60.7, 36, 54.8, 44, 53.7, 56],
  [52.5, 68, 56, 76, 56, 84],
  [56, 93, 47.8, 99, 35, 99],
];
const List<List<double>> _studsR = [
  [25.7, 13],
  [45.5, 13],
  [25.7, 89],
  [45.5, 89],
];

const Color _mainFill = Color(0xFFFFD54F);
const Color _mainText = Color(0xFF2B2100);
const Color _weakFill = Color(0xFF3F434A);

class _SolePainter extends CustomPainter {
  _SolePainter({required this.left, required this.main, required this.number});

  final bool left;
  final bool main;
  final int number;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / _soleW, sy = size.height / _soleH;
    double x(double v) => (left ? _soleW - v : v) * sx;
    double y(double v) => v * sy;
    final path = Path()..moveTo(x(_soleR[0][0]), y(_soleR[0][1]));
    for (final c in _soleR.skip(1)) {
      path.cubicTo(x(c[0]), y(c[1]), x(c[2]), y(c[3]), x(c[4]), y(c[5]));
    }
    path.close();
    canvas.drawPath(path, Paint()..color = main ? _mainFill : _weakFill);
    // 흰 테두리 (크기와 무관하게 약 1.2px)
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = main ? Colors.white : Colors.white.withOpacity(0.75));
    final stud = Paint()..color = Colors.black.withOpacity(0.3);
    for (final s in _studsR) {
      canvas.drawCircle(Offset(x(s[0]), y(s[1])), 3.4 * sx, stud);
    }
    final tp = TextPainter(
      text: TextSpan(
          text: '$number',
          style: TextStyle(
              fontSize: size.height * 0.56,
              height: 1.0,
              fontWeight: FontWeight.w800,
              color: main ? _mainText : Colors.white)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, size.height * 0.52 - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _SolePainter old) =>
      old.left != left || old.main != main || old.number != number;
}

/// 발 두 짝 (높이 [height], 폭은 0.7배)
class FeetIcon extends StatelessWidget {
  const FeetIcon({super.key, required this.foot, this.height = 20});

  final FootStat? foot;
  final double height;

  @override
  Widget build(BuildContext context) {
    final f = foot;
    if (f == null) return const SizedBox.shrink();
    final w = height * _soleW / _soleH;
    return Tooltip(
      message: f.description,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        CustomPaint(size: Size(w, height), painter: _SolePainter(left: true, main: f.prefIsLeft, number: f.left)),
        const SizedBox(width: 1),
        CustomPaint(size: Size(w, height), painter: _SolePainter(left: false, main: !f.prefIsLeft, number: f.right)),
      ]),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter({required this.up, required this.number});

  final bool up;
  final int number;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final head = h * 0.36, bw = w * 0.56, bx = (w - bw) / 2;
    final pts = up
        ? [Offset(w / 2, 0), Offset(w, head), Offset(bx + bw, head), Offset(bx + bw, h), Offset(bx, h), Offset(bx, head), Offset(0, head)]
        : [Offset(bx, 0), Offset(bx + bw, 0), Offset(bx + bw, h - head), Offset(w, h - head), Offset(w / 2, h), Offset(0, h - head), Offset(bx, h - head)];
    final path = Path()..addPolygon(pts, true);
    canvas.drawPath(path, Paint()..color = up ? const Color(0xFFE53935) : const Color(0xFF1E88E5));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.04
          ..color = Colors.black.withOpacity(0.35));
    final tp = TextPainter(
      text: TextSpan(
          text: '$number',
          style: TextStyle(fontSize: h * 0.62, height: 1.0, fontWeight: FontWeight.w800, color: Colors.white)),
      textDirection: TextDirection.ltr,
    )..layout();
    // 두 화살표 모두 세로 50% 중앙 → 숫자 수평 정렬
    tp.paint(canvas, Offset((w - tp.width) / 2, h / 2 - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter old) => old.up != up || old.number != number;
}

/// 참여도 화살표 두 개 (한 변 [size])
class WorkRateIcon extends StatelessWidget {
  const WorkRateIcon({super.key, required this.workrate, this.size = 16});

  final WorkRate? workrate;
  final double size;

  @override
  Widget build(BuildContext context) {
    final w = workrate;
    if (w == null) return const SizedBox.shrink();
    return Tooltip(
      message: w.description,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        CustomPaint(size: Size.square(size), painter: _ArrowPainter(up: true, number: w.att)),
        const SizedBox(width: 1),
        CustomPaint(size: Size.square(size), painter: _ArrowPainter(up: false, number: w.def)),
      ]),
    );
  }
}

/// 선수 목록 행·편집 시트의 양발 + 참여도 묶음 — 신규특성 아이콘 바로 오른쪽 (2026-09-28 'L5 R4' 글자 → 발 모양).
/// 둘 다 없으면 아무것도 그리지 않는다.
class FootBadge extends StatelessWidget {
  const FootBadge({super.key, required this.foot, this.workrate, this.feetHeight = 20, this.arrowSize = 15});

  final FootStat? foot;
  final WorkRate? workrate;
  final double feetHeight;
  final double arrowSize;

  @override
  Widget build(BuildContext context) {
    if (foot == null && workrate == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (foot != null) FeetIcon(foot: foot, height: feetHeight),
        if (foot != null && workrate != null) const SizedBox(width: 4),
        if (workrate != null) WorkRateIcon(workrate: workrate, size: arrowSize),
      ]),
    );
  }
}
