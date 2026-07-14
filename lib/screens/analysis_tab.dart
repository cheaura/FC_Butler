// 전적 분석 리포트 탭 (2026-07-14) — 웹 대시보드 전적 분석 섹션의 모바일 버전
// 자동 실행 없음: [분석하기] 버튼으로만 실행. 서버 API는 웹과 동일.
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AnalysisTab extends StatefulWidget {
  final String username;

  const AnalysisTab({Key? key, required this.username}) : super(key: key);

  @override
  State<AnalysisTab> createState() => _AnalysisTabState();
}

class _AnalysisTabState extends State<AnalysisTab> with AutomaticKeepAliveClientMixin {
  final ApiService _api = ApiService();

  // 범위 선택
  String _scopeType = 'count'; // count | period
  int _count = 100;
  DateTime _dateFrom = DateTime.now().subtract(const Duration(days: 7));
  DateTime _dateTo = DateTime.now();

  // 진행 상태
  bool _running = false;
  String _statusText = '';
  Timer? _pollTimer;

  // 결과
  Map<String, dynamic>? _result;
  String? _error;

  // 지난 분석
  Map<String, dynamic>? _latest;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadLatest();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLatest() async {
    final res = await _api.getLatestAnalysis(widget.username);
    if (!mounted) return;
    if (res['success'] == true && res['exists'] == true) {
      setState(() => _latest = res);
    }
  }

  Map<String, dynamic> _currentScope() {
    if (_scopeType == 'count') return {'type': 'count', 'count': _count};
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return {'type': 'period', 'from': fmt(_dateFrom), 'to': fmt(_dateTo)};
  }

