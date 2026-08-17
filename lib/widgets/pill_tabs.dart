import 'package:flutter/material.dart';

/// 알약 슬라이드 탭 (사용자 확정 컨트롤 — 하단 탭바와 같은 디자인 문법).
/// 풀폭 균등 분할 + 선택 시 보라 필이 슬라이드. SegmentedButton 대체 공용 위젯.
class PillTabs extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double height;

  const PillTabs({
    Key? key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.height = 40,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = theme.colorScheme.primary;
    final subColor = Colors.grey.shade500;
    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(999),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slotW = constraints.maxWidth / labels.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                left: slotW * selectedIndex,
                top: 0,
                bottom: 0,
                width: slotW,
                child: Container(
                  decoration: BoxDecoration(
                    color: accent.withOpacity(isDark ? 0.20 : 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelected(i),
                        child: Center(
                          child: Text(labels[i],
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: i == selectedIndex
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: i == selectedIndex
                                      ? accent
                                      : subColor)),
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
