import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/positions.dart';
import '../services/api_service.dart';
import '../services/trait_store.dart';
import '../utils/fc_format.dart';
import 'badges.dart';
import 'pill_tabs.dart';
import 'player_field_card.dart';

/// 스쿼드 탭 — 스쿼드메이커 (2026-08-19 웹 대시보드 완전 동일화, 사용자 확정).
/// 웹 static/user/squad.js 기능 이식:
///   포메이션 직접 선택 · 적응도 1~5 · 선수명 검색 배치 · 강화 1~13 변경 ·
///   시즌 카드 변경 · 슬롯 제거/초기화 · 유저 스쿼드 불러오기(커스텀 흐름) ·
///   카드별 급여/시세/신규특성 · 팀컬러 로고/발동 스킬 · 저장/불러오기 · 이미지 공유
/// 서버: /api/user/squad/* (무인증 공개)
class SquadTab extends StatefulWidget {
  const SquadTab({Key? key}) : super(key: key);

  @override
  State<SquadTab> createState() => _SquadTabState();
}

/// 슬롯 하나 — 역할/포지션 + 배치된 선수(전체 메타) + 강화 단계
class _Slot {
  String role;
  int spPos;
  Map<String, dynamic>? player; // /players 메타 (spid·name·season·pay·eachOvr·eachPrice·face_url...)
  int grade;
  _Slot(this.role, this.spPos, {this.player, this.grade = 1});
}

class _SquadTabState extends State<SquadTab> with AutomaticKeepAliveClientMixin {
  // ── 랭커 스쿼드 조건 ──
  String _mode = 'manager';
  int _top = 1000;
  String _teamcolor = '';
  String _formationCond = '';
  bool _metaLoading = false;
  bool _generating = false;
  String? _error;
  Map<String, dynamic>? _meta; // teamcolors/formations/snap_date

  // ── 스쿼드 본체 (웹 state 이식) ──
  String _formation = '4-3-3'; // 팀컬러 계산 payload용 포메이션 문자열
  String? _customLabel; // 커스텀 포메이션 라벨 (랭커/유저 스쿼드) — null이면 표준
  int _adap = 5;
  List<_Slot> _slots = [];
  Map<String, dynamic>? _tcCalc; // 팀컬러 계산 응답
  int _calcSeq = 0;
  Timer? _calcTimer;

  Map<String, List<dynamic>> _picksByPos = {};
  int _base = 0; // 조건 내 스쿼드 수 (사용률 % 분모)
  String _snapDate = '';
  final Map<int, Map<String, dynamic>> _fields = {}; // spid → player-fields
  bool _userLoading = false; // 유저 스쿼드 불러오는 중
  final GlobalKey _pitchKey = GlobalKey(); // 필드 캡처용 RepaintBoundary

  static const _topOptions = [200, 1000, 3000, 5000, 10000];
  static const _payLimit = 310; // 급여 상한 (초과 시에만 강조 — 패치로 오를 수 있음)
  static const _storageKey = 'squad_saved_v1';

  @override
  bool get wantKeepAlive => true;

