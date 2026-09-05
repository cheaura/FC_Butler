import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

/// 더보기 › 색상 — 프리셋 카드를 누르면 앱 전체에 즉시 적용·자동 저장 (2026-09-04).
/// 색상환·슬라이더 없이 카드 선택만 노출한다 (사용자 요구: 어렵지 않게).
///
/// 2단계 '직접 만들기' (2026-09-05): 화면 하단에 띠색·강조색·승/패 짝 세 줄 색 칩.
/// 칩은 프리셋과 같은 채도·명도로 정규화된 색조만 제공하고, 나머지 색은 자동 계산한다.
/// 칩을 누르면 즉시 적용·저장(prefs 'colorCustom', 프리셋 id 'custom').
class ColorSettingsScreen extends StatelessWidget {
  const ColorSettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final tokens = PanenkaTokens.of(context);
    final selected = themeProvider.preset;
    final isDark = themeProvider.isDarkMode;
    // 직접 만들기 현재 조합: 적용 중이면 그 값, 아니면 마지막으로 만든 조합(없으면 현재 프리셋에서 가장 가까운 칩)
    final customSpec = themeProvider.isCustom
        ? themeProvider.custom
        : (themeProvider.hasCustom
            ? themeProvider.custom
            : PanenkaCustomSpec.fromPreset(selected));

    return Scaffold(
      appBar: AppBar(
        title: const Text('색상'),
        backgroundColor: tokens.band,
        foregroundColor: tokens.bandInk,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            '카드를 누르면 앱 전체에 바로 적용됩니다. 마음에 드는 색을 고른 뒤 그냥 나가면 됩니다.',
            style: TextStyle(fontSize: 13, color: tokens.mute, height: 1.5),
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.35,
            ),
            // 프리셋 7종 + 마지막 칸 '직접 만들기' 카드 (2열 격자 8칸을 꼭 채움)
            itemCount: kPanenkaPresets.length + 1,
            itemBuilder: (context, i) {
              if (i == kPanenkaPresets.length) {
                return _PresetCard(
                  preset: customSpec.toPreset(),
                  selected: themeProvider.isCustom,
                  onTap: () => themeProvider.setCustom(customSpec),
                );
              }
              final p = kPanenkaPresets[i];
              return _PresetCard(
                preset: p,
                selected: p.id == selected.id,
                onTap: () => themeProvider.setPreset(p),
              );
            },
          ),
          const SizedBox(height: 22),
          // ── 직접 만들기 (2단계): 위 격자 마지막 카드와 연결 ──
          Text('직접 만들기',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: tokens.ink)),
          const SizedBox(height: 6),
          Text(
            '띠색과 강조색은 색조만 고르고, 진하기·밝기는 프리셋과 같게 맞춰 드립니다. 승·패는 어울리는 짝으로 고릅니다. 칩을 누르면 바로 적용되고, 위 격자의 마지막 카드에 내 조합이 표시됩니다.',
            style: TextStyle(fontSize: 12, color: tokens.mute, height: 1.5),
          ),
          const SizedBox(height: 10),
          _CustomBuilderCard(
            spec: customSpec,
            active: themeProvider.isCustom,
            onChanged: (spec) => themeProvider.setCustom(spec),
          ),
          const SizedBox(height: 18),
          // 다크·라이트 전환 (기존 '테마' 스위치와 같은 동작 — 색을 고르며 바로 확인용)
          Card(
            child: SwitchListTile(
              dense: true,
              secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode,
                  size: 20, color: Theme.of(context).colorScheme.primary),
              title: const Text('다크 모드', style: TextStyle(fontSize: 14)),
              subtitle: Text(
                isDark ? '어두운 바탕에 프리셋 색 그대로' : '밝은 바탕에 띠·강조색만 얹음',
                style: TextStyle(fontSize: 11.5, color: tokens.mute),
              ),
              value: isDark,
              onChanged: (_) => themeProvider.toggleTheme(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '순위 배지의 금·은·동, 선수 등급, 티어 로고처럼 뜻이 정해진 색은 프리셋과 상관없이 그대로 유지됩니다.',
            style: TextStyle(fontSize: 11.5, color: tokens.mute, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// 프리셋 카드 — 위쪽 색 띠(카드 6 : 띠 3 : 강조 1) + 이름·설명 + 선택 표시
class _PresetCard extends StatelessWidget {
  final PanenkaPreset preset;
  final bool selected;
  final VoidCallback onTap;

  const _PresetCard({
    Key? key,
    required this.preset,
    required this.selected,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tokens = PanenkaTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 미리보기 띠는 이 카드의 프리셋 값(다크 기준)을 그대로 보여준다
    final borderColor = selected
        ? tokens.accentInk
        : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08));

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: tokens.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    Expanded(flex: 6, child: Container(color: preset.card)),
                    Expanded(flex: 3, child: Container(color: preset.band)),
                    Expanded(flex: 1, child: Container(color: preset.accent)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(preset.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: tokens.ink)),
                ),
                if (selected)
                  Icon(Icons.check_circle, size: 16, color: tokens.accentInk),
              ],
            ),
            const SizedBox(height: 2),
            Text(preset.note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: tokens.mute)),
          ],
        ),
      ),
    );
  }
}

