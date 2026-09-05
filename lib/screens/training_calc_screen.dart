import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../constants/positions.dart';
import '../services/api_service.dart';
import '../services/error_reporter.dart';
import '../services/ovr_formula.dart';
import '../providers/theme_provider.dart';
import '../widgets/badges.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 집훈 계산기 (집중훈련 OVR 계산) — Panenka 1.0.4 (2026-08-22).
///
/// 두 진입 경로가 같은 화면을 쓴다.
///  ① 메인 탭(asTab=true): 검색 → 시즌·주포지션·OVR 목록에서 카드 선택 → 강화·팀컬러 선택 → 계산
///  ② 스쿼드 카드에서 push: 검색 단계를 건너뛰고 카드·강화·발동 팀컬러가 채워진 채 열림 ("다른 카드"로 검색 가능)
/// 인벤 계산기와 같은 체계: 총점 = Σ(능력치×가중치) + 100×(강화+팀컬러+적응도), OVR = 총점÷100 내림,
///   오버롤 상승 필요 포인트 = 100 − 총점%100, 사용 포인트 = Σ(훈련치×가중치). 적응도 Lv.5 고정(+4).
/// 팀컬러 3칸(2026-09-04, A안): 강화(물결)·소속·특성을 각각 고르고, '전체 능력치 +N'은 전 스탯에,
///   세부 효과(예: 시야 +3)는 해당 스탯에만 더한다. 소속 안에 특성이 겹쳐 동시 적용(사용자 확인).
///   참고 앱 대조: 크바라츠헬리아 26TS RW 123→146→150→155→156 전부 일치(서버 DB 검증 09-04).
/// 집중훈련 규칙(사용자 확인): 10강 이하 능력치 5개 · 11강 이상 6개 선택, 선택한 능력치마다 +2.
class TrainingCalcScreen extends StatefulWidget {
  final bool asTab;
  final int? spid;
  final String? name;
  final String? season;
  final int grade;
  final int tcBonus;
  /// 스쿼드에서 발동 중인 팀컬러 자동 채움: {'enhance'|'affiliation'|'feature': [tc_id, level]}
  final Map<String, List<int>>? tcPreset;
  final String? role;
  final String? faceUrl;

  const TrainingCalcScreen({
    super.key,
    this.asTab = false,
    this.spid,
    this.name,
    this.season,
    this.grade = 1,
    this.tcBonus = 0,
    this.tcPreset,
    this.role,
    this.faceUrl,
  });

  @override
  State<TrainingCalcScreen> createState() => _TrainingCalcScreenState();
}

class _TrainingCalcScreenState extends State<TrainingCalcScreen> with AutomaticKeepAliveClientMixin {
  static const _adapBonus = 4; // 적응도 Lv.5 고정
  static const _trainStep = 2; // 선택 능력치 1개당 +2
  static int _trainSlots(int grade) => grade >= 11 ? 6 : 5;
  static const _groupPills = [
    ['st', 'ST'],
    ['cf', 'CF'],
    ['lw', 'LW/RW'],
    ['cam', 'CAM'],
    ['cm', 'CM'],
    ['lm', 'LM/RM'],
    ['cdm', 'CDM'],
    ['cb', 'CB'],
    ['sw', 'SW'],
    ['lb', 'LB/RB'],
    ['lwb', 'LWB/RWB'],
    ['gk', 'GK'],
  ];

  // 선택된 카드
  int? _spid;
  String _name = '';
  String _season = '';
  String? _faceUrl;
  int _grade = 1;
  int _tcLegacy = 0; // 구 경로(스쿼드 발동 '전체 +N' 합계) — 3칸을 하나도 고르지 않았을 때만 적용
  String _pos = 'st';
  // 팀컬러 3칸 (A안): 카드가 고를 수 있는 목록(서버) + 선택
  static const _tcSections = [
    ['enhance', '강화 팀컬러'],
    ['affiliation', '소속 팀컬러'],
    ['feature', '특성 팀컬러'],
  ];
  Map<String, List<Map<String, dynamic>>> _tcOptions = {'enhance': [], 'affiliation': [], 'feature': []};
  final Map<String, _TcPick?> _tcSel = {'enhance': null, 'affiliation': null, 'feature': null};
  Map<String, List<int>>? _tcPreset;
  bool _tcLoading = false;
  Map<String, int>? _base;
  final Map<String, int> _train = {};
  String? _error;
  bool _loading = false;

