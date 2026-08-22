import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../constants/positions.dart';
import '../services/api_service.dart';
import '../services/error_reporter.dart';
import '../services/ovr_formula.dart';
import '../widgets/badges.dart';

/// 집훈 계산기 (집중훈련 OVR 계산) — Panenka 1.0.4 (2026-08-22).
///
/// 두 진입 경로가 같은 화면을 쓴다.
///  ① 메인 탭(asTab=true): 검색 → 시즌·주포지션·OVR 목록에서 카드 선택 → 강화·팀컬러 선택 → 계산
///  ② 스쿼드 카드에서 push: 검색 단계를 건너뛰고 카드·강화·발동 팀컬러가 채워진 채 열림 ("다른 카드"로 검색 가능)
/// 인벤 계산기와 같은 체계: 총점 = Σ(능력치×가중치) + 100×(강화+팀컬러+적응도), OVR = 총점÷100 내림,
///   오버롤 상승 필요 포인트 = 100 − 총점%100, 사용 포인트 = Σ(훈련치×가중치). 적응도 Lv.5 고정(+4).
/// 집중훈련 규칙(사용자 확인): 10강 이하 능력치 5개 · 11강 이상 6개 선택, 선택한 능력치마다 +2.
class TrainingCalcScreen extends StatefulWidget {
  final bool asTab;
  final int? spid;
  final String? name;
  final String? season;
  final int grade;
  final int tcBonus;
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
  int _tc = 0;
  String _pos = 'st';
  Map<String, int>? _base;
  List<int> _eachOvr = [];
  final Map<String, int> _train = {};
  String? _error;
  bool _loading = false;

  // 검색
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  bool _showSearch = false;

  @override
  bool get wantKeepAlive => widget.asTab;

  @override
  void initState() {
    super.initState();
    _showSearch = widget.asTab || widget.spid == null;
    if (widget.spid != null) {
      _applyCard(
        spid: widget.spid!,
        name: widget.name ?? '',
        season: widget.season ?? '',
        grade: widget.grade,
        tc: widget.tcBonus,
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
    String? role,
    String? faceUrl,
  }) async {
    setState(() {
      _spid = spid;
      _name = name;
      _season = season;
      _faceUrl = faceUrl ?? 'https://fco.dn.nexoncdn.co.kr/live/externalAssets/common/playersAction/p$spid.png';
      _grade = grade;
      _tc = tc;
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
      final eo = (p['each_ovr']?.toString() ?? '').split(',').map((s) => int.tryParse(s.trim()) ?? 0).toList();
      if (!mounted) return;
      setState(() {
        _base = stats;
        _eachOvr = eo;
        if ((role == null || role.isEmpty) && p['position'] != null) _pos = _pillFor('${p['position']}');
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '세부 능력치를 가져오지 못했습니다.\n$e';
        });
      }
    }
  }

  // ── 계산 ──
  int get _bonus => (kGradeBonus[_grade] ?? 0) + _adapBonus + _tc;
  int get _slots => _trainSlots(_grade);

  int? _eachOvrAt(String pos) {
    final i = OvrFormula.positions.indexOf(pos);
    return i >= 0 && i < _eachOvr.length ? _eachOvr[i] : null;
  }

  Map<String, num> _eff({bool withTrain = true}) {
    final out = <String, num>{};
    _base!.forEach((k, v) => out[k] = v + _bonus + (withTrain ? (_train[k] ?? 0) : 0));
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
            decoration: InputDecoration(
              isDense: true,
              hintText: '선수명 (게임 내 등록명, 일부 가능)',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(icon: const Icon(Icons.arrow_forward, size: 18), onPressed: _search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('카드를 고르세요 (시즌 · 주포지션 · 1강 OVR)', style: TextStyle(fontSize: 11.5, color: muted)),
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
    final pills = List.of(_groupPills)..sort((a, b) => (_eachOvrAt(b[0]) ?? 0).compareTo(_eachOvrAt(a[0]) ?? 0));

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
              // 강화 · 팀컬러 · 초기화
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
                  _dropdown<int>(
                    value: _tc,
                    items: [for (var t = 0; t <= 12; t++) DropdownMenuItem(value: t, child: Text('팀컬러 +$t'))],
                    onChanged: (v) => setState(() => _tc = v ?? _tc),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _train.isEmpty ? null : () => setState(() => _train.clear()),
                    child: const Text('초기화'),
                  ),
                ],
              ),
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
                    final o = _eachOvrAt(p[0]);
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
                        child: Text('${p[1]}${o != null ? ' ${o + _bonus}' : ''}',
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
                _statRow(weighted[i].key, weighted[i].value, eff[weighted[i].key]!.toInt(), accent, good, muted, mono),
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
                      Text('$k ${_base![k]! + _bonus}', style: mono.copyWith(fontSize: 12, color: muted))
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
          child: Text(
            '총점 = Σ 능력치 × 포지션 가중치 + 100 × (강화 + 팀컬러 + 적응도), OVR = 총점 ÷ 100 내림, '
            '오버롤 상승 필요 포인트 = 100 − 총점의 나머지. 넥슨 데이터센터 11,396건·집훈 오라클 30건 대조 100% 일치(2026-08-22).',
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

  Widget _statRow(String k, int w, int eff, Color accent, Color good, Color muted, TextStyle mono) {
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
                Text('+1당 ${w}pt${tr > 0 ? ' · 사용 +${tr * w}pt' : ''}',
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
