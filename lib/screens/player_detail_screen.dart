import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/foot_stat.dart';
import '../models/work_rate.dart';
import '../providers/theme_provider.dart';
import '../services/error_reporter.dart';
import '../services/favorite_player_store.dart';
import '../services/ovr_formula.dart';
import '../services/player_api.dart';
import '../services/player_calc.dart';
import '../utils/fc_format.dart';
import '../widgets/badges.dart';
import '../widgets/face_image.dart';
import '../widgets/foot_badge.dart';
import '../widgets/pill_tabs.dart';
import '../widgets/player_card_controls.dart';
import '../widgets/player_list_row.dart';
import 'training_calc_screen.dart';

/// 선수 상세 (2026-09-30 시안 확정).
///
/// 목록에서 상세 버튼으로 들어온다. 강화·적응도·팀컬러를 바꾸면 능력치가 바로 다시 계산되고,
/// 특성·시세·클럽 경력은 탭으로 본다. '다른 선수와 비교'를 누르면 `'compare'`를 돌려주며 닫힌다
/// (목록이 이 선수를 비교 첫 번째로 고정한다).
class PlayerDetailScreen extends StatefulWidget {
  const PlayerDetailScreen({super.key, required this.row, this.grade = 1});

  /// 검색 결과 줄 (spid·name·positions·each_price 등)
  final Map<String, dynamic> row;

  /// 목록에서 보고 있던 강화 기준
  final int grade;

  @override
  State<PlayerDetailScreen> createState() => _PlayerDetailScreenState();
}

class _PlayerDetailScreenState extends State<PlayerDetailScreen> {
  static const _periods = [7, 30, 90, 180, 365];

  late final PlayerCardState _card;
  int _tab = 0;
  bool _loading = true;
  String? _error;

  // 시세 그래프: 강화 단계별로 받아 보관
  final Map<int, Map<String, dynamic>?> _history = {};
  bool _historyLoading = false;
  int _period = 1; // _periods의 위치 (기본 30일)

  @override
  void initState() {
    super.initState();
    ErrorReporter.currentScreen = '선수 상세';
    _card = PlayerCardState((widget.row['spid'] as num).toInt(), grade: widget.grade);
    FavoritePlayerStore.ensureLoaded();
    _load();
  }

