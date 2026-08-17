import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../constants/positions.dart';
import '../services/api_service.dart';
import '../utils/fc_format.dart';
import 'badges.dart';
import 'pill_tabs.dart';

/// 스쿼드 탭 — 랭커 스쿼드 기반 스쿼드메이커 (웹 대시보드 스쿼드 탭과 동일 데이터).
/// 흐름(사용자 확정): 조건(모드/상위N/팀컬러/포메이션) → 랭커 스쿼드 생성 → 슬롯 탭으로 교체(커스텀).
/// 서버: /api/user/squad/ranker-meta, /api/user/squad/ranker-squad (무인증 공개)
class SquadTab extends StatefulWidget {
  const SquadTab({Key? key}) : super(key: key);

  @override
  State<SquadTab> createState() => _SquadTabState();
}

/// 슬롯 하나 — 포지션 + 배치된 랭커픽 카드
class _Slot {
  final int spPos;
  Map<String, dynamic>? pick; // {spid, grade, users, name, season, face_url}
  _Slot(this.spPos, this.pick);
}

class _SquadTabState extends State<SquadTab> with AutomaticKeepAliveClientMixin {
  String _mode = 'manager';
  int _top = 1000;
  String _teamcolor = '';
  String _formation = '';

  bool _metaLoading = false;
  bool _generating = false;
  String? _error;
  Map<String, dynamic>? _meta; // teamcolors/formations/snap_date

  List<_Slot> _slots = [];
  Map<String, List<dynamic>> _picksByPos = {};
  int _base = 0; // 조건 내 스쿼드 수 (사용률 % 분모)
  String _snapDate = '';
  // 스쿼드 요약 (급여·구단가치·팀컬러 — 사용자 지정)
  final Map<int, Map<String, dynamic>> _fields = {}; // spid → player-fields
  Map<String, dynamic>? _tcCalc; // 팀컬러 계산 응답
  bool _summaryLoading = false;

  static const _topOptions = [200, 1000, 3000, 5000, 10000];

  @override
  bool get wantKeepAlive => true;