  // 검색
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  bool _showSearch = false;
  List<Map<String, dynamic>> _recentCards = []; // 최근 선택 카드 (검색 기록, 2026-09-05)

  @override
  bool get wantKeepAlive => widget.asTab;

  @override
  void initState() {
    super.initState();
    _showSearch = widget.asTab || widget.spid == null;
    _TrainingRecentStore.load().then((list) {
      if (mounted) setState(() => _recentCards = list);
    });
if (widget.spid != null) {
      _applyCard(
        spid: widget.spid!,
        name: widget.name ?? '',
        season: widget.season ?? '',
        grade: widget.grade,
        tc: widget.tcBonus,
        tcPreset: widget.tcPreset,
        role: widget.role,
        faceUrl: widget.faceUrl,
      );
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── 검색 ──
  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    try {
      final r = await http
          .get(Uri.parse('${ApiService.baseUrl}/api/user/squad/players?name=${Uri.encodeComponent(q)}'))
          .timeout(const Duration(seconds: 25));
      final d = json.decode(r.body);
      if (!mounted) return;
      setState(() {
        _results =
            d['success'] == true ? (d['players'] as List? ?? []).map((p) => Map<String, dynamic>.from(p)).toList() : [];
      });
    } catch (e) {
      if (mounted) setState(() => _results = []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  String _pillFor(String role) {
    final g = OvrFormula.groups[role.toLowerCase()];
    for (final p in _groupPills) {
      if (OvrFormula.groups[p[0]] == g) return p[0];
    }
    return 'st';
  }

  Future<void> _applyCard({
    required int spid,
    required String name,
    String season = '',
    int grade = 1,
    int tc = 0,
    Map<String, List<int>>? tcPreset,
    String? role,
    String? faceUrl,
  }) async {
    setState(() {
      _spid = spid;
      _name = name;
      _season = season;
      _faceUrl = faceUrl ?? 'https://fco.dn.nexoncdn.co.kr/live/externalAssets/common/playersAction/p$spid.png';
      _grade = grade;
      _tcLegacy = tc;
      _tcPreset = tcPreset;
      _tcOptions = {'enhance': [], 'affiliation': [], 'feature': []};
      _tcSel.updateAll((k, v) => null);
      _train.clear();
      _base = null;
      _error = null;
      _loading = true;
      if (role != null && role.isNotEmpty) _pos = _pillFor(role);
    });
    await OvrFormula.ensureLoaded();
    try {
      final r = await http
          .get(Uri.parse('${ApiService.baseUrl}/api/user/squad/player-stats?spid=$spid'))
          .timeout(const Duration(seconds: 25));
      final d = json.decode(r.body);
      if (d['success'] != true || d['player']?['stats'] == null) {
        throw Exception(d['message'] ?? '세부 능력치 조회 실패');
      }
      final p = d['player'] as Map;
      final stats = <String, int>{};
      (p['stats'] as Map).forEach((k, v) => stats['$k'] = (v as num).toInt());
      if (!mounted) return;
      setState(() {
        _base = stats;
        if ((role == null || role.isEmpty) && p['position'] != null) _pos = _pillFor('${p['position']}');
        _loading = false;
      });
      _loadTcOptions(spid);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '세부 능력치를 가져오지 못했습니다.\n$e';
        });
      }
    }
  }

  // ── 팀컬러 3칸: 카드가 고를 수 있는 목록(마스터DB) ──
  Future<void> _loadTcOptions(int spid) async {
    setState(() => _tcLoading = true);
    try {
      final r = await http
          .get(Uri.parse('${ApiService.baseUrl}/api/user/squad/card-teamcolors?spid=$spid'))
          .timeout(const Duration(seconds: 20));
      final d = json.decode(r.body);
      if (!mounted || _spid != spid) return;
      if (d['success'] != true) throw Exception(d['message'] ?? '팀컬러 목록 조회 실패');
      final opts = <String, List<Map<String, dynamic>>>{};
      (d['options'] as Map? ?? {}).forEach((k, v) {
        opts['$k'] = (v as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
      setState(() {
        _tcOptions = {
          'enhance': opts['enhance'] ?? [],
          'affiliation': opts['affiliation'] ?? [],
          'feature': opts['feature'] ?? [],
        };
        _tcLoading = false;
        // 스쿼드에서 넘어온 발동 팀컬러 자동 채움
        final preset = _tcPreset;
        if (preset != null) {
          preset.forEach((sec, v) {
            if (v.length < 2) return;
            final pick = _findPick(sec, v[0], v[1]);
            if (pick != null) _tcSel[sec] = pick;
          });
          _tcPreset = null;
        }
      });
    } catch (e) {
      if (mounted && _spid == spid) setState(() => _tcLoading = false);
    }
  }

  _TcPick? _findPick(String section, int tcId, int level) {
    for (final it in _tcOptions[section] ?? const []) {
      if ((it['tc_id'] as num?)?.toInt() != tcId) continue;
      for (final lv in (it['levels'] as List? ?? const [])) {
        if ((lv['level'] as num?)?.toInt() == level) return _TcPick.from(section, it, lv as Map);
      }
    }
    return null;
  }

  /// 3칸 중 하나라도 골랐으면 그 합, 아니면 구 경로의 '전체 +N'
  bool get _tcChosen => _tcSel.values.any((p) => p != null);
  int get _tcAll => _tcChosen ? _tcSel.values.whereType<_TcPick>().fold(0, (a, p) => a + p.all) : _tcLegacy;

  /// 세부 효과 합 (스탯 → +N), '전체 능력치' 제외
  Map<String, int> get _tcDetail {
    final out = <String, int>{};
    for (final p in _tcSel.values.whereType<_TcPick>()) {
      p.detail.forEach((k, v) => out[k] = (out[k] ?? 0) + v);
    }
    return out;
  }

  // ── 계산 ──
  int get _bonus => (kGradeBonus[_grade] ?? 0) + _adapBonus + _tcAll;
  int get _slots => _trainSlots(_grade);

  Map<String, num> _eff({bool withTrain = true}) {
    final out = <String, num>{};
    final detail = _tcDetail;
    final b = _bonus;
    _base!.forEach((k, v) => out[k] = v + b + (detail[k] ?? 0) + (withTrain ? (_train[k] ?? 0) : 0));
    return out;
  }

  void _trimTrain() {
    final max = _slots;
    if (_train.length <= max) return;
    final order = OvrFormula.weightsFor(_pos).map((e) => e.key).toList();
    final keys = _train.keys.toList()..sort((a, b) => order.indexOf(b).compareTo(order.indexOf(a)));
    for (final k in keys.take(_train.length - max)) {
      _train.remove(k);
    }
  }

  _Rec _recommend(double baseSum) {
    final w = OvrFormula.weightsFor(_pos).take(_slots).toList();
    final target = baseSum.floor() + 1;
    var acc = baseSum;
    List<String>? minPick;
    final picks = <String>[];
    for (final e in w) {
      acc += _trainStep * e.value / 100;
      picks.add(e.key);
      if (minPick == null && acc + 1e-9 >= target) minPick = List.of(picks);
    }
    return _Rec(minPick, picks, (acc + 1e-9).floor(), acc);
  }

  void _applyPick(List<String> keys) {
    setState(() {
      _train.clear();
      for (final k in keys) {
        _train[k] = _trainStep;
      }
    });
  }

  // ── UI ──
  @override
  Widget build(BuildContext context) {
    super.build(context);
    ErrorReporter.currentScreen = '집훈 계산기';
    final body = ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        if (_showSearch) _searchPanel(),
        if (_spid != null) ...[
          if (_showSearch) const SizedBox(height: 10),
          _calcPanel(),
        ],
      ],
    );
    if (widget.asTab) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text('집훈 계산기${_name.isNotEmpty ? ' · $_name' : ''}'),
        actions: [
          TextButton(
            onPressed: () => setState(() => _showSearch = !_showSearch),
            child: Text(_showSearch ? '검색 닫기' : '다른 카드'),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _searchPanel() {
    final muted = Colors.grey.shade500;
    final card = Theme.of(context).cardColor;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.asTab)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child:
                  Text('집훈 계산기', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
          TextField(
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            onChanged: (_) => setState(() {}), // x 버튼 표시 갱신
            decoration: InputDecoration(
              isDense: true,
              hintText: '선수명 (게임 내 등록명, 일부 가능)',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 입력·결과 지우기 (검색 탭과 동일) — 지우면 최근 선택 카드가 다시 보인다 (2026-09-05)
                        if (_searchCtrl.text.isNotEmpty || _results.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() {
                              _searchCtrl.clear();
                              _results = [];
                            }),
                          ),
                        IconButton(icon: const Icon(Icons.arrow_forward, size: 18), onPressed: _search),
                      ],
                    ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          // 최근 선택 카드 — 검색 결과가 없을 때 칩으로 표시, 탭하면 바로 적용 (2026-09-05)
          if (_results.isEmpty && _recentCards.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.history, size: 14, color: muted),
              const SizedBox(width: 4),
              Text('최근 선택', style: TextStyle(fontSize: 11.5, color: muted)),
              const Spacer(),
              InkWell(
                onTap: () => _TrainingRecentStore.clear().then((_) {
                  if (mounted) setState(() => _recentCards = []);
                }),
                child: Text('지우기', style: TextStyle(fontSize: 11, color: muted)),
              ),
            ]),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _recentCards.map((r) {
                final rspid = (r['spid'] is num) ? (r['spid'] as num).toInt() : int.tryParse('${r['spid']}') ?? 0;
                return ActionChip(
                  avatar: ClipOval(
                    child: Image.network('${r['face_url'] ?? ''}',
                        width: 20, height: 20,
                        errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 16)),
                  ),
                  label: Text('${r['name'] ?? ''}${(r['season'] ?? '').toString().isNotEmpty ? ' · ${r['season']}' : ''}',
                      style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    _applyCard(
                      spid: rspid,
                      name: '${r['name'] ?? ''}',
                      season: '${r['season'] ?? ''}',
                      grade: 1,
                      tc: 0,
                      role: '${r['position'] ?? 'st'}',
                      faceUrl: (r['face_url'] ?? '').toString().isEmpty ? null : r['face_url'].toString(),
                    );
                    _TrainingRecentStore.add(Map<String, dynamic>.from(r)).then((list) {
                      if (mounted) setState(() => _recentCards = list);
                    });
                    if (!widget.asTab) setState(() => _showSearch = false);
                  },
                );
              }).toList(),
            ),
          ],
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('카드를 고르세요 (시즌 · 주포지션 · 기본 OVR)', style: TextStyle(fontSize: 11.5, color: muted)),
const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _results.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: muted.withOpacity(.15)),
                itemBuilder: (_, i) {
                  final p = _results[i];
                  final spid = (p['spid'] is num) ? (p['spid'] as num).toInt() : int.tryParse('${p['spid']}') ?? 0;
                  final selected = spid == _spid;
                  return InkWell(
                    onTap: () {
                      _applyCard(
                        spid: spid,
                        name: '${p['name'] ?? ''}',
                        season: '${p['season'] ?? ''}',
                        grade: 1,
                        tc: 0,
                        role: '${p['position'] ?? 'st'}',
                        faceUrl: p['face_url']?.toString(),
                      );
                      // 최근 선택 카드에 기록 (검색 기록)
                      _TrainingRecentStore.add({
                        'spid': spid,
                        'name': '${p['name'] ?? ''}',
                        'season': '${p['season'] ?? ''}',
                        'position': '${p['position'] ?? 'st'}',
                        'face_url': p['face_url']?.toString() ?? '',
                      }).then((list) {
                        if (mounted) setState(() => _recentCards = list);
                      });
                      if (!widget.asTab) setState(() => _showSearch = false);
                    },
child: Container(
                      color: selected ? Theme.of(context).colorScheme.primary.withOpacity(.12) : null,
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(p['face_url']?.toString() ?? '',
                                width: 34,
                                height: 34,
                                errorBuilder: (_, __, ___) => const SizedBox(width: 34, height: 34)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Flexible(
                                      child: Text('${p['name'] ?? ''}',
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                          overflow: TextOverflow.ellipsis)),
                                  const SizedBox(width: 6),
                                  SeasonBadge(spid: spid, height: 13, fallbackText: p['season']?.toString()),
                                ]),
                                Text('${'${p['position'] ?? ''}'.toUpperCase()} · 급여 ${p['pay'] ?? '-'}',
                                    style: TextStyle(fontSize: 11, color: muted)),
                              ],
                            ),
                          ),
                          Text('${p['ovr'] ?? ''}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  fontFeatures: [FontFeature.tabularFigures()])),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ] else if (_spid == null) ...[
            const SizedBox(height: 8),
            Text('선수를 검색해 카드를 고르면 집중훈련으로 오버롤이 얼마나 오르는지 계산합니다.\n스쿼드 탭의 카드를 눌러서도 열 수 있습니다.',
                style: TextStyle(fontSize: 12, color: muted)),
          ],
        ],
      ),
    );
  }

  Widget _calcPanel() {
    final muted = Colors.grey.shade500;
    final card = Theme.of(context).cardColor;
    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)),
        child: Text(_error!, style: TextStyle(color: muted)),
      );
    }
    if (_loading || _base == null) {
      return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
    }
    final cs = Theme.of(context).colorScheme;
    final accent = cs.primary;
    final good = Theme.of(context).brightness == Brightness.dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
    final warn = Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
    const mono = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

    final eff = _eff();
    final sum = OvrFormula.weightedSum(eff, _pos);
    final ovr = (sum + 1e-9).floor();
    final baseSum = OvrFormula.weightedSum(_eff(withTrain: false), _pos);
    final baseOvr = (baseSum + 1e-9).floor();
    final totalPt = (sum * 100).round();
    final needPt = 100 - (totalPt % 100);
    final wmap = OvrFormula.weights[OvrFormula.groups[_pos] ?? ''] ?? const {};
    final usedPt = _train.entries.fold<int>(0, (a, e) => a + e.value * (wmap[e.key] ?? 0));
    final rec = _recommend(baseSum);
    final weighted = OvrFormula.weightsFor(_pos);
    final inW = weighted.map((e) => e.key).toSet();
    final others = OvrFormula.statKeys.where((k) => !inW.contains(k) && _base!.containsKey(k)).toList();
    // 포지션 핀 OVR: 세부 효과(팀컬러)까지 반영한 현재 조건 값 (훈련 제외)
    final effBase = _eff(withTrain: false);
    final pillOvr = {for (final p in _groupPills) p[0]: OvrFormula.calc(effBase, p[0])};
    final pills = List.of(_groupPills)..sort((a, b) => (pillOvr[b[0]] ?? 0).compareTo(pillOvr[a[0]] ?? 0));

    Widget kpi(String k, String v, {Color? color, String? small}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Text(k, style: TextStyle(fontSize: 10.5, color: muted)),
              Text.rich(TextSpan(children: [
                TextSpan(text: v, style: mono.copyWith(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
                if (small != null) TextSpan(text: ' $small', style: TextStyle(fontSize: 10, color: muted)),
              ])),
            ]),
          ),
        );

    return Column(
      children: [
        // ── 카드·조건·KPI ──
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_faceUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(_faceUrl!,
                            width: 44, height: 44, errorBuilder: (_, __, ___) => const SizedBox(width: 44, height: 44)),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Flexible(
                              child: Text(_name,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                                  overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 6),
                          SeasonBadge(spid: _spid, height: 14, fallbackText: _season),
                        ]),
                        Text('적응도 Lv.5 · ${_pos.toUpperCase()} 기준', style: TextStyle(fontSize: 11.5, color: muted)),
                      ],
                    ),
                  ),
                  Text('$ovr',
                      style: mono.copyWith(fontSize: 44, fontWeight: FontWeight.w800, height: 1, letterSpacing: -1.5)),
                ],
              ),
              const SizedBox(height: 10),
              // 강화 · 초기화
              Row(
                children: [
                  _dropdown<int>(
                    value: _grade,
                    items: [for (var g = 1; g <= 13; g++) DropdownMenuItem(value: g, child: Text('$g강'))],
                    onChanged: (v) => setState(() {
                      _grade = v ?? _grade;
                      _trimTrain();
                    }),
                  ),
                  const SizedBox(width: 8),
                  Text('적응도 Lv.5', style: TextStyle(fontSize: 11.5, color: muted)),
                  const Spacer(),
                  TextButton(
                    onPressed: _train.isEmpty ? null : () => setState(() => _train.clear()),
                    child: const Text('초기화'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // 팀컬러 3칸 (A안): 강화 · 소속 · 특성 — 카드에 해당하는 것만, 누르면 시트
              Row(
                children: [
                  for (var i = 0; i < _tcSections.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(child: _tcField(_tcSections[i][0], _tcSections[i][1], muted)),
                  ],
                ],
              ),
              if (_tcChosen || _tcLegacy > 0) ...[
                const SizedBox(height: 4),
                Text(_tcSummary(), style: TextStyle(fontSize: 11, color: muted, height: 1.4)),
              ],
              const SizedBox(height: 8),
              Row(children: [
                kpi('오버롤 상승', '$needPt', color: warn, small: '포인트 필요'),
                const SizedBox(width: 6),
                kpi('사용 포인트', '$usedPt'),
                const SizedBox(width: 6),
                kpi('선택', '${_train.length} / $_slots'),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                    value: (totalPt % 100) / 100, minHeight: 6, color: accent, backgroundColor: muted.withOpacity(.2)),
              ),
              const SizedBox(height: 4),
              Text(
                '총점 $totalPt · $_grade강은 능력치 $_slots개까지, 능력치당 +$_trainStep'
                '${_tcAll > 0 ? ' · 팀컬러 전체 +$_tcAll' : ''}'
                '${ovr != baseOvr ? ' · 훈련으로 +${ovr - baseOvr} (전 $baseOvr)' : ''}',
                style: mono.copyWith(fontSize: 11, color: ovr != baseOvr ? good : muted),
              ),
              const SizedBox(height: 10),
              // 포지션 핀
              SizedBox(
                height: 30,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: pills.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final p = pills[i];
                    final on = p[0] == _pos;
                    final o = OvrFormula.groups[p[0]] == null ? null : pillOvr[p[0]];
                    return InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => setState(() {
                        _pos = p[0];
                        _trimTrain();
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: on ? accent : Colors.transparent,
                          border: Border.all(color: on ? accent : muted.withOpacity(.5)),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('${p[1]}${o != null ? ' $o' : ''}',
                            style: mono.copyWith(
                                fontSize: 12, fontWeight: FontWeight.w700, color: on ? Colors.white : muted)),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Text('추천 (가중치 높은 순, 누르면 적용)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: muted)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (rec.minPick != null)
                    _recChip(good, () => _applyPick(rec.minPick!), [
                      const TextSpan(text: 'OVR +1 최소 '),
                      TextSpan(text: '${rec.minPick!.length}개', style: const TextStyle(fontWeight: FontWeight.w800)),
                      TextSpan(text: ' · ${rec.minPick!.join(' · ')}'),
                    ])
                  else
                    Text('$_slots개를 다 올려도 OVR +1은 안 됩니다 (최대 총점 ${(rec.maxSum * 100).round()})',
                        style: TextStyle(fontSize: 11.5, color: muted)),
                  _recChip(good, () => _applyPick(rec.maxPick), [
                    const TextSpan(text: '최대 OVR '),
                    TextSpan(text: '${rec.maxOvr}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    TextSpan(text: ' · $_slots개 전부'),
                  ]),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // ── 능력치 (가중치 순) ──
        Container(
          padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)),
          child: Column(
            children: [
              for (var i = 0; i < weighted.length; i++) ...[
                _statRow(weighted[i].key, weighted[i].value, eff[weighted[i].key]!.toInt(),
                    _tcDetail[weighted[i].key] ?? 0, accent, good, muted, mono),
                if (i < weighted.length - 1) Divider(height: 1, color: muted.withOpacity(.15)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            title: Text('${_pos.toUpperCase()} OVR에 영향 없는 능력치 ${others.length}개',
                style: TextStyle(fontSize: 12.5, color: muted)),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    for (final k in others)
                      Text('$k ${eff[k]?.toInt() ?? _base![k]}', style: mono.copyWith(fontSize: 12, color: muted))
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
          child: Text(
            '총점 = Σ (능력치 + 팀컬러 세부 효과) × 포지션 가중치 + 100 × (강화 + 팀컬러 전체 + 적응도), OVR = 총점 ÷ 100 내림, '
            '오버롤 상승 필요 포인트 = 100 − 총점의 나머지. 넥슨 데이터센터 11,396건·집훈 오라클 30건 대조 100% 일치(2026-08-22). '
            '팀컬러 3칸은 강화(물결)·소속·특성이 함께 적용되고, 소속 Lv3·4와 특성의 세부 효과는 해당 능력치에만 더해집니다.',
            style: TextStyle(fontSize: 10.5, color: muted),
          ),
        ),
      ],
    );
  }

  Widget _dropdown<T>(
      {required T value, required List<DropdownMenuItem<T>> items, required ValueChanged<T?> onChanged}) {
    final muted = Colors.grey.shade500;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration:
          BoxDecoration(border: Border.all(color: muted.withOpacity(.4)), borderRadius: BorderRadius.circular(10)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
            value: value,
            isDense: true,
            style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurface),
            items: items,
            onChanged: onChanged),
      ),
    );
  }

  Widget _recChip(Color good, VoidCallback onTap, List<InlineSpan> spans) => ActionChip(
        onPressed: onTap,
        backgroundColor: good.withOpacity(.12),
        side: BorderSide(color: good.withOpacity(.4)),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        label: Text.rich(TextSpan(children: spans), style: TextStyle(fontSize: 12, color: good)),
      );

  // ── 팀컬러 3칸 UI ──
  Widget _tcField(String section, String label, Color muted) {
    final pick = _tcSel[section];
    final count = (_tcOptions[section] ?? const []).length;
    final tokens = PanenkaTokens.of(context);
    final empty = pick == null;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _tcLoading || count == 0 ? null : () => _openTcSheet(section, label),
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
                    _tcLoading
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

  String _tcSummary() {
    if (!_tcChosen) return '스쿼드 발동 팀컬러 전체 +$_tcLegacy (자동) · 칸을 고르면 그 값으로 바뀝니다';
    final detail = _tcDetail;
    final parts = <String>['팀컬러 합계 전체 +$_tcAll'];
    if (detail.isNotEmpty) {
      parts.add('세부 ${detail.entries.map((e) => '${e.key} +${e.value}').join(' · ')}');
    }
    return parts.join(' · ');
  }

  Future<void> _openTcSheet(String section, String label) async {
    final items = _tcOptions[section] ?? const [];
    final current = _tcSel[section];
    final picked = await showModalBottomSheet<_TcPick?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => _TcSheet(
        title: label,
        items: items,
        section: section,
        current: current,
        grade: _grade,
      ),
    );
    if (picked == null) return;
    setState(() => _tcSel[section] = picked.tcId == 0 ? null : picked);
  }

  Widget _statRow(String k, int w, int eff, int tcb, Color accent, Color good, Color muted, TextStyle mono) {
    final tr = _train[k] ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k, style: const TextStyle(fontSize: 13)),
                Text('+1당 ${w}pt${tcb > 0 ? ' · 팀컬러 +$tcb' : ''}${tr > 0 ? ' · 사용 +${tr * w}pt' : ''}',
                    style: mono.copyWith(fontSize: 10.5, color: tr > 0 ? good : muted)),
              ],
            ),
          ),
          SizedBox(
            width: 70,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: '$eff',
                    style: mono.copyWith(fontSize: 15, fontWeight: FontWeight.w700, color: tr > 0 ? good : null)),
                if (tr > 0)
                  TextSpan(
                      text: '  +$tr', style: mono.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: good)),
              ]),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 10),
          _PickButton(
            accent: accent,
            good: good,
            muted: muted,
            on: tr > 0,
            enabled: tr > 0 || _train.length < _slots,
            step: _trainStep,
            onTap: () => setState(() {
              if (tr > 0) {
                _train.remove(k);
              } else if (_train.length < _slots) {
                _train[k] = _trainStep;
              }
            }),
          ),
        ],
      ),
    );
  }
}

