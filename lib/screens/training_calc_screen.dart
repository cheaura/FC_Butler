import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../constants/positions.dart';
import '../services/api_service.dart';
import '../services/ovr_formula.dart';

/// 집훈 계산기 (집중훈련 OVR 계산) — 2026-08-22, A안 스탯 시트형 (사용자 선택).
///
/// 데이터: `/api/user/squad/player-stats?spid=` (0강 세부 능력치 34종 + eachOvr 28)
/// 공식: [OvrFormula] — OVR = 내림(Σ (0강 스탯 + 강화 보너스 + 훈련치) × 가중치 / 100)
/// 강화·팀컬러 '전체 능력치'는 전 스탯 균등 가산이라 같은 공식으로 계산된다.
/// 집중훈련 규칙(사용자 확인 08-22): 10강 이하 능력치 5개 · 11강 이상 6개 선택, 선택한 능력치마다 +2.
class TrainingCalcScreen extends StatefulWidget {
  final int spid;
  final String name;
  final int grade;
  final String role; // 슬롯 포지션 코드 (st, lw, cb …)
  final String? faceUrl;
  final String? season;

  const TrainingCalcScreen({
    super.key,
    required this.spid,
    required this.name,
    this.grade = 1,
    this.role = 'st',
    this.faceUrl,
    this.season,
  });

  @override
  State<TrainingCalcScreen> createState() => _TrainingCalcScreenState();
}

class _TrainingCalcScreenState extends State<TrainingCalcScreen> {
  // 포지션 그룹 대표 (같은 그룹은 가중치가 같아 OVR도 같다)
  static const _groupPills = [
    ['st', 'ST'], ['cf', 'CF'], ['lw', 'LW/RW'], ['cam', 'CAM'], ['cm', 'CM'],
    ['lm', 'LM/RM'], ['cdm', 'CDM'], ['cb', 'CB'], ['sw', 'SW'], ['lb', 'LB/RB'],
    ['lwb', 'LWB/RWB'], ['gk', 'GK'],
  ];

  static const _trainStep = 2; // 선택 능력치 1개당 +2
  static int _trainSlots(int grade) => grade >= 11 ? 6 : 5;

  Map<String, int>? _base; // 0강 세부 능력치
  List<int> _eachOvr = [];
  final Map<String, int> _train = {}; // 선택한 능력치 → +2
  late int _grade = widget.grade;
  late String _pos = 'st';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _pillFor(String role) {
    final g = OvrFormula.groups[role.toLowerCase()];
    for (final p in _groupPills) {
      if (OvrFormula.groups[p[0]] == g) return p[0];
    }
    return 'st';
  }

  Future<void> _load() async {
    await OvrFormula.ensureLoaded();
    _pos = _pillFor(widget.role);
    try {
      final r = await http
          .get(Uri.parse('${ApiService.baseUrl}/api/user/squad/player-stats?spid=${widget.spid}'))
          .timeout(const Duration(seconds: 25));
      final d = json.decode(r.body);
      if (d['success'] != true || d['player']?['stats'] == null) {
        throw Exception(d['message'] ?? '세부 능력치 조회 실패');
      }
      final p = d['player'] as Map;
      final stats = <String, int>{};
      (p['stats'] as Map).forEach((k, v) => stats['$k'] = (v as num).toInt());
      final eo = (p['each_ovr']?.toString() ?? '')
          .split(',')
          .map((s) => int.tryParse(s.trim()) ?? 0)
          .toList();
      if (!mounted) return;
      setState(() {
        _base = stats;
        _eachOvr = eo;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '세부 능력치를 가져오지 못했습니다.\n$e');
    }
  }

  int get _gb => kGradeBonus[_grade] ?? 0;

  int? _eachOvrAt(String pos) {
    final i = OvrFormula.positions.indexOf(pos);
    return i >= 0 && i < _eachOvr.length ? _eachOvr[i] : null;
  }

  Map<String, num> _eff({bool withTrain = true}) {
    final out = <String, num>{};
    _base!.forEach((k, v) => out[k] = v + _gb + (withTrain ? (_train[k] ?? 0) : 0));
    return out;
  }

  int get _slots => _trainSlots(_grade);

  /// 강화 단계가 내려가 한도를 넘으면 가중치 낮은 것부터 해제
  void _trimTrain() {
    final max = _slots;
    if (_train.length <= max) return;
    final order = OvrFormula.weightsFor(_pos).map((e) => e.key).toList();
    final keys = _train.keys.toList()
      ..sort((a, b) => order.indexOf(b).compareTo(order.indexOf(a)));
    for (final k in keys.take(_train.length - max)) {
      _train.remove(k);
    }
  }

  /// 추천: 가중치 높은 순으로 +2씩 채웠을 때 — OVR +1 최소 선택 / 한도 전부 사용 시 최대 OVR
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = cs.primary;
    final good = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF4ADE80)
        : const Color(0xFF15803D);
    final muted = Colors.grey.shade500;

