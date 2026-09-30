import 'package:flutter/material.dart';

import '../providers/theme_provider.dart';
import '../services/player_api.dart';
import '../services/player_calc.dart';
import 'tc_picker.dart';

/// 팀컬러 3칸의 이름 (집훈 계산기와 같은 순서·이름)
const kTcSections = [
  ['enhance', '강화 팀컬러'],
  ['affiliation', '소속 팀컬러'],
  ['feature', '특성 팀컬러'],
];

/// 선수 카드 1장의 조절 상태 (강화·적응도·팀컬러) + 서버에서 받은 카드 정보.
///
/// 선수 상세 화면은 1개, 비교 팝업은 2개를 쓴다. 계산은 [PlayerCalc] (집훈 계산식과 같음).
class PlayerCardState {
  PlayerCardState(this.spid, {this.grade = 1, this.adap = 1});

  final int spid;
  int grade;
  int adap;

  /// 서버 `/api/user/player/detail`의 카드 정보 (받기 전에는 null)
  Map<String, dynamic>? data;

  /// 세부 능력 34종 (0강 기준)
  Map<String, int>? base;

  Map<String, List<Map<String, dynamic>>> tcOptions = {'enhance': [], 'affiliation': [], 'feature': []};
  final Map<String, TcPick?> tcSel = {'enhance': null, 'affiliation': null, 'feature': null};
  bool tcLoading = false;

  bool get ready => base != null;

  void apply(Map<String, dynamic> d) {
    data = d;
    final stats = <String, int>{};
    (d['stats'] as Map? ?? {}).forEach((k, v) => stats['$k'] = (v as num).toInt());
    base = stats.isEmpty ? null : stats;
  }

  Iterable<TcPick> get picks => tcSel.values.whereType<TcPick>();

  /// 강화·적응도·팀컬러를 반영한 세부 능력치
  Map<String, num> get eff => PlayerCalc.effStats(base ?? const {}, grade: grade, adap: adap, picks: picks);

  /// [positions](대문자 포지션 목록)의 현재 조건 OVR
  List<({String pos, int ovr})> ovrsFor(Iterable<String> positions) {
    final e = eff;
    return [for (final p in positions) (pos: p.toUpperCase(), ovr: PlayerCalc.ovr(e, p.toLowerCase()))];
  }

  /// 현재 강화 단계의 시세 (없으면 null)
  int? get price => PlayerCalc.priceAt(data?['each_price']?.toString(), grade);

  /// 카드가 고를 수 있는 팀컬러 목록을 받는다 (실패해도 빈 목록으로 동작)
  Future<void> loadTcOptions() async {
    tcLoading = true;
    try {
      tcOptions = await PlayerApi.cardTeamcolors(spid);
    } catch (e) {
      print('[PlayerCardState] 팀컬러 목록 실패: $e');
    } finally {
      tcLoading = false;
    }
  }

  /// 팀컬러 요약 ('선택 안 함' / 'Lv2. 토트넘 홋스퍼 외 1')
  String get tcSummary {
    final p = picks.toList();
    if (p.isEmpty) return '선택 안 함';
    final first = 'Lv${p.first.level}. ${p.first.name}';
    return p.length == 1 ? first : '$first 외 ${p.length - 1}';
  }
}

/// − 값 + 조절 칸 (강화·적응도)
class StepperField extends StatelessWidget {
  const StepperField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.suffix = '',
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = PanenkaTokens.of(context);
    Widget btn(IconData icon, String tip, bool enabled, VoidCallback onTap) => SizedBox(
          width: 36,
          height: 36,
          child: IconButton(
            padding: EdgeInsets.zero,
            iconSize: 18,
            tooltip: tip,
            onPressed: enabled ? onTap : null,
            icon: Icon(icon),
          ),
        );
    return Container(
      height: 36,
      decoration: BoxDecoration(color: tokens.soft, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          btn(Icons.remove, '$label 낮추기', value > min, () => onChanged(value - 1)),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '$label ', style: TextStyle(fontSize: 11.5, color: tokens.mute)),
                TextSpan(text: '$value$suffix', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              ]),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          btn(Icons.add, '$label 높이기', value < max, () => onChanged(value + 1)),
        ],
      ),
    );
  }
}