  Color get _accent => Theme.of(context).colorScheme.primary;
  Color get _subColor => Colors.grey.shade500;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    setState(() {
      _metaLoading = true;
      _error = null;
    });
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/user/squad/ranker-meta'
            '?mode=$_mode&top=$_top'),
      ).timeout(const Duration(seconds: 20));
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          _meta = data;
          // 조건 목록이 바뀌면 기존 선택이 목록에 없을 수 있음 → 초기화
          final tcs = (data['teamcolors'] as List? ?? [])
              .map((t) => t['name'] as String)
              .toSet();
          if (_teamcolor.isNotEmpty && !tcs.contains(_teamcolor)) _teamcolor = '';
          final fms = (data['formations'] as List? ?? [])
              .map((f) => f['name'] as String)
              .toSet();
          if (_formation.isNotEmpty && !fms.contains(_formation)) _formation = '';
        });
      } else {
        setState(() => _error = data['message'] ?? '조건 목록을 불러오지 못했습니다.');
      }
    } catch (e) {
      setState(() => _error = '네트워크 오류가 발생했습니다.');
    } finally {
      setState(() => _metaLoading = false);
    }
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/user/squad/ranker-squad'
            '?mode=$_mode&top=$_top'
            '&teamcolor=${Uri.encodeComponent(_teamcolor)}'
            '&formation=${Uri.encodeComponent(_formation)}'),
      ).timeout(const Duration(seconds: 30));
      final data = json.decode(response.body);
      if (response.statusCode != 200 || data['success'] != true) {
        setState(() => _error = data['message'] ?? '랭커 스쿼드 조회에 실패했습니다.');
        return;
      }
      final picksByPos = <String, List<dynamic>>{};
      (data['picks_by_position'] as Map<String, dynamic>? ?? {})
          .forEach((k, v) => picksByPos[k] = v as List<dynamic>);

      // 실사용 포지션 상위 11자리 재구성 (웹 buildSlotsFromRankerPicks와 동일)
      final entries = picksByPos.entries.map((e) {
        int users = 0;
        for (final p in e.value) {
          users += (p['users'] as num? ?? 0).toInt();
        }
        return MapEntry(int.parse(e.key), users);
      }).toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final positions = entries.take(11).map((e) => e.key).toList()..sort();
      if (positions.length < 11) {
        setState(() => _error =
            '조건에 맞는 데이터가 부족합니다. 조건을 넓혀보세요. (팀컬러/포메이션 전체 등)');
        return;
      }

      // 슬롯별 1순위 카드 배정 — spid 중복 방지 (웹 fillEmptyFromRanker와 동일)
      final used = <String>{};
      final slots = <_Slot>[];
      for (final pos in positions) {
        Map<String, dynamic>? pick;
        for (final p in (picksByPos['$pos'] ?? [])) {
          final spid = '${p['spid']}';
          if (used.contains(spid)) continue;
          pick = Map<String, dynamic>.from(p);
          used.add(spid);
          break;
        }
        slots.add(_Slot(pos, pick));
      }

      setState(() {
        _slots = slots;
        _picksByPos = picksByPos;
        _base = (data['base'] as num? ?? 0).toInt();
        _snapDate = data['snap_date'] ?? '';
      });
      _enrichAndSummarize();
    } catch (e) {
      setState(() => _error = '네트워크 오류가 발생했습니다.');
    } finally {
      setState(() => _generating = false);
    }
  }

  // ── 스쿼드 요약: 선수 필드(급여·OVR·시세) 조회 + 팀컬러 계산 ──
  Future<void> _enrichAndSummarize() async {
    setState(() {
      _summaryLoading = true;
      _tcCalc = null;
    });
    final picks = _slots.where((s) => s.pick != null).toList();
    for (var i = 0; i < picks.length; i += 4) {
      await Future.wait(picks.skip(i).take(4).map((s) async {
        final spid = (s.pick!['spid'] as num).toInt();
        if (_fields.containsKey(spid)) return;
        try {
          final r = await http.get(
            Uri.parse('${ApiService.baseUrl}/api/user/squad/player-fields'
                '?spid=$spid'),
          ).timeout(const Duration(seconds: 25));
          final d = json.decode(r.body);
          if (d['success'] == true) {
            _fields[spid] = Map<String, dynamic>.from(d);
          }
        } catch (e) {
          print('[SquadTab] 선수 필드($spid) 조회 실패: $e');
        }
      }));
      if (mounted) setState(() {});
    }
    await _calcTeamColor();
    if (mounted) setState(() => _summaryLoading = false);
  }

  Future<void> _calcTeamColor() async {
    final players = _slots
        .where((s) => s.pick != null)
        .map((s) => {
              'spid': (s.pick!['spid'] as num).toInt(),
              'grade': (s.pick!['grade'] as num?)?.toInt() ?? 1,
              'role': kSpposRole[s.spPos] ?? 'cm',
              'sp_position': s.spPos,
              'player_name': s.pick!['name'] ?? '',
            })
        .toList();
    if (players.length < 11) return;
    try {
      final r = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/api/user/squad/teamcolor'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'formation':
                  _formation.isNotEmpty ? _formation : '4-1-2-3',
              'adap': 5,
              'players': players,
            }),
          )
          .timeout(const Duration(seconds: 40));
      final d = json.decode(r.body);
      if (mounted && d['success'] == true) {
        setState(() => _tcCalc = Map<String, dynamic>.from(d));
      }
    } catch (e) {
      print('[SquadTab] 팀컬러 계산 실패: $e');
    }
  }

  int? _slotOvr(_Slot slot) {
    final pick = slot.pick;
    if (pick == null) return null;
    final spid = (pick['spid'] as num).toInt();
    // 팀컬러 포함 최종 OVR (서버 계산값 우선 — 웹과 동일)
    final calcOvr = (_tcCalc?['ovr_by_spid'] as Map?)?['$spid'];
    if (calcOvr is num) return calcOvr.toInt();
    final eo = _fields[spid]?['each_ovr']?.toString();
    if (eo == null || eo.isEmpty) return null;
    final vals = eo.split(',');
    if (slot.spPos >= vals.length) return null;
    final base = int.tryParse(vals[slot.spPos].trim());
    if (base == null || base == 0) return null;
    return base +
        (kGradeBonus[(pick['grade'] as num?)?.toInt() ?? 1] ?? 0);
  }

  num? _slotPrice(_Slot slot) {
    final pick = slot.pick;
    if (pick == null) return null;
    final spid = (pick['spid'] as num).toInt();
    final ep = _fields[spid]?['each_price']?.toString();
    if (ep == null || ep.isEmpty) return null;
    final vals = ep.split('|');
    final grade = (pick['grade'] as num?)?.toInt() ?? 1;
    if (grade >= vals.length) return null;
    return num.tryParse(vals[grade].replaceAll(',', ''));
  }

  Widget _summaryCard() {
    num totalPay = 0;
    var payKnown = 0;
    num totalPrice = 0;
    var priceKnown = 0;
    for (final s in _slots.where((s) => s.pick != null)) {
      final spid = (s.pick!['spid'] as num).toInt();
      final pay = _fields[spid]?['pay'];
      if (pay is num) {
        totalPay += pay;
        payKnown++;
      }
      final price = _slotPrice(s);
      if (price != null) {
        totalPrice += price;
        priceKnown++;
      }
    }
    // 팀컬러 발동 목록 (소속/특성/강화 — 특성은 '특별' 표기)
    final tcEntries = <Map<String, String>>[];
    final tc = _tcCalc?['total_team_color'] as Map?;
    if (tc != null) {
      for (final sec in const [
        ['affiliation', '소속'],
        ['feature', '특별'],
        ['enhance', '강화'],
      ]) {
        final entries = tc[sec[0]] as Map? ?? {};
        for (final e in entries.values) {
          if (e is! Map) continue;
          final cnt = e['playercnt'] ?? (e['playerlist'] as List?)?.length ?? '';
          tcEntries.add({
            'label': sec[1],
            'name': '${e['name'] ?? ''}${e['lv'] != null ? ' Lv.${e['lv']}' : ''}',
            'cnt': '$cnt',
          });
        }
      }
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('총 급여',
                          style: TextStyle(fontSize: 10, color: _subColor)),
                      Text(
                          payKnown == 0
                              ? (_summaryLoading ? '조회 중...' : '-')
                              : '$totalPay / 310',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: totalPay > 310 ? Colors.red : null)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('구단가치 (시세 합)',
                          style: TextStyle(fontSize: 10, color: _subColor)),
                      Text(
                          priceKnown == 0
                              ? (_summaryLoading ? '조회 중...' : '-')
                              : formatBp(totalPrice),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('팀컬러', style: TextStyle(fontSize: 10, color: _subColor)),
            const SizedBox(height: 4),
            if (_tcCalc == null)
              Text(_summaryLoading ? '팀컬러 계산 중...' : '팀컬러 계산 실패 (기본 OVR 표시)',
                  style: TextStyle(fontSize: 12, color: _subColor))
            else if (tcEntries.isEmpty)
              Text('발동한 팀컬러가 없습니다.',
                  style: TextStyle(fontSize: 12, color: _subColor))
            else
              Wrap(
                spacing: 6,
                runSpacing: 5,
                children: [
                  for (final e in tcEntries)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: e['label'] == '특별'
                            ? _accent.withOpacity(0.18)
                            : Colors.grey.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: e['label'] == '특별'
                            ? Border.all(color: _accent.withOpacity(0.5))
                            : null,
                      ),
                      child: Text(
                          '${e['label'] == '특별' ? '★ ' : ''}${e['name']} · ${e['cnt']}명',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: e['label'] == '특별' ? _accent : null)),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // 슬롯 탭 → 해당 자리 랭커픽 후보로 교체 (커스텀)
  void _showCandidates(_Slot slot) {
    final cands = _picksByPos['${slot.spPos}'] ?? [];
    if (cands.isEmpty) return;
    final usedSpids = _slots
        .where((s) => s != slot && s.pick != null)
        .map((s) => '${s.pick!['spid']}')
        .toSet();
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '${kSpposRole[slot.spPos]?.toUpperCase()} 자리 랭커픽 (사용 랭커 수 순)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: cands.length,
                itemBuilder: (context, i) {
                  final p = cands[i];
                  final spid = '${p['spid']}';
                  final dup = usedSpids.contains(spid);
                  final users = (p['users'] as num? ?? 0).toInt();
                  final pct = _base > 0
                      ? (users * 100.0 / _base).toStringAsFixed(1)
                      : '-';
                  return ListTile(
                    enabled: !dup,
                    leading: ClipOval(
                      child: Image.network(
                        p['face_url'] ?? '',
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) =>
                            const Icon(Icons.person, size: 40),
                      ),
                    ),
                    title: Text('${p['name']}'
                        '${dup ? ' (다른 자리 사용 중)' : ''}'),
                    subtitle: Row(
                      children: [
                        SeasonBadge(
                            spid: p['spid'] as num?,
                            height: 13,
                            fallbackText: p['season']?.toString()),
                        const SizedBox(width: 6),
                        Text('$users명 ($pct%)',
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    trailing: GradeBadge(
                        grade: (p['grade'] as num? ?? 1).toInt(),
                        fontSize: 12),
                    onTap: dup
                        ? null
                        : () {
                            setState(() =>
                                slot.pick = Map<String, dynamic>.from(p));
                            Navigator.pop(context);
                          },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _condPanel() {
    final tcs = (_meta?['teamcolors'] as List? ?? []);
    final fms = (_meta?['formations'] as List? ?? []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: PillTabs(
                labels: const ['감독모드', '1vs1'],
                selectedIndex: _mode == 'manager' ? 0 : 1,
                onSelected: (i) {
                  setState(() => _mode = i == 0 ? 'manager' : '1vs1');
                  _loadMeta();
                },
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: _top,
              items: _topOptions
                  .map((t) => DropdownMenuItem(
                      value: t, child: Text(t == 10000 ? '전체' : '상위 $t')))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _top = v);
                _loadMeta();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButton<String>(
                value: _teamcolor,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: '', child: Text('전체 팀컬러')),
                  ...tcs.map((t) => DropdownMenuItem(
                        value: t['name'] as String,
                        child: Text('${t['name']} (${t['pct']}%)',
                            overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) => setState(() => _teamcolor = v ?? ''),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButton<String>(
                value: _formation,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: '', child: Text('전체 포메이션')),
                  ...fms.map((f) => DropdownMenuItem(
                        value: f['name'] as String,
                        child: Text('${f['name']} (${f['pct']}%)',
                            overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) => setState(() => _formation = v ?? ''),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_metaLoading || _generating) ? null : _generate,
            icon: _generating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_fix_high, size: 18),
            label: Text(_generating ? '생성 중...' : '랭커 스쿼드 생성'),
          ),
        ),
      ],
    );
  }

  Widget _slotCard(_Slot slot, double cardW) {
    final pick = slot.pick;
    final role = (kSpposRole[slot.spPos] ?? '').toUpperCase();
    return GestureDetector(
      onTap: () => _showCandidates(slot),
      child: SizedBox(
        width: cardW,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: cardW * 0.62,
                  height: cardW * 0.62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black26,
                    border: Border.all(color: Colors.white70, width: 1.5),
                  ),
                  child: ClipOval(
                    child: pick == null
                        ? const Icon(Icons.person_off,
                            color: Colors.white54, size: 22)
                        : Image.network(
                            pick['face_url'] ?? '',
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => const Icon(Icons.person,
                                color: Colors.white70, size: 22),
                          ),
                  ),
                ),
                Positioned(
                  top: -6,
                  left: -6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: posColor(slot.spPos),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(role,
                        style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ),
                ),
                if (pick != null)
                  Positioned(
                    bottom: -3,
                    right: -5,
                    child: GradeBadge(
                        grade: (pick['grade'] as num? ?? 1).toInt(),
                        fontSize: 8.5),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              pick == null ? '비어 있음' : '${pick['name']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 3)]),
            ),
            // OVR + 시즌 이미지 (사용자 지정)
            if (pick != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_slotOvr(slot) != null)
                    Text('${_slotOvr(slot)}',
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFFFE082),
                            shadows: [
                              Shadow(color: Colors.black87, blurRadius: 3)
                            ])),
                  const SizedBox(width: 3),
                  SeasonBadge(
                      spid: pick['spid'] as num?,
                      height: 11,
                      fallbackText: pick['season']?.toString()),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _field() {
    return AspectRatio(
      aspectRatio: 0.78,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final cardW = w / 5.6;
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
              ),
              border: Border.all(color: Colors.white24),
            ),
            child: Stack(
              children: [
                // 하프라인·센터서클 (간단 필드 마킹)
                Positioned(
                  top: h * 0.42,
                  left: 0,
                  right: 0,
                  child: Container(height: 1, color: Colors.white24),
                ),
                Positioned(
                  top: h * 0.42 - w * 0.09,
                  left: w / 2 - w * 0.09,
                  child: Container(
                    width: w * 0.18,
                    height: w * 0.18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24),
                    ),
                  ),
                ),
                for (final slot in _slots)
                  Builder(builder: (context) {
                    final role = kSpposRole[slot.spPos] ?? 'cm';
                    final coord = kRoleCoord[role] ?? const [50, 40];
                    // y(-15~85, 공격 위) → 세로 비율. 여백을 두고 배치
                    final fx = coord[0] / 100.0;
                    final fy = (85 - coord[1]) / 100.0;
                    return Positioned(
                      left: (w - cardW) * fx,
                      top: 8 + (h - cardW * 0.62 - 42) * fy,
                      child: _slotCard(slot, cardW),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _condPanel(),
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 12),
          if (_slots.isNotEmpty) ...[
            _summaryCard(),
            _field(),
            const SizedBox(height: 8),
            Text(
              '카드를 누르면 그 자리의 랭커픽 후보로 교체할 수 있습니다.'
              '${_snapDate.isNotEmpty ? ' ($_snapDate 수집 기준)' : ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ] else if (!_metaLoading)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.groups,
                        size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text('조건을 고르고 "랭커 스쿼드 생성"을 눌러보세요.',
                        style: TextStyle(color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ),
          if (_metaLoading)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