/// 팀컬러 선택 1건 (칸 하나에 팀컬러 1개 × 단계 1개)
class _TcPick {
  final String section;
  final int tcId;
  final String name;
  final int level;
  final int count;
  final int all;
  final Map<String, int> detail;
  const _TcPick(this.section, this.tcId, this.name, this.level, this.count, this.all, this.detail);

  /// tcId 0 = '—' (선택 해제)
  static const none = _TcPick('', 0, '', 0, 0, 0, {});

  factory _TcPick.from(String section, Map<String, dynamic> item, Map lv) {
    final detail = <String, int>{};
    for (final e in (lv['effects'] as List? ?? const [])) {
      final stat = '${e['stat']}';
      if (stat == '전체 능력치') continue;
      detail[stat] = (detail[stat] ?? 0) + ((e['value'] as num?)?.toInt() ?? 0);
    }
    return _TcPick(section, (item['tc_id'] as num).toInt(), '${item['name'] ?? ''}',
        (lv['level'] as num?)?.toInt() ?? 1, (lv['count'] as num?)?.toInt() ?? 0,
        (lv['all'] as num?)?.toInt() ?? 0, detail);
  }

  String get effectText {
    final parts = <String>['$count명'];
    if (all > 0) parts.add('전체 +$all');
    parts.addAll(detail.entries.map((e) => '${e.key} +${e.value}'));
    return parts.join(' · ');
  }
}

