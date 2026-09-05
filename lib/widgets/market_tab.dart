import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'badges.dart';
import '../services/api_service.dart';
import 'pill_tabs.dart';

/// 이적시장 탭 — 본인 넥슨 오픈API 키를 기기에만 저장하고 앱이 넥슨에 직접 호출
/// (서버 경유 0 — 사용자 결정 구조). 거래내역(구매/판매) + 스쿼드 손익.
/// 웹 대시보드 이적시장 카드와 동일한 안내·링크 제공.
class MarketTab extends StatefulWidget {
  const MarketTab({Key? key}) : super(key: key);

  @override
  State<MarketTab> createState() => _MarketTabState();
}

class _MarketTabState extends State<MarketTab>
    with AutomaticKeepAliveClientMixin {
  static const _keyPref = 'nexon_api_key';        // 구버전 단일 키 (마이그레이션용)
  static const _namePref = 'nexon_api_nickname';  // 구버전 단일 감독명 (마이그레이션용)
  // 다중 계정 (2026-09-05): 감독명+API 키 묶음 목록과 현재 선택 인덱스. 한 사람이 여러 계정을 쓰는 경우 대비.
  static const _accountsPref = 'nexon_api_accounts_v1';
  static const _accountIdxPref = 'nexon_api_account_index';
  static const _issueUrl = 'https://openapi.nexon.com/ko/game/fconline/?id=2';
  static const _apiBase = 'https://open.api.nexon.com';

  // spid/시즌 메타 (넥슨 static 메타 — 세션당 1회 로드, 앱 메모리 캐시)
  static Map<int, String>? _spidNames;
  static Map<int, String>? _seasonNames;

  final _keyController = TextEditingController();
  final _nameController = TextEditingController();
  final _filterController = TextEditingController();

  String? _apiKey;
  String? _nickname;
  bool _saving = false;
  String? _error;
  List<Map<String, String>> _accounts = []; // [{name, key}] — 현재 계정은 _accountIdx
  int _accountIdx = 0;
  bool _addingAccount = false; // '계정 추가' 중이면 기존 계정이 있어도 등록 화면 표시

  int _seg = 0; // 0=거래내역, 1=스쿼드 손익
  String _tradeType = 'buy';
  bool _tradesLoading = false;
  bool _metaLoading = false;
  final Map<String, List<Map<String, dynamic>>> _trades = {
    'buy': [],
    'sell': []
  };
  final Map<String, int> _offsets = {'buy': 0, 'sell': 0};
  final Map<String, bool> _exhausted = {'buy': false, 'sell': false};

  bool _pnlLoading = false;
  List<Map<String, dynamic>> _pnl = [];
  String _pnlFormation = '';
  // 구매가 심층 탐색 (2026-08-19 확정: +100건 더 찾기 / 끝까지 찾기)
  bool _deepSearching = false;
  bool _deepCancel = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Color get _accent => Theme.of(context).colorScheme.primary;
  Color get _subColor => Colors.grey.shade500;

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    var accounts = <Map<String, String>>[];
    try {
      final raw = prefs.getString(_accountsPref);
      if (raw != null) {
        accounts = (json.decode(raw) as List)
            .map((e) => {'name': '${e['name'] ?? ''}', 'key': '${e['key'] ?? ''}'})
            .where((a) => a['key']!.isNotEmpty)
            .toList();
      }
    } catch (_) {
      accounts = [];
    }
    // 구버전(단일 키) 마이그레이션 — 감독명이 없으면 손익 화면에서 입력받는다
    if (accounts.isEmpty) {
      final oldKey = prefs.getString(_keyPref);
      if (oldKey != null && oldKey.isNotEmpty) {
        accounts = [{'name': prefs.getString(_namePref) ?? '', 'key': oldKey}];
        await prefs.setString(_accountsPref, json.encode(accounts));
        await prefs.remove(_keyPref);
        await prefs.remove(_namePref);
      }
    }
    var idx = prefs.getInt(_accountIdxPref) ?? 0;
    if (idx < 0 || idx >= accounts.length) idx = 0;
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _accountIdx = idx;
      _apiKey = accounts.isEmpty ? null : accounts[idx]['key'];
      _nickname = accounts.isEmpty ? null : (accounts[idx]['name']!.isEmpty ? null : accounts[idx]['name']);
    });
    if (_apiKey != null && (_trades['buy']!.isEmpty)) {
      _loadTrades(reset: true);
    }
  }

  Future<void> _persistAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountsPref, json.encode(_accounts));
    await prefs.setInt(_accountIdxPref, _accountIdx);
  }

  /// 조회 상태 초기화 (계정 전환·삭제 시)
  void _resetData() {
    _trades['buy'] = [];
    _trades['sell'] = [];
    _offsets['buy'] = 0;
    _offsets['sell'] = 0;
    _exhausted['buy'] = false;
    _exhausted['sell'] = false;
    _pnl = [];
    _pnlFormation = '';
    _error = null;
  }

  /// 계정 전환 — 해당 계정의 키·감독명으로 바꾸고 거래내역을 다시 불러온다
  Future<void> _selectAccount(int i) async {
    if (i < 0 || i >= _accounts.length || i == _accountIdx) return;
    setState(() {
      _accountIdx = i;
      _apiKey = _accounts[i]['key'];
      _nickname = _accounts[i]['name']!.isEmpty ? null : _accounts[i]['name'];
      _resetData();
    });
    await _persistAccounts();
    _loadTrades(reset: true);
  }

  Future<void> _saveSettings() async {
    final key = _keyController.text.trim();
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '본인 감독명을 입력해주세요.');
      return;
    }
    if (key.isEmpty) {
      setState(() => _error = 'API 키를 입력해주세요.');
      return;
    }
    if (_accounts.any((a) => a['key'] == key)) {
      setState(() => _error = '이미 등록된 API 키입니다.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // 키 검증: 거래 API 1건 조회가 성공해야 저장
      // (거래 API는 키 소유자 데이터만 반환 — ouid·감독명 불필요, 2026-09 실측)
      final response = await http.get(
        Uri.parse('$_apiBase/fconline/v1/user/trade'
            '?tradetype=buy&offset=0&limit=1'),
        headers: {'x-nxopen-api-key': key},
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 429) {
        setState(() =>
            _error = '오늘 API 호출 한도를 모두 사용했습니다. 자정(00:00) 이후 다시 시도해주세요.');
        return;
      }
      if (response.statusCode != 200) {
        setState(() =>
            _error = 'API 키가 올바르지 않습니다. (응답 ${response.statusCode})');
        return;
      }
      // 감독명 존재 검증 (/id) — 손익 조회에 쓰인다
      final idResp = await http.get(
        Uri.parse('$_apiBase/fconline/v1/id?nickname=${Uri.encodeComponent(name)}'),
        headers: {'x-nxopen-api-key': key},
      ).timeout(const Duration(seconds: 15));
      final idData = json.decode(idResp.body);
      if (idResp.statusCode != 200 || idData['ouid'] == null) {
        setState(() => _error = idResp.statusCode == 400
            ? '감독명을 찾을 수 없습니다. 본인 감독명을 확인해주세요.'
            : '감독명 확인에 실패했습니다. (응답 ${idResp.statusCode})');
        return;
      }
      setState(() {
        _accounts.add({'name': name, 'key': key});
        _accountIdx = _accounts.length - 1;
        _apiKey = key;
        _nickname = name;
        _addingAccount = false;
        _keyController.clear();
        _nameController.clear();
        _resetData();
      });
      await _persistAccounts();
      _loadTrades(reset: true);
    } catch (e) {
      setState(() => _error = '네트워크 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 현재 계정 삭제 — 실수 방지용 확인창을 거친 뒤에만 지운다 (2026-09-05 사용자 지적: 누르자마자 등록 키가 사라짐)
  Future<void> _confirmClearSettings() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('계정 삭제'),
        content: Text('${_nickname ?? '현재'} 계정의 API 키와 불러온 거래 내역이 이 기기에서 지워집니다.\n계속할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok == true) await _clearSettings();
  }

  Future<void> _clearSettings() async {
    setState(() {
      if (_accountIdx >= 0 && _accountIdx < _accounts.length) _accounts.removeAt(_accountIdx);
      _accountIdx = 0;
      _apiKey = _accounts.isEmpty ? null : _accounts[0]['key'];
      _nickname = _accounts.isEmpty ? null : (_accounts[0]['name']!.isEmpty ? null : _accounts[0]['name']);
      _resetData();
    });
    await _persistAccounts();
    if (_apiKey != null) _loadTrades(reset: true);
  }

  /// 스쿼드 손익용 감독명 저장 — 존재 검증(/id) 후 저장하고 바로 손익 조회
  Future<void> _saveNickname() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '본인 감독명을 입력해주세요.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await http.get(
        Uri.parse('$_apiBase/fconline/v1/id'
            '?nickname=${Uri.encodeComponent(name)}'),
        headers: {'x-nxopen-api-key': _apiKey ?? ''},
      ).timeout(const Duration(seconds: 15));
      final data = json.decode(response.body);
      if (response.statusCode != 200 || data['ouid'] == null) {
        setState(() => _error = response.statusCode == 400
            ? '감독명을 찾을 수 없습니다. 본인 감독명을 확인해주세요.'
            : '감독명 확인에 실패했습니다. (응답 ${response.statusCode})');
        return;
      }
      setState(() {
        _nickname = name;
        if (_accountIdx < _accounts.length) _accounts[_accountIdx]['name'] = name;
      });
      await _persistAccounts();
      _loadPnl();
    } catch (e) {
      setState(() => _error = '네트워크 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 감독명 변경 — 입력 화면으로 (API 키·계정은 유지, 저장은 조회 성공 시)
  Future<void> _clearNickname() async {
    setState(() {
      _nameController.text = _nickname ?? '';
      _nickname = null;
      _pnl = [];
    });
  }

  Future<void> _ensureMeta() async {
    if (_spidNames != null || _metaLoading) return;
    _metaLoading = true;
    try {
      final responses = await Future.wait([
        http
            .get(Uri.parse('$_apiBase/static/fconline/meta/spid.json'))
            .timeout(const Duration(seconds: 30)),
        http
            .get(Uri.parse('$_apiBase/static/fconline/meta/seasonid.json'))
            .timeout(const Duration(seconds: 30)),
      ]);
      if (responses[0].statusCode == 200) {
        final list = json.decode(utf8.decode(responses[0].bodyBytes)) as List;
        _spidNames = {
          for (final e in list) (e['id'] as num).toInt(): e['name'] as String
        };
      }
      if (responses[1].statusCode == 200) {
        final list = json.decode(utf8.decode(responses[1].bodyBytes)) as List;
        _seasonNames = {
          for (final e in list)
            (e['seasonId'] as num).toInt(): (e['className'] as String)
                .split(' (')
                .first
        };
      }
    } catch (e) {
      print('[MarketTab] 메타 로드 실패: $e');
    } finally {
      _metaLoading = false;
    }
  }

  String _playerLabel(int spid) {
    final name = _spidNames?[spid] ?? '$spid';
    final season = _seasonNames?[spid ~/ 1000000] ?? '';
    return season.isNotEmpty ? '[$season] $name' : name;
  }

  // ── BP 1억:1 축소(2026-08-20 넥슨 점검) 대응 ──
  // 넥슨은 이적시장 히스토리를 옛 단위 그대로 두므로 점검 전 거래는 옛 단위로 내려온다.
  // 점검 시작 2026-08-20 02:30 KST = 2026-08-19 17:30 UTC (tradeDate는 UTC).
  // 서버(utils/bp_unit.py)와 같은 규칙: 1억으로 나눠 올림, 최소 1.
  static const String _bpUnitCutoverUtc = '2026-08-19T17:30:00';
  static const int _bpUnitDivisor = 100000000;

  static bool _isOldBpUnit(String? tradeDate) {
    if (tradeDate == null || tradeDate.isEmpty) return false;
    final td = tradeDate.length > 19 ? tradeDate.substring(0, 19) : tradeDate;
    return td.compareTo(_bpUnitCutoverUtc) < 0;
  }

  /// 넥슨 거래 행의 value를 새 단위로 정규화 (옛 단위 거래만 변환, 원본 Map을 수정)
  static List<Map<String, dynamic>> _normalizeTradeRows(List<Map<String, dynamic>> rows) {
    for (final t in rows) {
      if (!_isOldBpUnit(t['tradeDate']?.toString())) continue;
      final v = (t['value'] as num?)?.toInt() ?? 0;
      if (v <= 0) continue;
      final converted = (v + _bpUnitDivisor - 1) ~/ _bpUnitDivisor;
      t['value'] = converted < 1 ? 1 : converted;
    }
    return rows;
  }

  static String formatBp(num? v) {
    if (v == null) return '-';
    final n = v.toInt();
    if (n >= 1000000000000) {
      final jo = n ~/ 1000000000000;
      final eok = (n % 1000000000000) ~/ 100000000;
      return eok > 0 ? '$jo조 ${eok}억' : '$jo조';
    }
    if (n >= 100000000) {
      final eok = n ~/ 100000000;
      final man = (n % 100000000) ~/ 10000;
      return man > 0 ? '$eok억 ${man}만' : '$eok억';
    }
    if (n >= 10000) return '${n ~/ 10000}만';
    return '$n';
  }

  Future<void> _loadTrades({bool reset = false}) async {
    if (_apiKey == null || _tradesLoading) return;
    setState(() {
      _tradesLoading = true;
      _error = null;
    });
    try {
      await _ensureMeta();
      // 거래 API는 키 소유자 데이터만 반환 — ouid 불필요 (2026-09 실측)
      final type = _tradeType;
      final offset = reset ? 0 : _offsets[type]!;
      final response = await http.get(
        Uri.parse('$_apiBase/fconline/v1/user/trade'
            '?tradetype=$type&offset=$offset&limit=100'),
        headers: {'x-nxopen-api-key': _apiKey!},
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode == 429) {
        setState(() =>
            _error = '오늘 API 호출 한도를 모두 사용했습니다. 자정(00:00) 이후 다시 시도해주세요.');
        return;
      }
      final data = json.decode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 || data is! List) {
        setState(() => _error = '거래내역 조회에 실패했습니다. (응답 ${response.statusCode})');
        return;
      }
      final rows = _normalizeTradeRows(data
          .map((e) => Map<String, dynamic>.from(e))
          .toList());
      setState(() {
        if (reset) {
          _trades[type] = rows;
          _offsets[type] = rows.length;
        } else {
          _trades[type]!.addAll(rows);
          _offsets[type] = _offsets[type]! + rows.length;
        }
        _exhausted[type] = rows.length < 100;
      });
    } catch (e) {
      setState(() => _error = '네트워크 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _tradesLoading = false);
    }
  }

  // ── 스쿼드 손익: 서버 user-squad(라인업) + 로컬 구매가 + 서버 시세 ──
  Future<void> _loadPnl() async {
    final name = _nickname ?? '';
    if (name.isEmpty || _pnlLoading) return;
    setState(() {
      _pnlLoading = true;
      _error = null;
      _pnl = [];
    });
    try {
      await _ensureMeta();
      // 구매 기록을 충분히 확보 (최대 500건 — 구매가 매칭용)
      while (_trades['buy']!.length < 500 && !(_exhausted['buy'] ?? false)) {
        final before = _trades['buy']!.length;
        _tradeType = 'buy';
        await _loadTrades();
        if (_trades['buy']!.length == before) break;
      }
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/user/squad/user-squad'
            '?name=${Uri.encodeComponent(name)}&mode=manager'),
      ).timeout(const Duration(seconds: 30));
      final data = json.decode(response.body);
      if (data['success'] != true) {
        setState(() =>
            _error = data['message'] ?? '최근 경기 스쿼드를 찾지 못했습니다.');
        return;
      }
      final players = (data['players'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _pnlFormation = data['formation5'] ?? '';

      // 시세: 서버 조회 (동시 4건 제한)
      final results = <Map<String, dynamic>>[];
      for (var i = 0; i < players.length; i += 4) {
        final chunk = players.skip(i).take(4).toList();
        final prices = await Future.wait(chunk.map((p) async {
          try {
            final r = await http.get(
              Uri.parse('${ApiService.baseUrl}/api/user/lookup/player-price'
                  '?spid=${p['spid']}&grade=${p['grade']}'),
            ).timeout(const Duration(seconds: 25));
            final d = json.decode(r.body);
            return d['success'] == true ? d['value'] as num? : null;
          } catch (e) {
            return null;
          }
        }));
        for (var j = 0; j < chunk.length; j++) {
          final p = chunk[j];
          final spid = (p['spid'] as num).toInt();
          final grade = (p['grade'] as num).toInt();
          final buy = _lastBuy(spid, grade);
          final price = prices[j];
          results.add({
            ...p,
            'buy': buy,
            'price': price,
            'diff': (buy != null && price != null) ? price - buy : null,
          });
        }
        if (mounted) setState(() => _pnl = List.from(results));
      }
    } catch (e) {
      setState(() => _error = '스쿼드 손익 계산 중 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _pnlLoading = false);
    }
  }

  /// 구매가: 같은 spid+grade의 가장 최근 구매 (웹 squad-pnl과 동일 — grade까지 정확 일치.
  /// 강화 단계가 달라진 선수의 '-'는 정상 동작 — 사용자 확정, 손대지 말 것)
  num? _lastBuy(int spid, int grade) {
    for (final t in _trades['buy']!) {
      if ((t['spid'] as num?)?.toInt() == spid &&
          (t['grade'] as num?)?.toInt() == grade) {
        return t['value'] as num?;
      }
    }
    return null;
  }

  /// 확보된 구매 내역으로 손익 행들의 구매가만 재매칭 (시세는 유지)
  void _rematchPnl() {
    if (_pnl.isEmpty) return;
    setState(() {
      _pnl = _pnl.map((p) {
        final buy = _lastBuy(
            (p['spid'] as num).toInt(), (p['grade'] as num).toInt());
        final price = p['price'] as num?;
        return {
          ...p,
          'buy': buy,
          'diff': (buy != null && price != null) ? price - buy : null,
        };
      }).toList();
    });
  }

  /// 구매가 미확인 선수 수 (더 오래된 구매 내역에서 찾을 대상)
  int get _missingBuyCount => _pnl.where((p) => p['buy'] == null).length;

  /// 구매 내역 1페이지(100건) 추가 확보 — 심층 탐색 전용 (거래내역 세그 상태를 건드리지 않음)
  Future<bool> _fetchBuyPage() async {
    final offset = _offsets['buy']!;
    final response = await http.get(
      Uri.parse('$_apiBase/fconline/v1/user/trade'
          '?tradetype=buy&offset=$offset&limit=100'),
      headers: {'x-nxopen-api-key': _apiKey!},
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode == 429) {
      if (mounted) {
        setState(() =>
            _error = '오늘 API 호출 한도를 모두 사용했습니다. 자정(00:00) 이후 다시 시도해주세요.');
      }
      return false;
    }
    final data = json.decode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200 || data is! List) return false;
    final rows = _normalizeTradeRows(
        data.map((e) => Map<String, dynamic>.from(e)).toList());
    if (mounted) {
      setState(() {
        _trades['buy']!.addAll(rows);
        _offsets['buy'] = _offsets['buy']! + rows.length;
        _exhausted['buy'] = rows.length < 100;
      });
    }
    return rows.isNotEmpty;
  }

  /// 구매가 심층 탐색 — toEnd=false면 100건 1회, true면 소진/중단까지 반복
  Future<void> _findMoreBuy({required bool toEnd}) async {
    if (_deepSearching || _apiKey == null) return;
    setState(() {
      _deepSearching = true;
      _deepCancel = false;
    });
    try {
      while (!(_exhausted['buy'] ?? false) && !_deepCancel && mounted) {
        final got = await _fetchBuyPage();
        _rematchPnl();
        if (!got) break;
        if (!toEnd) break; // +100건 더 찾기: 1페이지만
        if (_missingBuyCount == 0) break; // 전부 찾으면 조기 종료
      }
    } catch (e) {
      print('[MarketTab] 구매가 탐색 오류: $e');
    } finally {
      if (mounted) setState(() => _deepSearching = false);
    }
  }

  /// 끝까지 찾기 — 시작 전 안내 (시간 소요 + 화면 유지, 사용자 확정 문구)
  void _confirmFindToEnd() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('끝까지 찾기'),
        content: const Text(
            '구매 내역을 처음부터 끝까지 확인합니다.\n'
            '기록이 많으면 수십 초~2분가량 걸릴 수 있으며,\n'
            '찾는 동안 앱 화면을 켜둔 채로 기다려주세요.\n'
            '(진행 중 중단할 수 있습니다)'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _findMoreBuy(toEnd: true);
            },
            child: const Text('시작'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_apiKey == null || _addingAccount) return _buildSetup();
    return _buildMain();
  }

  // ── 키 미등록: 발급 안내 + 등록 ──
  Widget _buildSetup() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_addingAccount ? '계정 추가' : '이적시장',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (_accounts.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() {
                    _addingAccount = false;
                    _error = null;
                  }),
                  child: const Text('취소'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(_addingAccount
                  ? '다른 계정의 감독명과 API 키를 등록하면 상단 메뉴에서 계정을 전환할 수 있습니다.'
                  : '본인의 이적시장 구매/판매 내역과 스쿼드 손익을 조회합니다.',
              style: TextStyle(fontSize: 13, color: _subColor)),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('넥슨 오픈 API 키 발급 방법',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _accent)),
                  const SizedBox(height: 10),
                  _stepRow('1', '아래 버튼으로 넥슨 오픈 API 사이트에 접속해 넥슨 계정으로 로그인합니다.'),
                  _stepRow('2', '[내 API 키 발급] 메뉴에서 FC온라인 API 키를 발급받습니다.'),
                  _stepRow('3', '발급된 키(test_... 또는 live_...)를 복사해 아래에 붙여넣습니다.'),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => launchUrl(Uri.parse(_issueUrl),
                          mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('API 키 발급받기 (openapi.nexon.com)'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '본인 감독명',
              hintText: '이 API 키 계정의 게임 내 감독명',
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _keyController,
            decoration: const InputDecoration(
              labelText: 'API 키',
              hintText: 'test_... 또는 live_... 로 시작하는 API 키',
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          if (_error != null)
            Text(_error!,
                style: const TextStyle(color: Colors.red, fontSize: 13)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: _saving ? null : _saveSettings,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('등록하기',
                      style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 10),
          Text('API 키는 이 기기에만 저장되며 서버로 전송되지 않습니다.',
              style: TextStyle(fontSize: 11.5, color: _subColor)),
        ],
      ),
    );
  }

  Widget _stepRow(String num, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Text(num,
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w800, color: _accent)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  // ── 키 등록됨: 거래내역 / 스쿼드 손익 ──
  Widget _buildMain() {
    return RefreshIndicator(
      // 당겨서 새로고침: 현재 세그먼트만 재조회 (로딩 정책 2026-08-19)
      onRefresh: () async {
        if (_seg == 0) {
          await _loadTrades(reset: true);
        } else {
          await _loadPnl();
        }
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('이적시장',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const Spacer(),
              // 계정 메뉴 (2026-09-05): 등록된 계정 전환 · 계정 추가 · 현재 계정 삭제
              PopupMenuButton<String>(
                tooltip: '계정 전환',
                onSelected: (v) {
                  if (v == '__add') {
                    setState(() {
                      _addingAccount = true;
                      _error = null;
                      _keyController.clear();
                      _nameController.clear();
                    });
                  } else if (v == '__del') {
                    _confirmClearSettings();
                  } else {
                    _selectAccount(int.tryParse(v) ?? _accountIdx);
                  }
                },
                itemBuilder: (_) => [
                  for (var i = 0; i < _accounts.length; i++)
                    PopupMenuItem<String>(
                      value: '$i',
                      child: Row(children: [
                        Icon(i == _accountIdx ? Icons.check : Icons.person_outline, size: 16),
                        const SizedBox(width: 8),
                        Text(_accounts[i]['name']!.isEmpty ? '감독명 미입력' : _accounts[i]['name']!),
                      ]),
                    ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    value: '__add',
                    child: Row(children: [Icon(Icons.add, size: 16), SizedBox(width: 8), Text('계정 추가')]),
                  ),
                  const PopupMenuItem<String>(
                    value: '__del',
                    child: Row(children: [Icon(Icons.delete_outline, size: 16), SizedBox(width: 8), Text('현재 계정 삭제')]),
                  ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.key, size: 14, color: _accent),
                    const SizedBox(width: 4),
                    Text(_nickname ?? 'API 키 등록됨',
                        style: TextStyle(fontSize: 12, color: _subColor)),
                    Icon(Icons.arrow_drop_down, size: 18, color: _subColor),
                  ],
                ),
              ),
            ],
          ),
          PillTabs(
            labels: const ['거래내역', '스쿼드 손익'],
            selectedIndex: _seg,
            onSelected: (i) {
              setState(() => _seg = i);
              if (i == 1 && _pnl.isEmpty) _loadPnl();
            },
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
          if (_seg == 0) ..._buildTrades() else ..._buildPnl(),
        ],
        ),
      ),
    );
  }

  List<Widget> _buildTrades() {
    final rows = _trades[_tradeType]!;
    final filter = _filterController.text.trim();
    final visible = filter.isEmpty
        ? rows
        : rows
            .where((t) => _playerLabel((t['spid'] as num?)?.toInt() ?? 0)
                .contains(filter))
            .toList();
    return [
      Row(
        children: [
          SizedBox(
            width: 132,
            child: PillTabs(
              labels: const ['구매', '판매'],
              selectedIndex: _tradeType == 'buy' ? 0 : 1,
              onSelected: (i) {
                final type = i == 0 ? 'buy' : 'sell';
                setState(() => _tradeType = type);
                if (_trades[type]!.isEmpty) _loadTrades(reset: true);
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _filterController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: '선수명 검색',
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (_tradesLoading && rows.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Center(child: CircularProgressIndicator()),
        ),
      for (final t in visible) _tradeRow(t),
      if (rows.isNotEmpty && !(_exhausted[_tradeType] ?? false))
        Center(
          child: TextButton(
            onPressed: _tradesLoading ? null : () => _loadTrades(),
            child: Text(_tradesLoading ? '불러오는 중...' : '+100건 더 보기'),
          ),
        ),
      if (rows.isNotEmpty && (_exhausted[_tradeType] ?? false))
        Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text('전체 ${rows.length}건',
                style: TextStyle(fontSize: 12, color: _subColor)),
          ),
        ),
    ];
  }

  Widget _tradeRow(Map<String, dynamic> t) {
    final spid = (t['spid'] as num?)?.toInt() ?? 0;
    final grade = (t['grade'] as num?)?.toInt() ?? 1;
    final date = (t['tradeDate'] ?? '').toString().replaceFirst('T', ' ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          GradeBadge(grade: grade, fontSize: 11),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SeasonBadge(spid: spid, height: 13),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(_spidNames?[spid] ?? '$spid',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                Text(date.length > 16 ? date.substring(0, 16) : date,
                    style: TextStyle(fontSize: 10.5, color: _subColor)),
              ],
            ),
          ),
          Text(formatBp(t['value'] as num?),
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: _tradeType == 'buy' ? Colors.orange : _accent)),
        ],
      ),
    );
  }

  List<Widget> _buildPnl() {
    // 감독명 미설정 → 입력 화면 (감독명은 스쿼드 손익에만 필요 — 거래내역은 키만으로 조회)
    if ((_nickname ?? '').isEmpty) {
      return [
        Text('스쿼드 손익은 게임 내 감독명으로 최근 경기 스쿼드를 조회합니다.',
            style: TextStyle(fontSize: 12, color: _subColor)),
        const SizedBox(height: 10),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: '본인 감독명',
            hintText: '게임 내 감독명',
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            onPressed: _saving ? null : _saveNickname,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('조회',
                    style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ];
    }
    num totalBuy = 0, totalPrice = 0;
    var counted = 0;
    for (final p in _pnl) {
      if (p['buy'] != null && p['price'] != null) {
        totalBuy += p['buy'] as num;
        totalPrice += p['price'] as num;
        counted++;
      }
    }
    final totalDiff = totalPrice - totalBuy;
    return [
      Row(
        children: [
          Expanded(
            child: Text(
                '${_nickname ?? ''}의 최근 경기 스쿼드 기준'
                '${_pnlFormation.isNotEmpty ? ' · $_pnlFormation' : ''}',
                style: TextStyle(fontSize: 12, color: _subColor)),
          ),
          TextButton(
            onPressed: _pnlLoading ? null : _clearNickname,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('변경', style: TextStyle(fontSize: 12)),
          ),
          TextButton(
            onPressed: _pnlLoading ? null : _loadPnl,
            child: Text(_pnlLoading ? '계산 중...' : '새로고침'),
          ),
        ],
      ),
      if (_pnlLoading && _pnl.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (counted > 0)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('평가 손익 ($counted명 기준)',
                          style: TextStyle(fontSize: 11, color: _subColor)),
                      Text(
                          '${totalDiff >= 0 ? '+' : '-'}${formatBp(totalDiff.abs())} BP',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: totalDiff >= 0 ? _accent : Colors.red)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('구매 합계 ${formatBp(totalBuy)}',
                        style: TextStyle(fontSize: 11, color: _subColor)),
                    Text('시세 합계 ${formatBp(totalPrice)}',
                        style: TextStyle(fontSize: 11, color: _subColor)),
                  ],
                ),
              ],
            ),
          ),
        ),
      for (final p in _pnl) _pnlRow(p),
      // 구매가 심층 탐색 (2026-08-19): 못 찾은 선수가 있으면 더 오래된 내역에서 탐색
      if (_pnl.isNotEmpty && _missingBuyCount > 0) ...[
        if (!(_exhausted['buy'] ?? false)) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                '구매가를 찾지 못한 선수 $_missingBuyCount명 — '
                '더 오래된 구매 내역(현재 ${_trades['buy']!.length}건 확인)에서 찾아볼 수 있습니다.',
                style: TextStyle(fontSize: 11.5, color: _subColor)),
          ),
          const SizedBox(height: 6),
          if (_deepSearching)
            Row(
              children: [
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      '구매 내역 ${_trades['buy']!.length}건째 확인 중...'
                      ' (남은 미확인 $_missingBuyCount명)',
                      style: TextStyle(fontSize: 12, color: _subColor)),
                ),
                TextButton(
                  onPressed: () => setState(() => _deepCancel = true),
                  child: const Text('중단', style: TextStyle(fontSize: 12)),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _findMoreBuy(toEnd: false),
                    child: const Text('+100건 더 찾기',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _confirmFindToEnd,
                    child:
                        const Text('끝까지 찾기', style: TextStyle(fontSize: 12.5)),
                  ),
                ),
              ],
            ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                '구매 내역 전체(${_trades['buy']!.length}건)를 확인했습니다. '
                '남은 "-"는 구매 당시와 강화 단계가 다르거나 이적시장 구매 기록이 없는 선수입니다.',
                style: TextStyle(fontSize: 11, color: _subColor)),
          ),
      ],
      if (_pnl.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
              '구매가는 이 기기에서 조회한 구매 내역 기준입니다. '
              '구매 후 강화로 단계가 달라진 선수는 "-"로 표시됩니다.',
              style: TextStyle(fontSize: 11, color: _subColor)),
        ),
    ];
  }

  Widget _pnlRow(Map<String, dynamic> p) {
    final diff = p['diff'] as num?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          GradeBadge(grade: (p['grade'] as num?)?.toInt() ?? 1, fontSize: 11),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SeasonBadge(spid: p['spid'] as num?, height: 13),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text('${p['name']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                Text(
                    '구매 ${formatBp(p['buy'] as num?)} · 시세 ${formatBp(p['price'] as num?)}',
                    style: TextStyle(fontSize: 10.5, color: _subColor)),
              ],
            ),
          ),
          Text(
              diff == null
                  ? '-'
                  : '${diff >= 0 ? '+' : '-'}${formatBp(diff.abs())}',
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: diff == null
                      ? _subColor
                      : (diff >= 0 ? _accent : Colors.red))),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _keyController.dispose();
    _nameController.dispose();
    _filterController.dispose();
    super.dispose();
  }
}
