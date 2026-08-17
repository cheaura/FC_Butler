import 'package:flutter/material.dart';
import '../constants/positions.dart';
import '../services/season_meta.dart';

/// 강화 단계 배지 — 웹 스쿼드 탭 확정 색 체계와 동일:
/// 1 회백 / 2~4 브론즈 / 5~7 실버 / 8~10 골드 / 11~13 넥슨 플래티넘 판(bg_plt.png 원본).
class GradeBadge extends StatelessWidget {
  final int grade;
  final double fontSize;
  const GradeBadge({Key? key, required this.grade, this.fontSize = 11})
      : super(key: key);

  static const String _pltUrl =
      'https://ssl.nexon.com/s2/game/fc/online/obt/datacenter/bg_plt.png';

  @override
  Widget build(BuildContext context) {
    final text = Text('+$grade',
        style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            color: Colors.black87));
    if (grade >= 11) {
      // 플래티넘 판은 넥슨 원본 이미지 (색 근사가 아니라 실물 — 사용자 교정)
      return Container(
        padding: EdgeInsets.symmetric(horizontal: fontSize * 0.5, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          image: const DecorationImage(
              image: NetworkImage(_pltUrl), fit: BoxFit.cover),
          color: const Color(0xFFD8E4E8), // 이미지 로드 전 근사색
        ),
        child: text,
      );
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: fontSize * 0.5, vertical: 2),
      decoration: BoxDecoration(
        color: gradeColor(grade),
        borderRadius: BorderRadius.circular(5),
      ),
      child: text,
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