  Color get _accent => Theme.of(context).colorScheme.primary;
  Color get _subColor => Colors.grey.shade500;
  Color get _rose => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFE58AA8)
      : const Color(0xFFD1567F);

  @override
  void initState() {
    super.initState();
    _buildSlots(_formation, keepPlayers: false);
    _loadMeta();
  }

  @override
  void dispose() {
    _calcTimer?.cancel();
    super.dispose();
  }

  // ── 슬롯/포메이션 (웹 buildSlots 이식) ──
  void _buildSlots(String formation, {required bool keepPlayers}) {
    final roles = kFormations[formation] ?? kFormations['4-3-3']!;
    final prev = keepPlayers
        ? _slots.where((s) => s.player != null).toList()
        : <_Slot>[];
    final used = <int>{};
    _slots = roles.map((role) {
      final slot = _Slot(role, kRoleSppos[role] ?? 25);
      // 포메이션 변경 시 같은 역할 → 같은 자리 유지
      for (var i = 0; i < prev.length; i++) {
        if (!used.contains(i) && prev[i].role == role) {
          slot.player = prev[i].player;
          slot.grade = prev[i].grade;
          used.add(i);
          break;
        }
      }
      return slot;
    }).toList();
    // 남은 선수는 빈 슬롯에 순서대로 (역할이 사라진 경우)
    for (var i = 0; i < prev.length; i++) {
      if (used.contains(i)) continue;
      final empty = _slots.where((s) => s.player == null).toList();
      if (empty.isEmpty) break;
      empty.first.player = prev[i].player;
      empty.first.grade = prev[i].grade;
      used.add(i);
    }
  }

  List<_Slot> get _filled => _slots.where((s) => s.player != null).toList();

  // ── 메타/가격/OVR 헬퍼 (웹과 동일 규칙) ──
  static num _parseBp(String? s) {
    final digits = (s ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 0;
    return int.tryParse(digits) ?? 0;
  }

  /// 강화단계별 시세: eachPrice = "0|1강|…|13강"
  num _priceAt(Map<String, dynamic> player, int grade) {
    final ep = player['eachPrice']?.toString() ?? '';
    if (ep.isEmpty) return 0;
    final parts = ep.split('|');
    if (grade >= parts.length) return 0;
    return _parseBp(parts[grade]);
  }

  /// 슬롯 포지션 기준 0강 OVR (eachOvr 기준 — 데이터센터 표기 OVR과 혼용 금지)
  int _eachOvrAt(Map<String, dynamic> player, int spPos) {
    final eo = player['eachOvr']?.toString() ?? '';
    if (eo.isEmpty) return 0;
    final vals = eo.split(',');
    if (spPos >= vals.length) return 0;
    return int.tryParse(vals[spPos].trim()) ?? 0;
  }

  /// 최종 OVR: 서버 계산값 우선, 없으면 로컬 근사(팀컬러 제외)
  int? _slotOvr(_Slot slot) {
    final p = slot.player;
    if (p == null) return null;
    final spid = (p['spid'] as num).toInt();
    final calcOvr = (_tcCalc?['ovr_by_spid'] as Map?)?['$spid'];
    if (calcOvr is num) return calcOvr.toInt();
    final base = _eachOvrAt(p, slot.spPos);
    if (base == 0) return null;
    return base + (kGradeBonus[slot.grade] ?? 0) + (kAdapBonus[_adap] ?? 0);
  }

  /// 같은 선수의 시즌 카드들은 pid(선수 고유번호)가 동일 — spid 뒤 6자리
  static int _playerPid(Map<String, dynamic> p) {
    if (p['pid'] != null) return (p['pid'] as num).toInt();
    return (p['spid'] as num).toInt() % 1000000;
  }

  /// 성만 남기기 (필드 위 공간 절약 — "킬리안 음바페" → "음바페")
  static String _shortName(String? name) {
    final parts = (name ?? '').trim().split(' ');
    return parts.isEmpty ? '' : parts.last;
  }

  // ── 서버 조회 ──
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
          if (_teamcolor.isNotEmpty && !tcs.contains(_teamcolor)) {
            _teamcolor = '';
          }
          final fms = (data['formations'] as List? ?? [])
              .map((f) => f['name'] as String)
              .toSet();
          if (_formationCond.isNotEmpty && !fms.contains(_formationCond)) {
            _formationCond = '';
          }
        });
      } else {
        setState(() => _error = data['message'] ?? '조건 목록을 불러오지 못했습니다.');
      }
    } catch (e) {
      setState(() => _error = '네트워크 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _metaLoading = false);
    }
  }

  /// 선수명 검색 (/players — 전체 메타)
  Future<List<Map<String, dynamic>>?> _searchPlayers(String name) async {
    try {
      final r = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/user/squad/players'
            '?name=${Uri.encodeComponent(name)}'),
      ).timeout(const Duration(seconds: 25));
      final d = json.decode(r.body);
      if (d['success'] == true) {
        return (d['players'] as List? ?? [])
            .map((p) => Map<String, dynamic>.from(p))
            .toList();
      }
    } catch (e) {
      print('[SquadTab] 선수 검색($name) 실패: $e');
    }
    return null;
  }

  /// 선수 필드(급여·eachOvr·시세) 확보 후 같은 spid 슬롯에 병합
  Future<void> _ensureFields(int spid) async {
    if (!_fields.containsKey(spid)) {
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
    }
    final f = _fields[spid];
    if (f == null) return;
    var changed = false;
    for (final s in _slots) {
      final p = s.player;
      if (p != null && (p['spid'] as num).toInt() == spid) {
        p['pay'] ??= f['pay'];
        if ((p['eachOvr']?.toString() ?? '').isEmpty) {
          p['eachOvr'] = f['each_ovr'];
        }
        if ((p['eachPrice']?.toString() ?? '').isEmpty) {
          p['eachPrice'] = f['each_price'];
        }
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});
  }

  // ── 팀컬러 계산 (디바운스 + 순번 가드 — 웹 requestCalc 이식) ──
  void _scheduleCalc() {
    _calcTimer?.cancel();
    _calcTimer = Timer(const Duration(milliseconds: 700), _requestCalc);
  }

  Future<void> _requestCalc() async {
    final filled = _filled;
    setState(() => _tcCalc = null);
    if (filled.isEmpty) return;
    final seq = ++_calcSeq;
    try {
      final r = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/api/user/squad/teamcolor'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'formation': _formation.isNotEmpty ? _formation : '4-1-2-3',
              'adap': _adap,
              'players': filled
                  .map((s) => {
                        'spid': (s.player!['spid'] as num).toInt(),
                        'grade': s.grade,
                        'role': s.role,
                        'sp_position': s.spPos,
                        // 서버 메타 캐시 미스 시 재검색용 (워커 분산 대응)
                        'player_name': s.player!['name'] ?? '',
                      })
                  .toList(),
            }),
          )
          .timeout(const Duration(seconds: 40));
      final d = json.decode(r.body);
      if (!mounted || seq != _calcSeq) return; // 이후 요청이 있으면 무시
      if (d['success'] == true) {
        setState(() => _tcCalc = Map<String, dynamic>.from(d));
      }
    } catch (e) {
      print('[SquadTab] 팀컬러 계산 실패: $e');
    }
  }

  // ── 배치 ──
  bool _placePlayer(int idx, Map<String, dynamic> player, int grade) {
    final dup = _slots.asMap().entries.any((e) =>
        e.key != idx &&
        e.value.player != null &&
        '${e.value.player!['spid']}' == '${player['spid']}');
    if (dup) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미 배치된 선수입니다.')));
      return false;
    }
    setState(() {
      _slots[idx].player = Map<String, dynamic>.from(player);
      _slots[idx].grade = grade;
    });
    _ensureFields((player['spid'] as num).toInt());
    TraitStore.ensure(player['spid'] as num?);
    _scheduleCalc();
    return true;
  }

  /// 랭커픽 카드 배치 (부분 메타 → player-fields로 보강, 검증된 기존 방식 재사용)
  bool _placePick(int idx, Map<String, dynamic> pick) {
    return _placePlayer(
        idx,
        {
          'spid': pick['spid'],
          'name': pick['name'],
          'season': pick['season'],
          'face_url': pick['face_url'],
        },
        (pick['grade'] as num? ?? 1).toInt());
  }

  // ── 랭커 스쿼드 생성 (기존 검증 로직 유지) ──
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
            '&formation=${Uri.encodeComponent(_formationCond)}'),
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
        final slot = _Slot(kSpposRole[pos] ?? 'st', pos);
        for (final p in (picksByPos['$pos'] ?? [])) {
          final spid = '${p['spid']}';
          if (used.contains(spid)) continue;
          slot.player = {
            'spid': p['spid'],
            'name': p['name'],
            'season': p['season'],
            'face_url': p['face_url'],
          };
          slot.grade = (p['grade'] as num? ?? 1).toInt();
          used.add(spid);
          break;
        }
        slots.add(slot);
      }

      setState(() {
        _slots = slots;
        _picksByPos = picksByPos;
        _base = (data['base'] as num? ?? 0).toInt();
        _snapDate = data['snap_date'] ?? '';
        _customLabel = '랭커 포메이션'
            '${_formationCond.isNotEmpty ? ' ($_formationCond)' : ''}';
        if (_formationCond.isNotEmpty) _formation = _formationCond;
        _tcCalc = null;
      });
      _enrichSlots();
    } catch (e) {
      setState(() => _error = '네트워크 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// 배치된 슬롯들의 급여·eachOvr·시세 확보 (4개씩 병렬) 후 팀컬러 계산
  Future<void> _enrichSlots() async {
    final picks = _filled;
    for (var i = 0; i < picks.length; i += 4) {
      await Future.wait(picks.skip(i).take(4).map(
          (s) => _ensureFields((s.player!['spid'] as num).toInt())));
    }
    _scheduleCalc();
  }

  // ── 유저 스쿼드 불러오기 → 커스텀 (웹 loadUserSquad 이식) ──
  Future<void> _loadUserSquad(String name, String mode) async {
    if (name.isEmpty || _userLoading) return;
    setState(() => _userLoading = true);
    try {
      final r = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/user/squad/user-squad'
            '?name=${Uri.encodeComponent(name)}&mode=$mode'),
      ).timeout(const Duration(seconds: 40));
      final d = json.decode(r.body);
      if (d['success'] != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(d['message'] ?? '스쿼드 조회에 실패했습니다.')));
        }
        return;
      }
      final rows = (d['players'] as List? ?? [])
          .map((p) => Map<String, dynamic>.from(p))
          .toList();
      // 불러온 포지션 그대로 커스텀 슬롯 구성
      setState(() {
        _slots = rows.map((p) {
          final sp = (p['sp_position'] as num? ?? 25).toInt();
          return _Slot(kSpposRole[sp] ?? 'st', sp,
              grade: (p['grade'] as num? ?? 1).toInt());
        }).toList();
        _formation = d['formation5']?.toString() ?? '4-1-2-3';
        _customLabel = '$name의 스쿼드 ($_formation)';
        _tcCalc = null;
      });
      // 선수별 전체 메타(eachOvr·시세·얼굴)를 순차 확보해 배치 (웹과 동일)
      var missed = 0;
      for (var i = 0; i < rows.length && i < _slots.length; i++) {
        final pd = rows[i];
        final players = await _searchPlayers(pd['name']?.toString() ?? '');
        final found = (players ?? [])
            .where((c) => '${c['spid']}' == '${pd['spid']}')
            .toList();
        if (found.isNotEmpty) {
          _slots[i].player = found.first;
          TraitStore.ensure(found.first['spid'] as num?);
        } else {
          missed++;
        }
        if (mounted) setState(() {});
      }
      if (missed > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$missed명은 선수 정보를 찾지 못해 비워뒀습니다.')));
      }
      _scheduleCalc();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('네트워크 오류가 발생했습니다.')));
      }
    } finally {
      if (mounted) setState(() => _userLoading = false);
    }
  }

  void _openUserSquadSheet() {
    final nameCtrl = TextEditingController();
    var mode = 'manager';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('유저 스쿼드 불러오기',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('감독명의 가장 최근 경기 선발 11명을 불러와 자유롭게 수정할 수 있습니다.',
                  style: TextStyle(fontSize: 12, color: _subColor)),
              const SizedBox(height: 12),
              PillTabs(
                labels: const ['감독모드', '1vs1'],
                selectedIndex: mode == 'manager' ? 0 : 1,
                onSelected: (i) =>
                    setSheet(() => mode = i == 0 ? 'manager' : '1vs1'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                    labelText: '감독명',
                    border: OutlineInputBorder(),
                    isDense: true),
                onSubmitted: (_) {
                  Navigator.pop(context);
                  _loadUserSquad(nameCtrl.text.trim(), mode);
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _loadUserSquad(nameCtrl.text.trim(), mode);
                  },
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('불러오기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 슬롯 상호작용: 빈 슬롯 → 검색 시트 / 배치 슬롯 → 편집 시트 ──
  void _onSlotTap(int idx) {
    if (_slots[idx].player == null) {
      _openSearchSheet(idx);
    } else {
      _openEditSheet(idx);
    }
  }

  /// 랭커픽 후보 (정확 포지션 → 같은 계열 폴백, 웹 picksForSlot 이식)
  List<Map<String, dynamic>> _picksForSlot(_Slot slot) {
    final codes = kRoleFallback[slot.role] ?? [slot.role.toUpperCase()];
    final out = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final code in codes) {
      final sp = kRoleSppos[code.toLowerCase()];
      if (sp == null) continue;
      for (final p in (_picksByPos['$sp'] ?? [])) {
        if (seen.add('${p['spid']}')) {
          out.add(Map<String, dynamic>.from(p));
        }
      }
    }
    return out;
  }

  void _openSearchSheet(int idx) {
    final slot = _slots[idx];
    final searchCtrl = TextEditingController();
    var pane = 0; // 0=검색, 1=이 자리 랭커픽
    List<Map<String, dynamic>>? results;
    var searching = false;
    Timer? debounce;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          Future<void> doSearch(String name) async {
            if (name.trim().length < 2) return;
            setSheet(() => searching = true);
            final r = await _searchPlayers(name.trim());
            if (searchCtrl.text.trim() != name.trim()) return; // 입력 변경 무시
            setSheet(() {
              searching = false;
              results = r ?? [];
            });
          }

          final picks = _picksForSlot(slot).take(15).toList();
          final usedSpids = _slots
              .asMap()
              .entries
              .where((e) => e.key != idx && e.value.player != null)
              .map((e) => '${e.value.player!['spid']}')
              .toSet();

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            builder: (context, controller) => Padding(
              padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 14,
                  bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${slot.role.toUpperCase()} 자리 선수 선택',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  PillTabs(
                    labels: const ['선수 검색', '이 자리 랭커픽'],
                    selectedIndex: pane,
                    onSelected: (i) => setSheet(() => pane = i),
                  ),
                  const SizedBox(height: 10),
                  if (pane == 0) ...[
                    TextField(
                      controller: searchCtrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                          hintText: '선수명 (게임 내 등록명, 이름 일부 가능)',
                          isDense: true,
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.search, size: 18)),
                      onChanged: (v) {
                        debounce?.cancel();
                        debounce = Timer(const Duration(milliseconds: 350),
                            () => doSearch(v));
                      },
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: searching
                          ? const Center(child: CircularProgressIndicator())
                          : results == null
                              ? Center(
                                  child: Text('선수명을 입력하세요.',
                                      style: TextStyle(
                                          fontSize: 12.5, color: _subColor)))
                              : results!.isEmpty
                                  ? Center(
                                      child: Text('검색 결과가 없습니다.',
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              color: _subColor)))
                                  : ListView.builder(
                                      controller: controller,
                                      itemCount: results!.length,
                                      itemBuilder: (context, i) {
                                        final p = results![i];
                                        final dup = usedSpids
                                            .contains('${p['spid']}');
                                        return _playerResultRow(
                                          p,
                                          slot: slot,
                                          disabled: dup,
                                          trailing: Text(
                                              '1강 ${formatBp(_priceAt(p, 1))}',
                                              style: const TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight:
                                                      FontWeight.w700)),
                                          onTap: () {
                                            if (_placePlayer(idx, p, 1)) {
                                              Navigator.pop(context);
                                            }
                                          },
                                        );
                                      },
                                    ),
                    ),
                  ] else ...[
                    Text(
                        _picksByPos.isEmpty
                            ? '랭커픽 데이터가 없습니다. 먼저 "랭커 스쿼드 생성"으로 조건을 조회하세요.'
                            : '${_mode == 'manager' ? '감독모드' : '1vs1'} · 상위 $_top위'
                                '${_teamcolor.isNotEmpty ? ' · $_teamcolor' : ' · 전체 팀컬러'}'
                                '${_snapDate.isNotEmpty ? ' ($_snapDate 수집)' : ''}',
                        style: TextStyle(fontSize: 11, color: _subColor)),
                    const SizedBox(height: 6),
                    Expanded(
                      child: picks.isEmpty
                          ? Center(
                              child: Text(
                                  '이 포지션(${slot.role.toUpperCase()})의 랭커 사용 데이터가 없습니다.',
                                  style: TextStyle(
                                      fontSize: 12.5, color: _subColor)))
                          : ListView.builder(
                              controller: controller,
                              itemCount: picks.length,
                              itemBuilder: (context, i) {
                                final p = picks[i];
                                final dup =
                                    usedSpids.contains('${p['spid']}');
                                final users =
                                    (p['users'] as num? ?? 0).toInt();
                                final pct = _base > 0
                                    ? (users * 100.0 / _base)
                                        .toStringAsFixed(1)
                                    : null;
                                return ListTile(
                                  enabled: !dup,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 4),
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
                                  title: Text(
                                      '${p['name']}${dup ? ' (다른 자리 사용 중)' : ''}',
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700)),
                                  subtitle: Row(
                                    children: [
                                      SeasonBadge(
                                          spid: p['spid'] as num?,
                                          height: 13,
                                          fallbackText:
                                              p['season']?.toString()),
                                      const SizedBox(width: 6),
                                      Text(
                                          '랭커 $users명 사용'
                                          '${pct != null ? ' ($pct%)' : ''}',
                                          style: const TextStyle(
                                              fontSize: 12)),
                                    ],
                                  ),
                                  trailing: GradeBadge(
                                      grade:
                                          (p['grade'] as num? ?? 1).toInt(),
                                      fontSize: 12),
                                  onTap: dup
                                      ? null
                                      : () {
                                          if (_placePick(idx, p)) {
                                            Navigator.pop(context);
                                          }
                                        },
                                );
                              },
                            ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() => debounce?.cancel());
  }

  /// 검색/시즌 목록 공용 행 (얼굴 · 이름+시즌 · 포지션/급여/이 자리 0강 OVR · 우측 커스텀)
  Widget _playerResultRow(Map<String, dynamic> p,
      {required _Slot slot,
      bool disabled = false,
      bool isCurrent = false,
      Widget? trailing,
      VoidCallback? onTap}) {
    final posOvr = _eachOvrAt(p, slot.spPos);
    return ListTile(
      enabled: !disabled,
      selected: isCurrent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: ClipOval(
        child: Image.network(
          p['face_url'] ?? '',
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) => const Icon(Icons.person, size: 40),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
                '${p['name'] ?? ''}${disabled ? ' (배치됨)' : ''}'
                '${isCurrent ? ' (현재)' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 6),
          SeasonBadge(
              spid: p['spid'] as num?,
              height: 13,
              fallbackText: p['season']?.toString()),
        ],
      ),
      subtitle: Text(
          '${(p['position'] ?? '').toString().toUpperCase()}'
          ' · 급여 ${p['pay'] ?? '-'}'
          ' · 이 자리 0강 OVR ${posOvr > 0 ? posOvr : '-'}',
          style: TextStyle(fontSize: 11.5, color: _subColor)),
      trailing: trailing,
      onTap: disabled ? null : onTap,
    );
  }

  // ── 선수 편집 시트 (강화 1~13 · 시즌 카드 변경 · 검색/제거 — 웹 편집 팝업 이식) ──
  void _openEditSheet(int idx) {
    List<Map<String, dynamic>>? variants;
    var variantsLoading = true;
    var loadRequested = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          final slot = _slots[idx];
          final p = slot.player;
          if (p == null) return const SizedBox.shrink();

          if (!loadRequested) {
            loadRequested = true;
            _searchPlayers(p['name']?.toString() ?? '').then((players) {
              final pid = _playerPid(p);
              final v = (players ?? [])
                  .where((c) => _playerPid(c) == pid)
                  .toList();
              setSheet(() {
                variants = v;
                variantsLoading = false;
              });
            });
          }

          final ovr = _slotOvr(slot);
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.78,
            maxChildSize: 0.95,
            builder: (context, controller) => ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                Text('${slot.role.toUpperCase()} — ${p['name'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                // 현재 카드 요약
                Row(
                  children: [
                    ClipOval(
                      child: Image.network(
                        p['face_url'] ?? '',
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) =>
                            const Icon(Icons.person, size: 48),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text('${p['name'] ?? ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800)),
                              ),
                              const SizedBox(width: 6),
                              SeasonBadge(
                                  spid: p['spid'] as num?,
                                  height: 14,
                                  fallbackText: p['season']?.toString()),
                            ],
                          ),
                          Text(
                              '${(p['position'] ?? '').toString().toUpperCase()}'
                              ' · 급여 ${p['pay'] ?? '-'}'
                              ' · OVR ${ovr ?? '-'}',
                              style: TextStyle(
                                  fontSize: 12, color: _subColor)),
                          Text(
                              '${slot.grade}강 시세 ${formatBp(_priceAt(p, slot.grade))}',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: _accent)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text('강화 단계',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: _subColor)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var g = 1; g <= 13; g++)
                      GestureDetector(
                        onTap: () {
                          if (g == slot.grade) return;
                          setState(() {
                            slot.grade = g;
                            _tcCalc = null;
                          });
                          setSheet(() {});
                          _scheduleCalc();
                        },
                        child: Container(
                          width: 38,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: g == slot.grade
                                ? _accent.withOpacity(0.20)
                                : Colors.grey.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(8),
                            border: g == slot.grade
                                ? Border.all(color: _accent)
                                : null,
                          ),
                          child: Text('$g',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: g == slot.grade ? _accent : null)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text('시즌 카드 변경 (강화 단계 유지)',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: _subColor)),
                const SizedBox(height: 4),
                if (variantsLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (variants == null || variants!.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('다른 시즌 카드가 없습니다.',
                        style: TextStyle(fontSize: 12.5, color: _subColor)),
                  )
                else
                  for (final c in variants!)
                    _playerResultRow(
                      c,
                      slot: slot,
                      isCurrent: '${c['spid']}' == '${p['spid']}',
                      disabled: '${c['spid']}' != '${p['spid']}' &&
                          _slots.asMap().entries.any((e) =>
                              e.key != idx &&
                              e.value.player != null &&
                              '${e.value.player!['spid']}' == '${c['spid']}'),
                      trailing: Text('1강 ${formatBp(_priceAt(c, 1))}',
                          style: const TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w700)),
                      onTap: () {
                        if ('${c['spid']}' == '${p['spid']}') return;
                        setState(() {
                          slot.player = Map<String, dynamic>.from(c);
                          _tcCalc = null;
                        });
                        TraitStore.ensure(c['spid'] as num?);
                        setSheet(() {});
                        _scheduleCalc();
                      },
                    ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _openSearchSheet(idx);
                        },
                        icon: const Icon(Icons.search, size: 16),
                        label: const Text('다른 선수 검색'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            slot.player = null;
                            slot.grade = 1;
                            _tcCalc = null;
                          });
                          _scheduleCalc();
                          Navigator.pop(context);
                        },
                        icon: Icon(Icons.person_remove,
                            size: 16, color: _rose),
                        label: Text('제거', style: TextStyle(color: _rose)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── 저장/불러오기 (SharedPreferences — 웹 localStorage 이식) ──
  static const _keepFields = [
    'spid', 'pid', 'name', 'season', 'seasonImgBig', 'position',
    'pay', 'eachOvr', 'eachPrice', 'face_url', 'thumb',
  ];

  Map<String, dynamic> _slimPlayer(Map<String, dynamic> p) {
    final out = <String, dynamic>{};
    for (final k in _keepFields) {
      if (p[k] != null) out[k] = p[k];
    }
    return out;
  }

  Future<Map<String, dynamic>> _loadStore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return Map<String, dynamic>.from(
          json.decode(prefs.getString(_storageKey) ?? '{}'));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveStore(Map<String, dynamic> store) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, json.encode(store));
  }

  Future<void> _saveSquad() async {
    if (_filled.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('배치된 선수가 없습니다.')));
      return;
    }
    final nameCtrl = TextEditingController(text: '내 스쿼드');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('스쿼드 저장'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '스쿼드 이름'),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(context, nameCtrl.text.trim()),
              child: const Text('저장')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final store = await _loadStore();
    store[name] = {
      'formation': _formation,
      'custom_label': _customLabel,
      'adap': _adap,
      'saved_at': DateTime.now().toIso8601String(),
      'slots': _slots
          .map((s) => {
                'role': s.role,
                'sp_pos': s.spPos,
                'grade': s.grade,
                'player': s.player == null ? null : _slimPlayer(s.player!),
              })
          .toList(),
    };
    await _saveStore(store);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$name" 저장 완료 (이 기기에 저장됩니다)')));
    }
  }

  Future<void> _openLoadSheet() async {
    final store = await _loadStore();
    if (store.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('저장된 스쿼드가 없습니다.')));
      }
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Text('저장된 스쿼드',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final name in store.keys.toList())
                      ListTile(
                        title: Text(name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            '${store[name]?['custom_label'] ?? store[name]?['formation'] ?? ''}'
                            ' · ${(store[name]?['saved_at'] ?? '').toString().split('T').first}',
                            style: TextStyle(
                                fontSize: 11.5, color: _subColor)),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline,
                              size: 20, color: _rose),
                          onPressed: () async {
                            store.remove(name);
                            await _saveStore(store);
                            setSheet(() {});
                            if (store.isEmpty && context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _applySaved(
                              Map<String, dynamic>.from(store[name] as Map));
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _applySaved(Map<String, dynamic> data) {
    final rows = (data['slots'] as List? ?? [])
        .map((s) => Map<String, dynamic>.from(s))
        .toList();
    if (rows.isEmpty) return;
    setState(() {
      _formation = data['formation']?.toString() ?? '4-3-3';
      _customLabel = data['custom_label']?.toString();
      _adap = (data['adap'] as num? ?? 5).toInt();
      _slots = rows.map((s) {
        final sp = (s['sp_pos'] as num? ??
                kRoleSppos[s['role']?.toString() ?? 'st'] ??
                25)
            .toInt();
        return _Slot(s['role']?.toString() ?? (kSpposRole[sp] ?? 'st'), sp,
            player: s['player'] == null
                ? null
                : Map<String, dynamic>.from(s['player'] as Map),
            grade: (s['grade'] as num? ?? 1).toInt());
      }).toList();
      _tcCalc = null;
    });
    _scheduleCalc();
  }

  // ── 이미지 공유 (RepaintBoundary 캡처 — 웹 html2canvas 대응) ──
  Future<void> _shareImage() async {
    try {
      final boundary = _pitchKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final path = '${dir.path}/squad_${ts.year}${two(ts.month)}${two(ts.day)}'
          '_${two(ts.hour)}${two(ts.minute)}.png';
      final file = File(path);
      await file.writeAsBytes(byteData.buffer.asUint8List());
      await Share.shareXFiles([XFile(path)]);
    } catch (e) {
      print('[SquadTab] 이미지 공유 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이미지 공유에 실패했습니다.')));
      }
    }
  }

  void _clearSquad() {
    if (_filled.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text('배치한 선수를 모두 지울까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _customLabel = null;
                if (!kFormations.containsKey(_formation)) {
                  _formation = '4-3-3';
                }
                _buildSlots(_formation, keepPlayers: false);
                _tcCalc = null;
              });
            },
            child: const Text('초기화'),
          ),
        ],
      ),
    );
  }

  // ── 팀컬러 선택 시트 (콤보 + 직접입력 자동완성 통합 — 모바일형) ──
  void _openTeamcolorSheet() {
    final tcs = (_meta?['teamcolors'] as List? ?? [])
        .map((t) => Map<String, dynamic>.from(t))
        .toList();
    final filterCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          final q = filterCtrl.text.trim().toLowerCase();
          final hits = q.isEmpty
              ? tcs
              : tcs
                  .where((t) =>
                      (t['name'] as String).toLowerCase().contains(q))
                  .toList();
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            builder: (context, controller) => Padding(
              padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 14,
                  bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('팀컬러 선택',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: filterCtrl,
                    decoration: const InputDecoration(
                        hintText: '팀컬러 검색',
                        isDense: true,
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search, size: 18)),
                    onChanged: (_) => setSheet(() {}),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView(
                      controller: controller,
                      children: [
                        ListTile(
                          dense: true,
                          title: const Text('전체 팀컬러'),
                          selected: _teamcolor.isEmpty,
                          onTap: () {
                            setState(() => _teamcolor = '');
                            Navigator.pop(context);
                          },
                        ),
                        for (final t in hits)
                          ListTile(
                            dense: true,
                            title: Text('${t['name']}'),
                            subtitle: Text(
                                '${t['pct'] ?? 0}% (${t['users'] ?? 0}명)',
                                style: TextStyle(
                                    fontSize: 11, color: _subColor)),
                            selected: _teamcolor == t['name'],
                            onTap: () {
                              setState(
                                  () => _teamcolor = t['name'] as String);
                              Navigator.pop(context);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── 조건 패널 ──
  Widget _condPanel() {
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
            // 팀컬러: 검색 가능한 선택 시트 (웹 콤보+직접입력 자동완성 통합)
            Expanded(
              child: InkWell(
                onTap: _openTeamcolorSheet,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                            _teamcolor.isEmpty ? '전체 팀컬러' : _teamcolor,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5)),
                      ),
                      Icon(Icons.arrow_drop_down, color: _subColor),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButton<String>(
                value: _formationCond,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: '', child: Text('전체 포메이션')),
                  ...fms.map((f) => DropdownMenuItem(
                        value: f['name'] as String,
                        child: Text('${f['name']} (${f['pct']}%)',
                            overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (v) => setState(() => _formationCond = v ?? ''),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
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
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _userLoading ? null : _openUserSquadSheet,
                // 좁은 화면에서 '유저 스/쿼드' 두 줄 줄바꿈 방지 — 한 줄 유지 + 축소
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                icon: _userLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.person_search, size: 16),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('유저 스쿼드', maxLines: 1, softWrap: false),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 포메이션 직접 선택 + 적응도 (웹 동일 기능)
        Row(
          children: [
            Expanded(
              child: DropdownButton<String>(
                value: _customLabel != null ? '__custom' : _formation,
                isExpanded: true,
                items: [
                  ...kFormations.keys.map((f) =>
                      DropdownMenuItem(value: f, child: Text('포메이션 $f'))),
                  if (_customLabel != null)
                    DropdownMenuItem(
                        value: '__custom',
                        child: Text(_customLabel!,
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) {
                  if (v == null || v == '__custom') return;
                  setState(() {
                    _formation = v;
                    _customLabel = null;
                    _buildSlots(v, keepPlayers: true);
                    _tcCalc = null;
                  });
                  _scheduleCalc();
                },
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: _adap,
              items: [
                for (var a = 1; a <= 5; a++)
                  DropdownMenuItem(value: a, child: Text('적응도 $a')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _adap = v;
                  _tcCalc = null;
                });
                _scheduleCalc();
              },
            ),
          ],
        ),
      ],
    );
  }

  // ── 요약 카드 (인원/급여/구단가치 + 팀컬러 로고·발동 스킬) ──
  Widget _summaryCard() {
    num totalPay = 0;
    var payKnown = 0;
    num totalPrice = 0;
    for (final s in _filled) {
      final pay = num.tryParse('${s.player!['pay'] ?? ''}');
      if (pay != null) {
        totalPay += pay;
        payKnown++;
      }
      totalPrice += _priceAt(s.player!, s.grade);
    }
    // 팀컬러 발동 목록 (소속/특성/강화 — 로고·발동 스킬 포함, 웹 renderTeamColor 이식)
    final tcEntries = <Map<String, dynamic>>[];
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
          final skills = (e['skill']?.toString() ?? '')
              .split('|')
              .where((s) => s.trim().isNotEmpty)
              .join(' · ');
          tcEntries.add({
            'label': sec[1],
            'name': '${e['name'] ?? ''}',
            'lv': e['lv'],
            'cnt': e['playercnt'] ?? (e['playerlist'] as List?)?.length ?? '',
            'image': e['image']?.toString() ?? '',
            'skill': skills,
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
                      Text('인원',
                          style: TextStyle(fontSize: 10, color: _subColor)),
                      Text('${_filled.length}/11',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('총 급여',
                          style: TextStyle(fontSize: 10, color: _subColor)),
                      Text(
                          payKnown == 0 ? '-' : '$totalPay / $_payLimit',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: totalPay > _payLimit ? _rose : null)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('총 구단가치',
                          style: TextStyle(fontSize: 10, color: _subColor)),
                      Text(totalPrice == 0 ? '-' : formatBp(totalPrice),
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
            if (_filled.isEmpty)
              Text('배치된 선수가 없습니다.',
                  style: TextStyle(fontSize: 12, color: _subColor))
            else if (_tcCalc == null)
              Text('팀컬러 계산 중...',
                  style: TextStyle(fontSize: 12, color: _subColor))
            else if (tcEntries.isEmpty)
              Text('발동한 팀컬러가 없습니다.',
                  style: TextStyle(fontSize: 12, color: _subColor))
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in tcEntries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((e['image'] as String).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Image.network(
                                e['image'] as String,
                                width: 22,
                                height: 22,
                                errorBuilder: (c, err, s) =>
                                    const SizedBox(width: 22, height: 22),
                              ),
                            )
                          else
                            const SizedBox(width: 28),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 5,
                                  crossAxisAlignment:
                                      WrapCrossAlignment.center,
                                  children: [
                                    Text('${e['name']}',
                                        style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w800,
                                            color: e['label'] == '특별'
                                                ? _accent
                                                : null)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: e['label'] == '특별'
                                            ? _accent.withOpacity(0.18)
                                            : Colors.grey.withOpacity(0.14),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                          '${e['label']}'
                                          '${e['lv'] != null ? ' Lv.${e['lv']}' : ''}'
                                          ' · ${e['cnt']}명',
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: e['label'] == '특별'
                                                  ? _accent
                                                  : _subColor)),
                                    ),
                                  ],
                                ),
                                if ((e['skill'] as String).isNotEmpty)
                                  Text('${e['skill']}',
                                      style: TextStyle(
                                          fontSize: 11, color: _subColor)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ── 필드 ──
  Widget _slotCard(int idx, double cardW) {
    final slot = _slots[idx];
    final pick = slot.player;
    final footer = <Widget>[];
    if (pick != null) {
      // 선수명 아래 = 시세만 (OVR·급여·시즌은 카드 코너로 이동 — 2026-08-19 사용자 확정)
      final price = _priceAt(pick, slot.grade);
      if (price > 0) {
        footer.add(Text(formatBp(price),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w600,
                color: Color(0xFFB9E3C6),
                shadows: [Shadow(color: Colors.black87, blurRadius: 3)])));
      }
    }
    return PlayerFieldCard(
      cardW: cardW,
      spPos: slot.spPos,
      spid: pick?['spid'] as num?,
      faceUrl: pick?['face_url']?.toString(),
      name: pick == null ? '' : _shortName(pick['name']?.toString()),
      grade: pick == null ? null : slot.grade,
      ovr: pick == null ? null : _slotOvr(slot),
      pay: pick?['pay'],
      seasonFallback: pick?['season']?.toString(),
      footerLines: footer,
      empty: pick == null,
      onTap: () => _onSlotTap(idx),
    );
  }

  Widget _field() {
    return RepaintBoundary(
      key: _pitchKey,
      child: AspectRatio(
        aspectRatio: 0.72,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final cardW = w / 5.4;
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
                  for (var i = 0; i < _slots.length; i++)
                    Builder(builder: (context) {
                      final slot = _slots[i];
                      final role = kSpposRole[slot.spPos] ?? 'cm';
                      final coord = kRoleCoord[role] ?? const [50, 40];
                      final fx = coord[0] / 100.0;
                      final fy = (85 - coord[1]) / 100.0;
                      return Positioned(
                        left: (w - cardW) * fx,
                        top: 8 + (h - cardW * 0.62 - 58) * fy,
                        child: _slotCard(i, cardW),
                      );
                    }),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _actionBar() {
    Widget btn(IconData icon, String label, VoidCallback onTap) => Expanded(
          child: OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 15),
            label: Text(label, style: const TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4)),
          ),
        );
    return Row(
      children: [
        btn(Icons.save_outlined, '저장', _saveSquad),
        const SizedBox(width: 6),
        btn(Icons.folder_open, '불러오기', _openLoadSheet),
        const SizedBox(width: 6),
        btn(Icons.refresh, '초기화', _clearSquad),
        const SizedBox(width: 6),
        btn(Icons.ios_share, '이미지', _shareImage),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _loadMeta,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                  color: _rose.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!, style: TextStyle(color: _rose)),
              ),
            const SizedBox(height: 12),
            _summaryCard(),
            _field(),
            const SizedBox(height: 8),
            _actionBar(),
            const SizedBox(height: 6),
            Text(
              '빈 자리를 누르면 선수 검색/랭커픽, 배치된 카드를 누르면 강화·시즌 변경이 가능합니다.'
              '${_snapDate.isNotEmpty ? ' ($_snapDate 랭커픽 수집 기준)' : ''}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            if (_metaLoading)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}