/// 팀컬러 칸 1개 (누르면 선택 시트) — 집훈 계산기의 칸과 같은 모양
class TcField extends StatelessWidget {
  const TcField({super.key, required this.state, required this.section, required this.label, required this.onChanged});

  final PlayerCardState state;
  final String section;
  final String label;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = PanenkaTokens.of(context);
    final muted = tokens.mute;
    final pick = state.tcSel[section];
    final count = (state.tcOptions[section] ?? const []).length;
    final empty = pick == null;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: state.tcLoading || count == 0 ? null : () => _open(context),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 5, 6, 5),
        decoration: BoxDecoration(
          border: Border.all(color: empty ? muted.withOpacity(.4) : tokens.accentInk.withOpacity(.55)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 9.5, color: muted)),
                  Text(
                    state.tcLoading
                        ? '불러오는 중'
                        : count == 0
                            ? '해당 없음'
                            : empty
                                ? '—'
                                : 'Lv${pick.level}. ${pick.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: empty ? FontWeight.w500 : FontWeight.w700,
                        color: count == 0 ? muted : null),
                  ),
                ],
              ),
            ),
            Icon(Icons.expand_more, size: 14, color: muted),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<TcPick?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => TcSheet(
        title: label,
        items: state.tcOptions[section] ?? const [],
        section: section,
        current: state.tcSel[section],
        grade: state.grade,
      ),
    );
    if (picked == null) return;
    state.tcSel[section] = picked.tcId == 0 ? null : picked;
    onChanged();
  }
}

/// 팀컬러 3칸을 한 줄 요약으로 접은 칸 (비교 팝업의 좁은 칸용) — 누르면 3칸이 든 시트가 열린다
class TcSummaryField extends StatelessWidget {
  const TcSummaryField({super.key, required this.state, required this.onChanged});

  final PlayerCardState state;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = PanenkaTokens.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Theme.of(context).cardColor,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheet) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${state.data?['name'] ?? ''} 팀컬러',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  for (final s in kTcSections) ...[
                    TcField(
                        state: state,
                        section: s[0],
                        label: s[1],
                        onChanged: () {
                          setSheet(() {});
                          onChanged();
                        }),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: tokens.soft, borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Text('팀컬러 ', style: TextStyle(fontSize: 11.5, color: tokens.mute)),
            Expanded(
              child: Text(state.tcLoading ? '불러오는 중' : state.tcSummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            Icon(Icons.expand_more, size: 14, color: tokens.mute),
          ],
        ),
      ),
    );
  }
}

/// 특성 타일 (아이콘 위·이름 아래 — 2026-09-30 시안 확정). 금색 육각 = 신규특성, 회색 = 일반 (넥슨 아이콘 그대로).
class TraitTile extends StatelessWidget {
  const TraitTile({
    super.key,
    required this.name,
    required this.icon,
    this.iconSize = 28,
    this.fontSize = 11,
    this.selected = false,
    this.excluded = false,
    this.onTap,
  });

  final String name;
  final String? icon;
  final double iconSize;
  final double fontSize;

  /// 조건 시트: 보유 조건으로 선택됨
  final bool selected;

  /// 조건 시트: 제외 조건으로 선택됨
  final bool excluded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = PanenkaTokens.of(context);
    final on = selected || excluded;
    final ring = excluded ? tokens.loseInk : tokens.accentInk;
    final body = Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 6),
      decoration: BoxDecoration(
        color: on ? ring.withOpacity(.14) : null,
        border: Border.all(color: on ? ring.withOpacity(.75) : Colors.transparent),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if ((icon ?? '').isNotEmpty)
            Image.network(icon!,
                width: iconSize,
                height: iconSize,
                errorBuilder: (c, e, s) => Icon(Icons.hexagon_outlined, size: iconSize, color: tokens.mute))
          else
            Icon(Icons.hexagon_outlined, size: iconSize, color: tokens.mute),
          const SizedBox(height: 4),
          Text(name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: fontSize,
                  height: 1.25,
                  fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                  decoration: excluded ? TextDecoration.lineThrough : null)),
        ],
      ),
    );
    if (onTap == null) return body;
    return InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: body);
  }
}
