import 'package:flutter/material.dart';
import '../services/season_meta.dart';

/// 강화 단계 배지 — 웹 대시보드(user_dashboard.css .pitch-player-grade / .squad-slot-gradebadge)와 동일 규격 (2026-09-07 사용자 요청):
/// 정사각에 가까운 상자, 숫자만, 1px 테두리, 옅은 그림자.
/// 색: 1 회백 #C5C8C9 / 2~4 브론즈 #CD7F32 / 5~7 실버 #C0C0C0 / 8~10 골드 #FFD700 / 11~13 넥슨 플래티넘 판(내장 assets/grade_plt.png)+파란 테두리.
class GradeBadge extends StatelessWidget {
  final int grade;
  /// 배지 높이(px). 너비는 높이의 1.15배, 글자는 높이의 0.62배.
  final double size;
  const GradeBadge({Key? key, required this.grade, this.size = 18})
      : super(key: key);

  /// 웹 CSS와 같은 단계별 (배경, 테두리, 글자색)
  static ({Color bg, Color border, Color fg}) _style(int g) {
    if (g >= 8) return (bg: const Color(0xFFFFD700), border: const Color(0xFFDAA520), fg: const Color(0xFF8B4513));
    if (g >= 5) return (bg: const Color(0xFFC0C0C0), border: const Color(0xFF999999), fg: const Color(0xFF333333));
    if (g >= 2) return (bg: const Color(0xFFCD7F32), border: const Color(0xFFA05A2C), fg: const Color(0xFFFFFFFF));
    return (bg: const Color(0xFFC5C8C9), border: const Color(0xFF999999), fg: const Color(0xFF333333));
  }

  @override
  Widget build(BuildContext context) {
    final w = size * 1.15;
    final radius = BorderRadius.circular(size * 0.18);
    const shadow = [BoxShadow(color: Color(0x80000000), blurRadius: 2, offset: Offset(0, 1))];
    if (grade >= 11) {
      // 플래티넘 판 — 넥슨 원본 이미지를 앱에 내장 (네트워크 불필요)
      return Container(
        width: w,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: radius,
          image: const DecorationImage(image: AssetImage('assets/grade_plt.png'), fit: BoxFit.cover),
          border: Border.all(color: const Color(0xFF607DC4), width: 1),
          boxShadow: shadow,
        ),
        child: Text('$grade',
            style: TextStyle(fontSize: size * 0.62, fontWeight: FontWeight.w900, height: 1, color: const Color(0xFF2D2B43))),
      );
    }
    final st = _style(grade);
    return Container(
      width: w,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: st.bg,
        borderRadius: radius,
        border: Border.all(color: st.border, width: 1),
        boxShadow: shadow,
      ),
      child: Text('$grade',
          style: TextStyle(fontSize: size * 0.62, fontWeight: FontWeight.w800, height: 1, color: st.fg)),
    );
  }
}

/// 시즌 배지 — 시즌 이미지 표기 (이미지 없으면 시즌명 텍스트 폴백).
class SeasonBadge extends StatefulWidget {
  final num? spid;
  final double height;
  /// 이미지·이름 둘 다 없을 때 표시할 텍스트 (서버가 준 시즌명 등)
  final String? fallbackText;
  const SeasonBadge(
      {Key? key, required this.spid, this.height = 14, this.fallbackText})
      : super(key: key);

  @override
  State<SeasonBadge> createState() => _SeasonBadgeState();
}

class _SeasonBadgeState extends State<SeasonBadge> {
  @override
  void initState() {
    super.initState();
    SeasonMeta.ensure().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final img = SeasonMeta.imgForSpid(widget.spid);
    if (img != null) {
      return Image.network(img,
          height: widget.height,
          fit: BoxFit.contain,
          errorBuilder: (c, e, s) => _textFallback());
    }
    return _textFallback();
  }

  Widget _textFallback() {
    final text = widget.fallbackText ?? SeasonMeta.nameForSpid(widget.spid) ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(text,
        style: TextStyle(
            fontSize: widget.height * 0.72,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade500));
  }
}
