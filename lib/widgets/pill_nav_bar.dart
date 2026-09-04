import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';

class PillBarItem {
  final IconData icon;
  final String label;
  const PillBarItem(this.icon, this.label);
}

/// 반투명 플로팅 알약 내비게이션 바 — 선택 시 인디케이터가 슬라이드.
/// 하단 탭바와 매크로 상단 탭이 같은 위젯을 공유한다 (사용자 지정: 동일 디자인).
class PanenkaPillBar extends StatelessWidget {
  final List<PillBarItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double height;

  const PanenkaPillBar({
    Key? key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.height = 62,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // 색상 프리셋(2026-09-04): 알약 바는 띠색(30), 선택 탭은 띠 위 강조색(10)
    final tokens = PanenkaTokens.of(context);
    final accent = tokens.accentBand;
    final idle = tokens.bandInk.withOpacity(0.62);
    final barColor = tokens.band.withOpacity(0.94);
    return Container(
      height: height,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: barColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.45 : 0.12),
              blurRadius: 18,
              offset: const Offset(0, 6)),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slotW = constraints.maxWidth / items.length;
          return Stack(
            children: [
              // 슬라이드 인디케이터 (선택 이동 시 스르륵)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                left: slotW * selectedIndex,
                top: 0,
                bottom: 0,
                width: slotW,
                child: Container(
                  decoration: BoxDecoration(
                    color: tokens.accentSoftBand,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelected(i),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(items[i].icon,
                                size: height >= 56 ? 20 : 17,
                                color: i == selectedIndex
                                    ? accent
                                    : idle),
                            const SizedBox(height: 2),
                            Text(items[i].label,
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: TextStyle(
                                    fontSize: height >= 56 ? 9 : 8.5,
                                    fontWeight: i == selectedIndex
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    color: i == selectedIndex
                                        ? accent
                                        : idle)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
