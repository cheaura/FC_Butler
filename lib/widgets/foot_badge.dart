import 'package:flutter/material.dart';
import '../models/foot_stat.dart';

/// 선수 목록 행의 양발 스탯 배지 — 축약 `L5 R4`, 주발 쪽만 굵게·본문색, 약발 쪽은 흐리게 (2026-09-21).
/// 신규특성 아이콘 바로 오른쪽에 놓인다. [foot]이 null이면 아무것도 그리지 않는다.
class FootBadge extends StatelessWidget {
  const FootBadge({super.key, required this.foot, this.fontSize = 11});

  final FootStat? foot;
  final double fontSize;

  static const Color _weakColor = Color(0xFF9E9E9E); // Colors.grey.shade500 과 동일 (목록 보조 글자색)

  @override
  Widget build(BuildContext context) {
    final f = foot;
    if (f == null) return const SizedBox.shrink();
    final bodyColor = DefaultTextStyle.of(context).style.color ?? Theme.of(context).colorScheme.onSurface;
    final pref = TextStyle(
        fontSize: fontSize, fontWeight: FontWeight.w800, color: bodyColor, fontFeatures: const [FontFeature.tabularFigures()]);
    final weak = TextStyle(
        fontSize: fontSize, fontWeight: FontWeight.w500, color: _weakColor, fontFeatures: const [FontFeature.tabularFigures()]);
    return Padding(
      padding: const EdgeInsets.only(left: 5),
      child: Tooltip(
        message: f.description,
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: f.leftLabel, style: f.prefIsLeft ? pref : weak),
            TextSpan(text: ' ', style: weak),
            TextSpan(text: f.rightLabel, style: f.prefIsLeft ? weak : pref),
          ]),
          maxLines: 1,
          softWrap: false,
        ),
      ),
    );
  }
}