/// 팀컬러 선택 시트: 검색 + 'LvN. 이름' 목록 (카드에 해당하는 것만)
class _TcSheet extends StatefulWidget {
  final String title;
  final String section;
  final List<Map<String, dynamic>> items;
  final _TcPick? current;
  final int grade;
  const _TcSheet({required this.title, required this.section, required this.items, required this.current, required this.grade});

  @override
  State<_TcSheet> createState() => _TcSheetState();
}

class _TcSheetState extends State<_TcSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final muted = Colors.grey.shade500;
    final tokens = PanenkaTokens.of(context);
    final rows = <_TcPick>[];
    for (final it in widget.items) {
      final name = '${it['name'] ?? ''}';
      if (_q.isNotEmpty && !name.toLowerCase().contains(_q.toLowerCase())) continue;
      for (final lv in (it['levels'] as List? ?? const [])) {
        rows.add(_TcPick.from(widget.section, it, lv as Map));
      }
    }
    final minGrade = {for (final it in widget.items) (it['tc_id'] as num).toInt(): (it['min_grade'] as num?)?.toInt() ?? 0};
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .78),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(width: 36, height: 4, decoration: BoxDecoration(color: muted.withOpacity(.5), borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Row(children: [
                  Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 6),
                  Text('이 카드에 해당하는 것만', style: TextStyle(fontSize: 11, color: muted)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  onChanged: (v) => setState(() => _q = v.trim()),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '검색어를 입력하세요',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: rows.length + 1,
                  separatorBuilder: (_, __) => Divider(height: 1, color: muted.withOpacity(.15)),
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      final on = widget.current == null;
                      return ListTile(
                        dense: true,
                        title: const Text('—'),
                        subtitle: Text('적용 안 함', style: TextStyle(fontSize: 11, color: muted)),
                        trailing: on ? Icon(Icons.check, color: tokens.accentInk, size: 18) : null,
                        onTap: () => Navigator.pop(context, _TcPick.none),
                      );
                    }
                    final p = rows[i - 1];
                    final on = widget.current != null && widget.current!.tcId == p.tcId && widget.current!.level == p.level;
                    final mg = minGrade[p.tcId] ?? 0;
                    final under = mg > 0 && widget.grade < mg;
                    return ListTile(
                      dense: true,
                      title: Text('Lv${p.level}. ${p.name}',
                          style: TextStyle(fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: under ? muted : null)),
                      subtitle: Text('${p.effectText}${mg > 0 ? ' · $mg강 이상' : ''}', style: TextStyle(fontSize: 11, color: muted)),
                      trailing: on ? Icon(Icons.check, color: tokens.accentInk, size: 18) : null,
                      onTap: () => Navigator.pop(context, p),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Rec {
  final List<String>? minPick;
  final List<String> maxPick;
  final int maxOvr;
  final double maxSum;
  const _Rec(this.minPick, this.maxPick, this.maxOvr, this.maxSum);
}

class _PickButton extends StatelessWidget {
  final Color accent;
  final Color good;
  final Color muted;
  final bool on;
  final bool enabled;
  final int step;
  final VoidCallback onTap;
  const _PickButton(
      {required this.accent,
      required this.good,
      required this.muted,
      required this.on,
      required this.enabled,
      required this.step,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = on ? Colors.white : (enabled ? accent : muted.withOpacity(.5));
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? good : Colors.transparent,
          border: Border.all(color: on ? good : muted.withOpacity(enabled ? .5 : .25)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(on ? '+$step 해제' : '선택 +$step',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
      ),
    );
  }
}


/// 집훈 계산기 최근 선택 카드 저장소 (검색 기록) — SharedPreferences, 최대 10개, 같은 spid는 최신으로 교체. (2026-09-05)
class _TrainingRecentStore {
  static const _key = 'training_recent_cards_v1';
  static const _max = 10;

  static Future<List<Map<String, dynamic>>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      return (json.decode(raw) as List).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      print('[TrainingRecentStore] 로드 실패: $e');
      return [];
    }
  }

  static Future<void> _save(List<Map<String, dynamic>> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, json.encode(list));
    } catch (e) {
      print('[TrainingRecentStore] 저장 실패: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> add(Map<String, dynamic> card) async {
    final list = await load();
    list.removeWhere((r) => '${r['spid']}' == '${card['spid']}');
    list.insert(0, card);
    final trimmed = list.length > _max ? list.sublist(0, _max) : list;
    await _save(trimmed);
    return trimmed;
  }

  static Future<void> clear() => _save([]);
}