    return Scaffold(
      appBar: AppBar(
        title: Text('집훈 계산기 · ${widget.name}'),
        actions: [
          TextButton(
            onPressed: _train.isEmpty ? null : () => setState(() => _train.clear()),
            child: const Text('초기화'),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: muted)),
              ),
            )
          : _base == null
              ? const Center(child: CircularProgressIndicator())
              : _buildBody(accent, good, muted),
    );
  }

  Widget _buildBody(Color accent, Color good, Color muted) {
    final eff = _eff();
    final sum = OvrFormula.weightedSum(eff, _pos);
    final ovr = (sum + 1e-9).floor();
    final baseOvr = (OvrFormula.weightedSum(_eff(withTrain: false), _pos) + 1e-9).floor();
    final frac = sum - ovr;
    final rec = _recommend(OvrFormula.weightedSum(_eff(withTrain: false), _pos));
    final weighted = OvrFormula.weightsFor(_pos);
    final inW = weighted.map((e) => e.key).toSet();
    final others = OvrFormula.statKeys.where((k) => !inW.contains(k) && _base!.containsKey(k)).toList();
    final pills = List.of(_groupPills)
      ..sort((a, b) => (_eachOvrAt(b[0]) ?? 0).compareTo(_eachOvrAt(a[0]) ?? 0));
    final card = Theme.of(context).cardColor;
    const mono = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        // ── 요약 카드 ──
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (widget.faceUrl != null && widget.faceUrl!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(widget.faceUrl!, width: 44, height: 44,
                            errorBuilder: (_, __, ___) => const SizedBox(width: 44, height: 44)),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        Row(
                          children: [
                            if (widget.season != null) Text('${widget.season} · ', style: TextStyle(color: muted, fontSize: 12)),
                            DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                value: _grade,
                                isDense: true,
                                style: TextStyle(color: muted, fontSize: 12),
                                items: [for (var g = 1; g <= 13; g++) DropdownMenuItem(value: g, child: Text('$g강'))],
                                onChanged: (v) => setState(() {
                                  _grade = v ?? _grade;
                                  _trimTrain();
                                }),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$ovr',
                          style: mono.copyWith(fontSize: 44, fontWeight: FontWeight.w800, height: 1, letterSpacing: -1.5)),
                      Text(
                        ovr != baseOvr ? '+${ovr - baseOvr} (훈련 전 $baseOvr)' : '가중합 ${sum.toStringAsFixed(2)}',
                        style: mono.copyWith(fontSize: 11, color: ovr != baseOvr ? good : muted, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
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
                      onTap: () => setState(() => _pos = p[0]),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: on ? accent : Colors.transparent,
                          border: Border.all(color: on ? accent : muted.withOpacity(.5)),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${p[1]}${o != null ? ' ${o + _gb}' : ''}',
                          style: mono.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: on ? Colors.white : muted),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(value: frac.clamp(0, 1).toDouble(), minHeight: 6, color: accent,
                    backgroundColor: muted.withOpacity(.2)),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('다음 OVR까지 ', style: TextStyle(fontSize: 12, color: muted)),
                  Text((1 - frac).toStringAsFixed(2), style: mono.copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: good)),
                  Text(' · 가중합 ${sum.toStringAsFixed(2)}', style: mono.copyWith(fontSize: 12, color: muted)),
                ],
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '집중훈련 선택 ', style: TextStyle(color: muted)),
                  TextSpan(text: '${_train.length} / $_slots', style: mono.copyWith(fontWeight: FontWeight.w800)),
                  TextSpan(text: '개 ($_grade강은 $_slots개, 능력치당 +$_trainStep)', style: TextStyle(color: muted)),
                ]),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              Text('추천 (가중치 높은 순, 탭하면 적용)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: muted)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (rec.minPick != null)
                    ActionChip(
                      onPressed: () => _applyPick(rec.minPick!),
                      backgroundColor: good.withOpacity(.12),
                      side: BorderSide(color: good.withOpacity(.4)),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                      label: Text.rich(TextSpan(children: [
                        const TextSpan(text: 'OVR +1 최소 '),
                        TextSpan(text: '${rec.minPick!.length}개', style: const TextStyle(fontWeight: FontWeight.w800)),
                        TextSpan(text: ' · ${rec.minPick!.join(' · ')}'),
                      ]), style: TextStyle(fontSize: 12, color: good)),
                    )
                  else
                    Text('$_slots개를 다 올려도 OVR +1은 안 됩니다 (최대 가중합 ${rec.maxSum.toStringAsFixed(2)})',
                        style: TextStyle(fontSize: 11.5, color: muted)),
                  ActionChip(
                    onPressed: () => _applyPick(rec.maxPick),
                    backgroundColor: good.withOpacity(.12),
                    side: BorderSide(color: good.withOpacity(.4)),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    label: Text.rich(TextSpan(children: [
                      const TextSpan(text: '최대 OVR '),
                      TextSpan(text: '${rec.maxOvr}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      TextSpan(text: ' · $_slots개 전부'),
                    ]), style: TextStyle(fontSize: 12, color: good)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // ── 스탯 시트 (가중치 순) ──
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
        // ── 영향 없는 능력치 (접기) ──
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
                      Text('$k ${_base![k]! + _gb}', style: mono.copyWith(fontSize: 12, color: muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
          child: Text(
            'OVR = 내림(Σ 능력치 × 포지션 가중치 / 100). 넥슨 데이터센터 eachOvr 11,396건·집훈 오라클 30건 대조 100% 일치(2026-08-22). '
            "팀컬러 '전체 능력치 +N'은 OVR에 그대로 +N.",
            style: TextStyle(fontSize: 10.5, color: muted),
          ),
        ),
      ],
    );
  }

  Widget _statRow(String k, int w, int eff, Color accent, Color good, Color muted, TextStyle mono) {
    final tr = _train[k] ?? 0;
    final cur = _base![k]! + _gb;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k, style: const TextStyle(fontSize: 13)),
                Text('$w% · 기여 ${(eff * w / 100).toStringAsFixed(2)}', style: mono.copyWith(fontSize: 10.5, color: muted)),
              ],
            ),
          ),
          SizedBox(
            width: 74,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '$eff', style: mono.copyWith(fontSize: 15, fontWeight: FontWeight.w700, color: tr > 0 ? good : null)),
                if (tr > 0) TextSpan(text: '  +$tr', style: mono.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: good)),
                if (tr == 0) TextSpan(text: '  $cur', style: mono.copyWith(fontSize: 11, color: Colors.transparent)),
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
  final List<String>? minPick; // OVR +1에 필요한 최소 선택 (한도 내 불가면 null)
  final List<String> maxPick; // 한도 전부 사용 (가중치 상위)
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
  const _PickButton({
    required this.accent,
    required this.good,
    required this.muted,
    required this.on,
    required this.enabled,
    required this.step,
    required this.onTap,
  });

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
