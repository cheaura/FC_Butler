import 'package:flutter/material.dart';

import '../models/foot_stat.dart';
import '../models/work_rate.dart';
import '../providers/theme_provider.dart';
import '../services/player_calc.dart';
import '../utils/fc_format.dart';
import 'badges.dart';
import 'face_image.dart';
import 'foot_badge.dart';

/// 비교 선택 상태에 따른 줄의 모습
enum PlayerCompareMode {
  /// 비교를 시작하지 않음 — 비교 버튼 기본 모양
  none,

  /// 이 줄이 비교 첫 번째 선수 — 버튼은 '선택됨'(눌리지 않음)
  picked,

  /// 첫 번째 선수가 정해진 상태의 다른 줄 — 비교 버튼 강조
  target,
}

/// 신규특성 아이콘 줄 (검색 결과 new_traits: [{name, icon}]) — 스쿼드 탭 목록과 같은 모양(남색 바탕 14px)
class NewTraitIcons extends StatelessWidget {
  const NewTraitIcons({super.key, required this.traits, this.size = 14});

  final List<dynamic>? traits;
  final double size;

  @override
  Widget build(BuildContext context) {
    final list = traits ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final t in list)
          if (t is Map)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Tooltip(
                message: '신규특성: ${t['name'] ?? ''}',
                child: Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(color: const Color(0xE61F3A5C), borderRadius: BorderRadius.circular(4)),
                  child: Image.network('${t['icon'] ?? ''}',
                      width: size, height: size, errorBuilder: (c, e, s) => SizedBox(width: size, height: size)),
                ),
              ),
            ),
      ],
    );
  }
}

/// 포지션별 OVR 한 줄 ('ST 122  LW 122')
class PositionOvrLine extends StatelessWidget {
  const PositionOvrLine({super.key, required this.items, this.ovrSize = 16});

  final List<({String pos, int ovr})> items;
  final double ovrSize;

  @override
  Widget build(BuildContext context) {
    final tokens = PanenkaTokens.of(context);
    return Wrap(
      spacing: 8,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        for (final p in items)
          Text.rich(TextSpan(children: [
            TextSpan(
                text: '${p.pos} ',
                style: TextStyle(fontSize: ovrSize * 0.7, fontWeight: FontWeight.w700, color: tokens.subInk)),
            TextSpan(
                text: '${p.ovr}',
                style: TextStyle(
                    fontSize: ovrSize,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ])),
      ],
    );
  }
}

/// 선수 검색 결과·관심선수 목록의 한 줄 (2026-09-30 시안 확정 구성).
///
/// 왼쪽 얼굴, 가운데 3줄(시즌·이름·신규특성·관심 별 / 포지션별 OVR / 급여·양발·참여도·시세),
/// 오른쪽에 상세·비교 버튼. [row]는 서버 검색 결과 한 줄이며 OVR은 0강 기준 → [grade]강 값으로 표시한다.
class PlayerListRow extends StatelessWidget {
  const PlayerListRow({
    super.key,
    required this.row,
    required this.grade,
    required this.favorite,
    required this.onDetail,
    required this.onCompare,
    required this.onFavorite,
    this.compare = PlayerCompareMode.none,
  });

  final Map<String, dynamic> row;
  final int grade;
  final bool favorite;
  final PlayerCompareMode compare;
  final VoidCallback onDetail;
  final VoidCallback onCompare;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final tokens = PanenkaTokens.of(context);
    final spid = row['spid'] as num?;
    final name = '${row['name'] ?? ''}';
    final price = PlayerCalc.priceAt(row['each_price']?.toString(), grade);
    final picked = compare == PlayerCompareMode.picked;

    final buttonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(56, 40),
      maximumSize: const Size(64, 40),
      padding: EdgeInsets.zero,
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );

    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
      decoration: BoxDecoration(
        color: picked ? tokens.accentSoft : null,
        border: Border(bottom: BorderSide(color: tokens.line)),
      ),
      child: Row(
        children: [
          ClipOval(
            child: Container(
              color: tokens.soft,
              child: FaceImage(
                  url: row['face_url']?.toString(),
                  spid: spid,
                  width: 46,
                  height: 46,
                  fallback: Icon(Icons.person, size: 30, color: tokens.mute)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    SeasonBadge(spid: spid, height: 14, fallbackText: row['season_img']?.toString()),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 5),
                    NewTraitIcons(traits: row['new_traits'] as List?),
                    const Spacer(),
                    SizedBox(
                      width: 32,
                      height: 28,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 19,
                        tooltip: favorite ? '관심선수 해제' : '관심선수 등록',
                        onPressed: onFavorite,
                        icon: Icon(favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                            color: favorite ? const Color(0xFFE8C66A) : tokens.mute),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                PositionOvrLine(items: PlayerCalc.shownPositions(row['positions'] as List?, grade)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(text: '급여 ', style: TextStyle(fontSize: 11, color: tokens.mute)),
                      TextSpan(
                          text: '${row['pay'] ?? '-'}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ])),
                    const SizedBox(width: 8),
                    FeetIcon(foot: FootStat.fromJson(row['foot']), height: 16),
                    const SizedBox(width: 6),
                    WorkRateIcon(workrate: WorkRate.fromJson(row['workrate']), size: 13),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(price == null ? '-' : formatBp(price),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(style: buttonStyle, onPressed: onDetail, child: const Text('상세')),
              const SizedBox(height: 4),
              if (compare == PlayerCompareMode.target)
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(56, 40),
                    maximumSize: const Size(64, 40),
                    padding: EdgeInsets.zero,
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: onCompare,
                  child: const Text('비교'),
                )
              else
                OutlinedButton(
                  style: buttonStyle.copyWith(
                    foregroundColor: WidgetStatePropertyAll(picked ? tokens.mute : tokens.accentInk),
                    side: WidgetStatePropertyAll(
                        BorderSide(color: picked ? tokens.line : tokens.accentInk.withOpacity(.45))),
                  ),
                  onPressed: picked ? null : onCompare,
                  child: Text(picked ? '선택됨' : '비교'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