  Future<void> _start() async {
    _pollTimer?.cancel();
    setState(() {
      _running = true;
      _statusText = '분석 요청 중...';
      _result = null;
      _error = null;
    });
    final res = await _api.startMatchAnalysis(widget.username, _currentScope());
    if (!mounted) return;
    if (res['success'] != true) {
      setState(() {
        _running = false;
        _error = res['error']?.toString() ?? '분석 요청 실패';
      });
      return;
    }
    if (res['status'] == 'insufficient') {
      setState(() {
        _running = false;
        _error = '분석에는 최소 ${res['min_required']}경기가 필요합니다 (현재 서버에 ${res['have']}경기).';
      });
      return;
    }
    if (res['status'] == 'done') {
      setState(() {
        _running = false;
        _result = res['result'] as Map<String, dynamic>?;
      });
      return;
    }
    // queued → 폴링 (첫 분석은 랭커 수집 포함 최대 1분 이상 걸릴 수 있음)
    final jobId = res['job_id']?.toString() ?? '';
    setState(() => _statusText = '분석 대기 중...');
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll(jobId));
  }

  Future<void> _poll(String jobId) async {
    final res = await _api.getAnalysisStatus(jobId);
    if (!mounted) return;
    if (res['success'] != true) {
      _pollTimer?.cancel();
      setState(() {
        _running = false;
        _error = res['error']?.toString() ?? '상태 조회 실패';
      });
      return;
    }
    final status = res['status']?.toString();
    if (status == 'queued') {
      setState(() => _statusText = '분석 대기 중... (순번 ${res['position'] ?? 1})');
    } else if (status == 'running') {
      setState(() => _statusText = '분석 실행 중... (첫 분석은 1분 정도 걸릴 수 있습니다)');
    } else if (status == 'done') {
      _pollTimer?.cancel();
      final r = await _api.getAnalysisResult(jobId);
      if (!mounted) return;
      setState(() {
        _running = false;
        if (r['success'] == true) {
          _result = r['result'] as Map<String, dynamic>?;
        } else {
          _error = r['error']?.toString() ?? '결과 조회 실패';
        }
      });
    } else if (status == 'error') {
      _pollTimer?.cancel();
      setState(() {
        _running = false;
        _error = '분석 중 오류: ${res['error'] ?? '알 수 없는 오류'}';
      });
    }
  }

  // ── 렌더링 ──

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildScopeSelector(),
        const SizedBox(height: 8),
        if (_running)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(_statusText, style: const TextStyle(fontSize: 13)),
            ]),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Icon(Icons.warning_amber, size: 32, color: Colors.orange),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
            ]),
          )
        else if (_result != null)
          ..._buildResult(_result!)
        else
          _buildEmpty(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildScopeSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              for (final t in const [
                ['count', '경기 수'],
                ['period', '기간'],
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(t[1], style: const TextStyle(fontSize: 12)),
                    selected: _scopeType == t[0],
                    onSelected: (_) => setState(() => _scopeType = t[0]),
                  ),
                ),
            ]),
            const SizedBox(height: 6),
            if (_scopeType == 'count')
              Wrap(
                spacing: 6,
                children: [
                  for (final c in const [50, 100, 300, 500, 1000, 3000])
                    ChoiceChip(
                      label: Text(c == 3000 ? '전체(최대 3000)' : '$c',
                          style: const TextStyle(fontSize: 12)),
                      selected: _count == c,
                      onSelected: (_) => setState(() => _count = c),
                    ),
                ],
              )
            else
              Row(children: [
                Expanded(child: _dateButton(true)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('~')),
                Expanded(child: _dateButton(false)),
              ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _running ? null : _start,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('분석하기'),
                ),
              ),
            ]),
            if (_latest != null && _result == null && !_running)
              TextButton(
                onPressed: () => setState(() => _result = _latest!['result'] as Map<String, dynamic>?),
                child: Text('지난 분석 열기 (${_scopeLabel(_latest!['scope'])})',
                    style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  String _scopeLabel(dynamic scope) {
    if (scope is Map) {
      if (scope['type'] == 'count') return '최근 ${scope['count']}경기';
      return '${scope['from']} ~ ${scope['to']}';
    }
    return '';
  }

  Widget _dateButton(bool isFrom) {
    final d = isFrom ? _dateFrom : _dateTo;
    return OutlinedButton(
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: d,
          firstDate: DateTime(2025, 1, 1),
          lastDate: DateTime.now(),
        );
        if (picked != null) {
          setState(() {
            if (isFrom) {
              _dateFrom = picked;
            } else {
              _dateTo = picked;
            }
          });
        }
      },
      child: Text('${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(children: [
        Icon(Icons.pie_chart, size: 40, color: Theme.of(context).hintColor),
        const SizedBox(height: 8),
        const Text('분석 범위를 선택하고 [분석하기]를 누르면\n경기 내용·선수 퍼포먼스 리포트가 표시됩니다.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
      ]),
    );
  }

  List<Widget> _buildResult(Map<String, dynamic> r) {
    if (r['insufficient'] == true) {
      return [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text('분석에는 최소 ${r['min_required']}경기가 필요합니다 (유효 ${r['have']}경기).',
              textAlign: TextAlign.center),
        ),
      ];
    }
    final meta = r['meta'] as Map<String, dynamic>? ?? {};
    final summary = r['summary'] as Map<String, dynamic>? ?? {};
    final verdict = r['verdict'] as Map<String, dynamic>? ?? {};
    return [
      _buildMetaChips(meta),
      const SizedBox(height: 8),
      _buildSummaryGrid(summary, r['xg'] as Map<String, dynamic>? ?? {}),
      const SizedBox(height: 8),
      _buildVerdictCard(verdict),
      const SizedBox(height: 12),
      const Text('핵심 지표', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      Text('상대와 차이(평균) = 경기마다 (내 값 − 상대팀 값)을 평균. +면 내가 앞선 것',
          style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
      const SizedBox(height: 4),
      ...List<Map<String, dynamic>>.from(r['metrics'] ?? [])
          .where((m) => m['grade'] == 'core')
          .map(_buildMetricCard),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('보조 지표 (연관성 약함 — 참고용)', style: TextStyle(fontSize: 13)),
        children: List<Map<String, dynamic>>.from(r['metrics'] ?? [])
            .where((m) => m['grade'] == 'aux')
            .map(_buildMetricCard)
            .toList(),
      ),
      const SizedBox(height: 12),
      const Text('선수 분석', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      Text('판정: 데이터센터 랭킹 1~10,000위 랭커의 같은 포지션 카드 평점 분포 기준 (출전 30경기 이상)',
          style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
      const SizedBox(height: 4),
      ...List<Map<String, dynamic>>.from(r['players'] ?? []).map(_buildPlayerCard),
      const SizedBox(height: 12),
      _buildTacticsSection(r['tactics'] as Map<String, dynamic>?),
      const SizedBox(height: 12),
      Text('※ ${verdict['caution'] ?? ''}',
          style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
    ];
  }

  Widget _buildMetaChips(Map<String, dynamic> meta) {
    final period = (meta['period'] as List?) ?? [];
    String periodStr = '';
    if (period.length == 2) {
      periodStr =
          '${period[0].toString().substring(0, 10)} ~ ${period[1].toString().substring(0, 10)}';
    }
    final chips = <String>[
      _scopeLabel(meta['scope']),
      '분석 ${meta['matches']}경기',
      if (periodStr.isNotEmpty) periodStr,
      if ((meta['excluded_special_end'] ?? 0) > 0) '특수종료 제외 ${meta['excluded_special_end']}',
      if (meta['sample_warning'] == true) '⚠ 표본 부족 — 참고용',
      if ((meta['lineup_changes'] ?? 0) > 0)
        '라인업 변경 ${meta['lineup_changes']}회 (현재 ${meta['current_segment_matches']}경기)',
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: chips
          .where((c) => c.isNotEmpty)
          .map((c) => Chip(
                label: Text(c, style: const TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ))
          .toList(),
    );
  }

  Widget _summaryCell(String title, String main, String sub) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Text(title,
                style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(main, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            if (sub.isNotEmpty)
              Text(sub,
                  style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  String _pctText(dynamic pct) {
    if (pct == null) return '';
    final p = (pct as num).toDouble();
    return p >= 50 ? '상위 ${(100 - p).toStringAsFixed(0)}%' : '하위 ${p.toStringAsFixed(0)}%';
  }

  Widget _buildSummaryGrid(Map<String, dynamic> s, Map<String, dynamic> xg) {
    final f = s['final'] as Map<String, dynamic>? ?? {};
    final o = s['open_play'] as Map<String, dynamic>? ?? {};
    final so = s['shootout'] as Map<String, dynamic>? ?? {};
    final g = s['goals'] as Map<String, dynamic>? ?? {};
    String n(dynamic v, [int digits = 2]) =>
        v == null ? '-' : (v as num).toStringAsFixed(digits);
    final cells = [
      _summaryCell('공식 전적', '${f['W']}승 ${f['D']}무 ${f['L']}패',
          '승률 ${n((f['win_rate'] as num?) == null ? null : (f['win_rate'] as num) * 100, 1)}%'),
      _summaryCell('경기당 승점', n(f['points_per_match']), _pctText(f['points_percentile'])),
      _summaryCell('정규 득점 전적', '${o['W']}승 ${o['D']}무 ${o['L']}패', '승부차기 제외'),
      _summaryCell('승부차기', (so['matches'] ?? 0) > 0 ? '${so['W']}승 ${so['L']}패' : '없음',
          '${so['matches']}경기'),
      _summaryCell('경기당 득/실점', '${n(g['for_pm'])} / ${n(g['against_pm'])}', ''),
      _summaryCell('경기당 xG', '${n(xg['for_pm'])} / ${n(xg['against_pm'])}', '기대 득점 / 기대 실점'),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.35,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: cells,
    );
  }

  Widget _buildVerdictCard(Map<String, dynamic> v) {
    final strengths = List<String>.from(v['strengths'] ?? []);
    final weaknesses = List<String>.from(v['weaknesses'] ?? []);
    final playerLines = List<String>.from(v['player_lines'] ?? []);
    final teamFlags = List<Map<String, dynamic>>.from(v['team_flags'] ?? []);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(v['points_line']?.toString() ?? '',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            if (strengths.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('💪 강점: ${strengths.join(' · ')}', style: const TextStyle(fontSize: 12)),
            ],
            if (weaknesses.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('📉 약점: ${weaknesses.join(' · ')}', style: const TextStyle(fontSize: 12)),
            ],
            if (playerLines.isNotEmpty) ...[
              const SizedBox(height: 4),
              const Text('👥 선수:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ...playerLines.map((l) => Text('· $l', style: const TextStyle(fontSize: 12))),
            ],
            ...teamFlags.map((fl) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      '⚠ ${fl['text'] ?? ''}${(fl['suggestion'] ?? '').toString().isNotEmpty ? ' → ${fl['suggestion']}' : ''}',
                      style: const TextStyle(fontSize: 12)),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(Map<String, dynamic> m) {
    final diff = m['diff_avg'] as num?;
    final direction = (m['direction'] as num?)?.toInt() ?? 1;
    Color? diffColor;
    if (diff != null && diff != 0) {
      final good = (diff > 0) == (direction > 0);
      diffColor = good ? Colors.green : Colors.red;
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${m['label']}${direction < 0 ? ' ↓' : ''}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                Text(
                  diff == null ? '—' : '${diff > 0 ? '+' : ''}${diff.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: diffColor),
                ),
                const SizedBox(width: 8),
                Text(_pctText(m['percentile']), style: const TextStyle(fontSize: 12)),
              ],
            ),
            if ((m['guide_text'] ?? '').toString().isNotEmpty)
              Text(m['guide_text'].toString(),
                  style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
          ],
        ),
      ),
    );
  }

  Color _badgeColor(String badge) {
    switch (badge) {
      case 'red':
        return Colors.red;
      case 'orange':
        return Colors.orange;
      case 'green':
        return Colors.green;
      case 'star':
        return Colors.teal;
      case 'hold':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'up':
        return Colors.green;
      case 'down':
        return Colors.red;
      case 'even':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  Widget _buildPlayerCard(Map<String, dynamic> p) {
    final keyStats = List<String>.from(p['key_stats'] ?? []);
    final rankerCompare = (p['ranker_compare'] as List?) ?? [];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        title: Text(
          '${p['display_name']}${p['low_enhance_flag'] == true ? '  [강화↓]' : ''}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Row(
          children: [
            Text('${p['position']} · 출전 ${p['apps']} · 평점 ${p['avg_rating']}',
                style: const TextStyle(fontSize: 11)),
          ],
        ),
        trailing: Container(
          constraints: const BoxConstraints(maxWidth: 110),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: _badgeColor(p['badge']?.toString() ?? '').withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            (p['badge_text']?.toString() ?? '').split(' — ').first,
            style: TextStyle(fontSize: 10, color: _badgeColor(p['badge']?.toString() ?? '')),
            textAlign: TextAlign.center,
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('판정: ${p['badge_text'] ?? '-'}', style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                if (keyStats.isNotEmpty)
                  Text('주요 기록: ${keyStats.join(' · ')}', style: const TextStyle(fontSize: 12)),
                if (rankerCompare.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('랭커 대비:', style: TextStyle(fontSize: 12)),
                      ...rankerCompare.map((it) {
                        if (it is! Map) return Text(it.toString(), style: const TextStyle(fontSize: 12));
                        return RichText(
                          text: TextSpan(
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).textTheme.bodyMedium?.color),
                            children: [
                              TextSpan(text: '${it['label']} '),
                              TextSpan(
                                  text: '${it['my']}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _statusColor(it['status']?.toString()))),
                              TextSpan(text: '/${it['rk']}',
                                  style: const TextStyle(color: Colors.orange)),
                            ],
                          ),
                        );
                      }),
                      Text('(데이터센터 랭킹 ${p['ranker_range'] ?? ''})',
                          style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTacticsSection(Map<String, dynamic>? tac) {
    if (tac == null) return const SizedBox.shrink();
    final myForms = List<Map<String, dynamic>>.from(tac['my_formations'] ?? []);
    final vs = List<Map<String, dynamic>>.from(tac['vs_opponent_formations'] ?? []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('포메이션별 승률', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        Text('수비-수비형MF-중앙MF-공격형MF-공격 (공식 결과 기준, 5경기 이상만)',
            style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
        const SizedBox(height: 4),
        if (myForms.isNotEmpty)
          Text(
            myForms
                .map((f) =>
                    '내 포메이션 ${f['formation']}: ${f['matches']}경기 (${((f['share'] as num) * 100).toStringAsFixed(0)}%)')
                .join(' · '),
            style: const TextStyle(fontSize: 12),
          ),
        const SizedBox(height: 4),
        if (vs.isEmpty)
          const Text('표시할 포메이션 데이터가 없습니다 (5경기 미만)', style: TextStyle(fontSize: 12))
        else
          Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1.6),
              3: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                children: ['상대 포메이션', '경기', '승/무/패', '승률']
                    .map((h) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(h,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ))
                    .toList(),
              ),
              ...vs.map((t) {
                final wr = (t['win_rate'] as num).toDouble();
                final color = wr >= 0.55 ? Colors.green : (wr < 0.45 ? Colors.red : null);
                return TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(t['formation'].toString(), style: const TextStyle(fontSize: 12)),
                    ),
                    Text('${t['matches']}', style: const TextStyle(fontSize: 12)),
                    Text('${t['W']}/${t['D']}/${t['L']}', style: const TextStyle(fontSize: 12)),
                    Text('${(wr * 100).toStringAsFixed(0)}%',
                        style: TextStyle(fontSize: 12, color: color)),
                  ],
                );
              }),
            ],
          ),
      ],
    );
  }
}
