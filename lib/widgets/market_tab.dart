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
  static const _keyPref = 'nexon_api_key';
  static const _namePref = 'nexon_api_nickname';
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
  String? _ouid;
  bool _saving = false;
  String? _error;

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
    if (!mounted) return;
    setState(() {
      _apiKey = prefs.getString(_keyPref);
      _nickname = prefs.getString(_namePref);
    });
    if (_apiKey != null && (_trades['buy']!.isEmpty)) {
      _loadTrades(reset: true);
    }
  }

  Future<void> _saveSettings() async {
    final key = _keyController.text.trim();
    final name = _nameController.text.trim();
    if (key.isEmpty || name.isEmpty) {
      setState(() => _error = 'API 키와 본인 감독명을 모두 입력해주세요.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // 키·감독명 검증: ouid 조회가 성공해야 저장
      final response = await http.get(
        Uri.parse('$_apiBase/fconline/v1/id'
            '?nickname=${Uri.encodeComponent(name)}'),
        headers: {'x-nxopen-api-key': key},
      ).timeout(const Duration(seconds: 15));
      final data = json.decode(response.body);
      if (response.statusCode != 200 || data['ouid'] == null) {
        setState(() => _error = response.statusCode == 400
            ? '감독명을 찾을 수 없습니다. 본인 감독명을 확인해주세요.'
            : 'API 키가 올바르지 않습니다. (응답 ${response.statusCode})');
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyPref, key);
      await prefs.setString(_namePref, name);
      setState(() {
        _apiKey = key;
        _nickname = name;
        _ouid = data['ouid'];
      });
      _loadTrades(reset: true);
    } catch (e) {
      setState(() => _error = '네트워크 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPref);
    await prefs.remove(_namePref);
    setState(() {
      _apiKey = null;
      _nickname = null;
      _ouid = null;
      _trades['buy'] = [];
      _trades['sell'] = [];
      _offsets['buy'] = 0;
      _offsets['sell'] = 0;
      _pnl = [];
    });
  }

  Future<String?> _resolveOuid() async {
    if (_ouid != null) return _ouid;
    try {
      final response = await http.get(
        Uri.parse('$_apiBase/fconline/v1/id'
            '?nickname=${Uri.encodeComponent(_nickname ?? '')}'),
        headers: {'x-nxopen-api-key': _apiKey ?? ''},
      ).timeout(const Duration(seconds: 15));
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['ouid'] != null) {
        _ouid = data['ouid'];
      }
    } catch (e) {
      print('[MarketTab] ouid 조회 실패: $e');
    }
    return _ouid;
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
      final ouid = await _resolveOuid();
      if (ouid == null) {
        setState(() => _error = '계정 확인에 실패했습니다. 키/감독명을 다시 등록해주세요.');
        return;
      }
      final type = _tradeType;
      final offset = reset ? 0 : _offsets[type]!;
      final response = await http.get(
        Uri.parse('$_apiBase/fconline/v1/user/trade'
            '?ouid=$ouid&tradetype=$type&offset=$offset&limit=100'),
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
      final rows = data
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
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

      // 구매가: 같은 spid+grade의 가장 최근 구매 (웹 squad-pnl과 동일 — grade까지 매칭)
      num? lastBuy(int spid, int grade) {
        for (final t in _trades['buy']!) {
          if ((t['spid'] as num?)?.toInt() == spid &&
              (t['grade'] as num?)?.toInt() == grade) {
            return t['value'] as num?;
          }
        }
        return null;
      }

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
          final buy = lastBuy(spid, grade);
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_apiKey == null) return _buildSetup();
    return _buildMain();
  }

  // ── 키 미등록: 발급 안내 + 등록 ──
  Widget _buildSetup() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('이적시장',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('본인의 이적시장 구매/판매 내역과 스쿼드 손익을 조회합니다.',
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
            controller: _keyController,
            decoration: const InputDecoration(
              labelText: 'API 키',
              hintText: 'test_... 또는 live_... 로 시작하는 API 키',
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '본인 감독명',
              hintText: '게임 내 감독명 (스쿼드 손익 조회에 사용)',
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('이적시장',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const Spacer(),
              Icon(Icons.key, size: 14, color: _accent),
              const SizedBox(width: 4),
              Text(_nickname ?? '',
                  style: TextStyle(fontSize: 12, color: _subColor)),
              TextButton(
                onPressed: _clearSettings,
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                child: const Text('변경', style: TextStyle(fontSize: 12)),
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
      if (_pnl.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
              '구매가는 이 기기에서 조회한 구매 내역(최근 500건) 기준이라\n'
              '오래된 구매는 "-"로 표시될 수 있습니다.',
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