  Future<void> _load() async {
    try {
      await OvrFormula.ensureLoaded();
      final d = await PlayerApi.detail([_card.spid]);
      if (!mounted) return;
      final data = d[_card.spid];
      if (data == null) throw Exception('세부 능력치를 가져오지 못했습니다.');
      setState(() {
        _card.apply(data);
        _loading = false;
      });
      await _card.loadTcOptions();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _ensureHistory() async {
    final g = _card.grade;
    if (_history.containsKey(g) || _historyLoading) return;
    setState(() => _historyLoading = true);
    final h = await PlayerApi.priceHistory(_card.spid, g);
    if (!mounted) return;
    setState(() {
      _history[g] = h;
      _historyLoading = false;
    });
  }

  void _changed() {
    setState(() {});
    if (_tab == 2) _ensureHistory();
  }

  /// 표시할 포지션: 검색 결과 줄의 포지션(없으면 카드 주포지션)
  List<String> get _positions {
    final list = [for (final p in (widget.row['positions'] as List? ?? const [])) if (p is Map) '${p['pos']}'];
    if (list.isNotEmpty) return list;
    final main = '${_card.data?['position'] ?? ''}';
    return main.isEmpty ? const [] : [main];
  }

  Future<void> _toggleFavorite() async {
    final messenger = ScaffoldMessenger.of(context);
    if (FavoritePlayerStore.contains(_card.spid)) {
      await FavoritePlayerStore.remove(_card.spid);
    } else {
      final ok = await FavoritePlayerStore.add(widget.row);
      if (!ok) {
        messenger.showSnackBar(
            const SnackBar(content: Text('관심선수는 ${FavoritePlayerStore.max}명까지 등록할 수 있습니다.')));
      }
    }
    if (mounted) setState(() {});
  }

  void _openTraining() {
    final d = _card.data ?? widget.row;
    final preset = <String, List<int>>{
      for (final e in _card.tcSel.entries)
        if (e.value != null) e.key: [e.value!.tcId, e.value!.level],
    };
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TrainingCalcScreen(
        spid: _card.spid,
        name: '${d['name'] ?? ''}',
        grade: _card.grade,
        tcPreset: preset.isEmpty ? null : preset,
        role: _positions.isEmpty ? null : _positions.first.toLowerCase(),
        faceUrl: (d['face_url'] ?? widget.row['face_url'])?.toString(),
        season: widget.row['season_img']?.toString(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PanenkaTokens.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('선수 상세'),
        actions: [
          ValueListenableBuilder<List<Map<String, dynamic>>>(
            valueListenable: FavoritePlayerStore.players,
            builder: (context, _, __) {
              final on = FavoritePlayerStore.contains(_card.spid);
              return IconButton(
                tooltip: on ? '관심선수 해제' : '관심선수 등록',
                onPressed: _toggleFavorite,
                icon: Icon(on ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: on ? const Color(0xFFE8C66A) : null),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
        children: [
          _header(tokens),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: StepperField(
                      label: '강화',
                      value: _card.grade,
                      min: 1,
                      max: 13,
                      suffix: '강',
                      onChanged: (v) {
                        _card.grade = v;
                        _changed();
                      })),
              const SizedBox(width: 8),
              Expanded(
                  child: StepperField(
                      label: '적응도',
                      value: _card.adap,
                      min: 1,
                      max: 5,
                      onChanged: (v) {
                        _card.adap = v;
                        _changed();
                      })),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < kTcSections.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                    child: TcField(
                        state: _card, section: kTcSections[i][0], label: kTcSections[i][1], onChanged: _changed)),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.pop(context, 'compare'),
                  icon: const Icon(Icons.compare_arrows, size: 18),
                  label: const Text('다른 선수와 비교'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openTraining,
                  icon: const Icon(Icons.fitness_center, size: 17),
                  label: const Text('집훈 계산'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PillTabs(
            labels: const ['능력치', '특성', '시세', '클럽 경력'],
            selectedIndex: _tab,
            onSelected: (i) {
              setState(() => _tab = i);
              if (i == 2) _ensureHistory();
            },
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: tokens.mute)))
          else
            ...switch (_tab) {
              1 => _traitsTab(tokens),
              2 => _priceTab(tokens),
              3 => _careerTab(tokens),
              _ => _statsTab(tokens),
            },
        ],
      ),
    );
  }

  // ── 머리: 얼굴·시즌·이름·포지션별 OVR + 기본 정보 8칸 ──
  Widget _header(PanenkaTokens tokens) {
    final row = widget.row;
    final d = _card.data ?? const <String, dynamic>{};
    final ovrs = _card.ready
        ? _card.ovrsFor(_positions)
        : PlayerCalc.shownPositions(row['positions'] as List?, _card.grade);
    final traits = [
      for (final t in ((d['traits'] ?? row['new_traits']) as List? ?? const []))
        if (t is Map && (t['is_new'] == true || d['traits'] == null)) t
    ];
    final height = d['height'] ?? row['height'];
    final weight = d['weight'] ?? row['weight'];
    final skill = (d['skill_move'] as num?)?.toInt();
    final price = _card.price ?? PlayerCalc.priceAt(row['each_price']?.toString(), _card.grade);

    Widget kv(String k, String v) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k, style: TextStyle(fontSize: 10, color: tokens.mute)),
            Text(v,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        );

    final cells = [
      kv('국적', '${(d['nation'] as Map?)?['name'] ?? '-'}'),
      kv('생년월일', '${d['birth'] ?? '-'}'),
      kv('키 · 몸무게', height == null ? '-' : '$height · ${weight ?? '-'}'),
      kv('체형', '${d['body_type'] ?? '-'}'),
      kv('개인기', skill == null ? '-' : '$skill성'),
      kv('명성', '${d['reputation'] ?? '-'}'),
      kv('급여', '${d['pay'] ?? row['pay'] ?? '-'}'),
      kv('시세 (${_card.grade}강)', price == null ? '-' : formatBp(price)),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Row(
            children: [
              ClipOval(
                child: Container(
                  color: tokens.soft,
                  child: FaceImage(
                      url: (d['face_url'] ?? row['face_url'])?.toString(),
                      spid: _card.spid,
                      width: 64,
                      height: 64,
                      fallback: Icon(Icons.person, size: 42, color: tokens.mute)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      SeasonBadge(spid: _card.spid, height: 15, fallbackText: row['season_img']?.toString()),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text('${d['name'] ?? row['name'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    PositionOvrLine(items: ovrs, ovrSize: 18),
                    const SizedBox(height: 5),
                    Row(children: [
                      NewTraitIcons(traits: traits, size: 15),
                      if (traits.isNotEmpty) const SizedBox(width: 5),
                      WorkRateIcon(workrate: WorkRate.fromJson(d['workrate'] ?? row['workrate']), size: 15),
                      const SizedBox(width: 6),
                      FeetIcon(foot: FootStat.fromJson(d['foot'] ?? row['foot']), height: 19),
                    ]),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var r = 0; r < 2; r++) ...[
            if (r > 0) const SizedBox(height: 10),
            Row(children: [
              for (var c = 0; c < 4; c++) Expanded(child: cells[r * 4 + c]),
            ]),
          ],
        ],
      ),
    );
  }

  // ── 능력치 탭: 6개 묶음 + 총 능력치 + 세부 34종 (두 칸) ──
  List<Widget> _statsTab(PanenkaTokens tokens) {
    final eff = _card.eff;
    final face = PlayerCalc.faceStats(eff);
    const mono = [FontFeature.tabularFigures()];
    final keys = [for (final k in OvrFormula.statKeys) if (eff.containsKey(k)) k];
    final half = (keys.length + 1) ~/ 2;

    Widget cell(String k) {
      final v = (eff[k] ?? 0).round();
      return Container(
        height: 28,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tokens.line))),
        child: Row(
          children: [
            Expanded(child: Text(k, style: TextStyle(fontSize: 12, color: tokens.mute))),
            Text('$v',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    fontFeatures: mono,
                    color: v >= 125 ? tokens.accentInk : (v >= 100 ? null : tokens.mute))),
          ],
        ),
      );
    }

    return [
      Row(
        children: [
          for (var i = 0; i < PlayerCalc.faceOrder.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration:
                    BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(10)),
                child: Column(children: [
                  Text(PlayerCalc.faceOrder[i], style: TextStyle(fontSize: 11, color: tokens.mute)),
                  Text('${face[PlayerCalc.faceOrder[i]] ?? 0}',
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, fontFeatures: mono)),
                ]),
              ),
            ),
          ],
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 4),
        child: Row(
          children: [
            Expanded(child: Text('총 능력치', style: TextStyle(fontSize: 12, color: tokens.mute))),
            Text('${PlayerCalc.totalStats(eff)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, fontFeatures: mono)),
          ],
        ),
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Column(children: [for (final k in keys.take(half)) cell(k)])),
          const SizedBox(width: 18),
          Expanded(child: Column(children: [for (final k in keys.skip(half)) cell(k)])),
        ],
      ),
    ];
  }

  // ── 특성 탭: 아이콘 타일 (금색 = 신규특성) ──
  List<Widget> _traitsTab(PanenkaTokens tokens) {
    final traits = [for (final t in (_card.data?['traits'] as List? ?? const [])) if (t is Map) t];
    if (traits.isEmpty) {
      return [
        Padding(
            padding: const EdgeInsets.all(24),
            child: Text('특성 없음', textAlign: TextAlign.center, style: TextStyle(color: tokens.mute)))
      ];
    }
    return [
      GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1.15,
        children: [for (final t in traits) TraitTile(name: '${t['name'] ?? ''}', icon: t['icon']?.toString())],
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6, left: 2),
        child: Text('금색 아이콘은 신규특성입니다', style: TextStyle(fontSize: 11, color: tokens.mute)),
      ),
    ];
  }

  // ── 시세 탭: 현재가 + 기간별 그래프 + 강화 단계별 현재가 ──
  List<Widget> _priceTab(PanenkaTokens tokens) {
    final g = _card.grade;
    final h = _history[g];
    final eachPrice = (_card.data?['each_price'] ?? widget.row['each_price'])?.toString();
    final current = (h?['current'] as num?)?.toInt() ?? PlayerCalc.priceAt(eachPrice, g);

    Widget chart() {
      if (_historyLoading && !_history.containsKey(g)) {
        return const SizedBox(height: 150, child: Center(child: CircularProgressIndicator()));
      }
      final times = [for (final t in (h?['times'] as List? ?? const [])) '$t'];
      final values = [for (final v in (h?['values'] as List? ?? const [])) (v as num).toDouble()];
      if (times.isEmpty || times.length != values.length) {
        return SizedBox(
            height: 150,
            child: Center(child: Text('시세 기록이 없습니다', style: TextStyle(fontSize: 12, color: tokens.mute))));
      }
      final n = _periods[_period] < values.length ? _periods[_period] : values.length;
      final t = times.sublist(times.length - n), v = values.sublist(values.length - n);
      final hi = v.reduce((a, b) => a > b ? a : b), lo = v.reduce((a, b) => a < b ? a : b);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Text('최고 ', style: TextStyle(fontSize: 11, color: tokens.mute)),
            Text(formatBp(hi), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(width: 12),
            Text('최저 ', style: TextStyle(fontSize: 11, color: tokens.mute)),
            Text(formatBp(lo), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          SizedBox(
            height: 150,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: hi * 1.15,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(color: tokens.line, strokeWidth: 1),
                ),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: [for (var i = 0; i < v.length; i++) FlSpot(i.toDouble(), v[i])],
                    isCurved: false,
                    barWidth: 2,
                    color: tokens.accentInk,
                    dotData: FlDotData(show: v.length <= 10),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => [
                      for (final s in spots)
                        LineTooltipItem(
                          '${t[s.x.toInt().clamp(0, t.length - 1)]}  ${formatBp(s.y)}',
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              Text(t.first, style: TextStyle(fontSize: 10, color: tokens.mute)),
              const Spacer(),
              Text(t.last, style: TextStyle(fontSize: 10, color: tokens.mute)),
            ]),
          ),
        ],
      );
    }

    Widget gradeCell(int grade) {
      final p = PlayerCalc.priceAt(eachPrice, grade);
      return Container(
        height: 28,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tokens.line))),
        child: Row(children: [
          Expanded(
              child: Text('$grade강',
                  style: TextStyle(fontSize: 12, color: grade == g ? tokens.accentInk : tokens.mute))),
          Text(p == null ? '-' : formatBp(p),
              style: TextStyle(fontSize: 12, fontWeight: grade == g ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );
    }

    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('현재가 ($g강)', style: TextStyle(fontSize: 12, color: tokens.mute)),
          const SizedBox(width: 8),
          Text(current == null ? '-' : formatBp(current),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ],
      ),
      const SizedBox(height: 8),
      PillTabs(
        height: 34,
        labels: [for (final p in _periods) '$p일'],
        selectedIndex: _period,
        onSelected: (i) => setState(() => _period = i),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12)),
        child: chart(),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 2),
        child: Text('강화 단계별 현재가',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tokens.subInk)),
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Column(children: [for (var i = 1; i <= 7; i++) gradeCell(i)])),
          const SizedBox(width: 18),
          Expanded(child: Column(children: [for (var i = 8; i <= 13; i++) gradeCell(i)])),
        ],
      ),
    ];
  }

  // ── 클럽 경력 탭 ──
  List<Widget> _careerTab(PanenkaTokens tokens) {
    final career = [for (final c in (_card.data?['career'] as List? ?? const [])) if (c is Map) c];
    if (career.isEmpty) {
      return [
        Padding(
            padding: const EdgeInsets.all(24),
            child: Text('클럽 경력 없음', textAlign: TextAlign.center, style: TextStyle(color: tokens.mute)))
      ];
    }
    return [
      for (final c in career)
        Container(
          height: 40,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tokens.line))),
          child: Row(children: [
            SizedBox(
                width: 108,
                child: Text('${c['years'] ?? ''}',
                    style: TextStyle(
                        fontSize: 12.5, color: tokens.mute, fontFeatures: const [FontFeature.tabularFigures()]))),
            Expanded(
                child: Text('${c['club'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            if ('${c['loan'] ?? ''}'.isNotEmpty)
              Text('${c['loan']}', style: TextStyle(fontSize: 11, color: tokens.mute)),
          ]),
        ),
    ];
  }
}
