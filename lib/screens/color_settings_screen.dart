import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

/// 더보기 › 색상 — 프리셋 카드를 누르면 앱 전체에 즉시 적용·자동 저장 (2026-09-04).
/// 색상환·슬라이더 없이 카드 선택만 노출한다 (사용자 요구: 어렵지 않게).
class ColorSettingsScreen extends StatelessWidget {
  const ColorSettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final tokens = PanenkaTokens.of(context);
    final selected = themeProvider.preset;
    final isDark = themeProvider.isDarkMode;

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
            itemCount: kPanenkaPresets.length,
            itemBuilder: (context, i) {
              final p = kPanenkaPresets[i];
              return _PresetCard(
                preset: p,
                selected: p.id == selected.id,
                onTap: () => themeProvider.setPreset(p),
              );
            },
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