/// 직접 만들기 카드 — 미리보기 띠 + 띠색 칩 줄 + 강조색 칩 줄 + 승/패 짝 칩 줄
class _CustomBuilderCard extends StatelessWidget {
  final PanenkaCustomSpec spec;
  final bool active;
  final ValueChanged<PanenkaCustomSpec> onChanged;

  const _CustomBuilderCard({
    Key? key,
    required this.spec,
    required this.active,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tokens = PanenkaTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final preview = spec.toPreset();
    final borderColor = active
        ? tokens.accentInk
        : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: active ? 2 : 1),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 미리보기: 프리셋 카드와 같은 비율(카드 6 : 띠 3 : 강조 1) + 승/패 점
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        Expanded(flex: 6, child: Container(color: preview.card)),
                        Expanded(flex: 3, child: Container(color: preview.band)),
                        Expanded(flex: 1, child: Container(color: preview.accent)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _Dot(color: preview.win, label: '승', ink: tokens.mute),
              const SizedBox(width: 6),
              _Dot(color: preview.lose, label: '패', ink: tokens.mute),
              if (active) ...[
                const SizedBox(width: 10),
                Icon(Icons.check_circle, size: 16, color: tokens.accentInk),
              ],
            ],
          ),
          const SizedBox(height: 12),
          _ChipRow(
            label: '띠색',
            children: [
              for (final h in kPanenkaHueChips)
                _HueChip(
                  color: panenkaBandChip(h),
                  selected: active && spec.bandHue == h,
                  onTap: () => onChanged(spec.copyWith(bandHue: h)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _ChipRow(
            label: '강조색',
            children: [
              for (final h in kPanenkaHueChips)
                _HueChip(
                  color: panenkaAccentChip(h),
                  selected: active && spec.accentHue == h,
                  onTap: () => onChanged(spec.copyWith(accentHue: h)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _ChipRow(
            label: '승 · 패',
            children: [
              for (var i = 0; i < kPanenkaWinLosePairs.length; i++)
                _PairChip(
                  pair: kPanenkaWinLosePairs[i],
                  selected: active && spec.pairIndex == i,
                  onTap: () => onChanged(spec.copyWith(pairIndex: i)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            active
                ? '${spec.pair.name} · 바탕·카드·경기 중 띠는 띠색에서 자동으로 맞춰졌습니다'
                : '칩을 하나 누르면 지금 프리셋을 바탕으로 직접 만들기가 시작됩니다',
            style: TextStyle(fontSize: 11, color: tokens.mute, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// 라벨 + 가로 스크롤 칩 줄 (좁은 화면에서도 한 줄 유지)
class _ChipRow extends StatelessWidget {
  final String label;
  final List<Widget> children;
  const _ChipRow({Key? key, required this.label, required this.children})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tokens = PanenkaTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 44,
          child: Text(label,
              style: TextStyle(fontSize: 12, color: tokens.mute)),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 단색 칩 — 선택 시 본문 글자색 테두리(어떤 칩 색에서도 보이도록 칩과 띄운 링)
class _HueChip extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _HueChip(
      {Key? key, required this.color, required this.selected, required this.onTap})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tokens = PanenkaTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: selected ? tokens.ink : Colors.transparent, width: 2),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: tokens.lineStrong, width: 1),
          ),
        ),
      ),
    );
  }
}

/// 승/패 짝 칩 — 왼쪽 반은 승, 오른쪽 반은 패
class _PairChip extends StatelessWidget {
  final PanenkaWinLosePair pair;
  final bool selected;
  final VoidCallback onTap;
  const _PairChip(
      {Key? key, required this.pair, required this.selected, required this.onTap})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tokens = PanenkaTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: pair.name,
        child: Container(
          width: 30,
          height: 30,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: selected ? tokens.ink : Colors.transparent, width: 2),
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: tokens.lineStrong, width: 1),
            ),
            child: ClipOval(
              child: Row(
                children: [
                  Expanded(child: Container(color: pair.win)),
                  Expanded(child: Container(color: pair.lose)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 미리보기용 작은 색 점 + 글자
class _Dot extends StatelessWidget {
  final Color color;
  final String label;
  final Color ink;
  const _Dot({Key? key, required this.color, required this.label, required this.ink})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11, color: ink)),
      ],
    );
  }
}
