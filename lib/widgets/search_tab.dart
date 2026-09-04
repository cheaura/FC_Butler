import 'dart:convert';
import '../providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../screens/training_calc_screen.dart';
import '../constants/positions.dart';
import '../services/api_service.dart';
import '../services/recent_search_store.dart';
import '../screens/match_detail_screen.dart';
import 'pill_tabs.dart';
import 'player_field_card.dart';

/// 검색 탭으로 전달되는 검색 요청 (홈 타일·최근 감독에서 사용)
class SearchRequest {
  final String name;
  final String mode;
  const SearchRequest(this.name, this.mode);
}

/// 검색 탭 (하단 탭 — 홈과 랭킹 사이, 사용자 확정 구조).
/// 결과는 [개요 | 전적 | 경기] 탭 구분(A안): 개요=현재 랭킹+역대 최고 등급,
/// 전적=승무패·포메이션 승률·상성·필터, 경기=목록(최초 100)+수집.
class SearchTab extends StatefulWidget {
  /// 홈 등 다른 탭에서 검색을 요청할 때 사용 (셸이 소유)
  final ValueNotifier<SearchRequest?>? requestNotifier;
  const SearchTab({Key? key, this.requestNotifier}) : super(key: key);

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab>
    with AutomaticKeepAliveClientMixin {
  final _nameController = TextEditingController();
  final _kwController = TextEditingController();
  String _mode = 'manager';
  bool _loading = false;
  bool _matchesLoading = false;
  bool _backfilling = false;
  String? _error;
  Map<String, dynamic>? _result; // lookup/manager 응답
  Map<String, dynamic>? _matches; // lookup/matches 응답 (항상 미필터 전체 — 경기 세그용)
  // 필터된 전적 응답 (전적 세그 전용 — 2026-08-19 필터 UX 개편: 경기 세그는 항상 전체 유지)
  Map<String, dynamic>? _filteredMatches;
  bool _filteredLoading = false;
  int _visibleFiltered = 100; // 필터된 경기 목록 표시 수, 더 보기 +100씩
  List<Map<String, dynamic>> _recent = [];
  List<String> _clubs = [];
  String _club = '';
  int _visibleMatches = 100; // 최초 100경기 표시, 더 보기 +100씩
  bool _autoBackfilled = false;
  int _resultSeg = 0; // 0=개요, 1=스쿼드, 2=전적, 3=경기, 4=채굴
  // 채굴량 조회 (승리당 FC — 챔피언스/슈퍼 챔피언스만 지급)
  // 기간별 캐시: 오늘/7일 토글 재호출 방지, 실패 시 이전 데이터 유지 (로딩 정책 2026-08-19)
  bool _miningLoading = false;
  final Map<int, Map<String, dynamic>> _miningCache = {};
  int _miningPeriod = 0; // 0=오늘, 1=7일 (30일·전체는 과다 수집 방지로 제외 — 사용자 지정)

  Map<String, dynamic>? get _mining => _miningCache[_miningPeriod];

  // 필터(클럽/키워드) 활성 여부 — 활성 시 전적 세그에 필터된 경기 목록 표시
  bool get _filterActive =>
      _club.isNotEmpty || _kwController.text.trim().isNotEmpty;
  // 감독 스쿼드 조회 (최근 경기 라인업 — 서버 user-squad)
  bool _squadLoading = false;
  Map<String, dynamic>? _squad;

  static const _modeLabels = {
    'manager': '감독모드',
    '1vs1': '1vs1',
    '2vs2': '2vs2',
  };

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    RecentSearchStore.load().then((list) {
      if (mounted) setState(() => _recent = list);
    });
    _loadClubs();
    widget.requestNotifier?.addListener(_onExternalRequest);
    // 검색어를 지우면 결과를 닫고 최근 검색 목록으로 복귀 (사용자 지정)
    _nameController.addListener(() {
      if (_nameController.text.isEmpty &&
          (_result != null || _error != null)) {
        setState(() {
          _result = null;
          _matches = null;
          _filteredMatches = null;
          _miningCache.clear();
          _squad = null;
          _error = null;
        });
      } else {
        setState(() {}); // 지우기(X) 버튼 표시 갱신
      }
    });
  }

  // 홈 타일/최근 감독에서 넘어온 검색 요청 처리
  void _onExternalRequest() {
    final req = widget.requestNotifier?.value;
    if (req == null) return;
    widget.requestNotifier?.value = null;
    _nameController.text = req.name;
    setState(() => _mode = req.mode);
    if (req.name.isNotEmpty) _search();
  }

  Future<void> _loadClubs() async {
    try {
      final response = await http
          .get(Uri.parse('${ApiService.baseUrl}/api/user/lookup/clubs'))
          .timeout(const Duration(seconds: 15));
      final data = json.decode(response.body);
      if (data['success'] == true && mounted) {
        setState(() => _clubs = (data['clubs'] as List)
            .map((c) => c['name'] as String)
            .toList());
      }
    } catch (e) {
      print('[SearchTab] 클럽 목록 로드 실패: $e');
    }
  }

  Future<void> _search() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _matches = null;
      _filteredMatches = null;
      _visibleMatches = 100;
      _visibleFiltered = 100;
      _autoBackfilled = false;
      _resultSeg = 0;
      _miningCache.clear();
      _squad = null;
    });
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/user/lookup/manager'
            '?name=${Uri.encodeComponent(name)}&mode=$_mode'),
      ).timeout(const Duration(seconds: 25));
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() => _result = data);
        if (data['found'] == true) {
          final list = await RecentSearchStore.add(
              name, _mode, Map<String, dynamic>.from(data['data'] ?? {}));
          if (mounted) setState(() => _recent = list);
        }
        // 전적은 감독모드/1vs1만 지원 (2vs2는 오픈API 미제공 — 웹과 동일)
        if (data['found'] == true && _mode != '2vs2') {
          _loadMatches();
        }
      } else {
        setState(() => _error = data['message'] ?? '조회에 실패했습니다.');
      }
    } catch (e) {
      setState(() => _error = '네트워크 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMatches() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _matchesLoading = true);
    try {
      // 항상 미필터 전체 조회 — 경기 세그는 필터와 무관하게 전체 유지 (2026-08-19)
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/user/lookup/matches'
            '?name=${Uri.encodeComponent(name)}&mode=$_mode'),
      ).timeout(const Duration(seconds: 40));
      final data = json.decode(response.body);
      if (mounted && data['success'] == true) {
        setState(() => _matches = data);
        // 필터가 걸려 있으면 필터 결과도 갱신
        if (_filterActive) _loadFilteredMatches();
        // 최초 조회 시 100경기가 안 되면 자동으로 한 번 과거 수집 (+100)
        final stored = (data['stored_total'] as num? ?? 0).toInt();
        if (!_autoBackfilled &&
            data['found'] == true &&
            stored < 100 &&
            data['backfill_done'] != true) {
          _autoBackfilled = true;
          _backfill();
        }
      }
    } catch (e) {
      print('[SearchTab] 전적 로드 실패: $e');
    } finally {
      if (mounted) setState(() => _matchesLoading = false);
    }
  }

  // 필터(클럽/키워드) 적용 조회 — 전적 세그 전용, _matches(전체)는 건드리지 않음
  Future<void> _loadFilteredMatches() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    if (!_filterActive) {
      setState(() => _filteredMatches = null);
      return;
    }
    setState(() {
      _filteredLoading = true;
      _visibleFiltered = 100;
    });
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/user/lookup/matches'
            '?name=${Uri.encodeComponent(name)}&mode=$_mode'
            '&club=${Uri.encodeComponent(_club)}'
            '&kw=${Uri.encodeComponent(_kwController.text.trim())}'),
      ).timeout(const Duration(seconds: 40));
      final data = json.decode(response.body);
      if (mounted && data['success'] == true) {
        setState(() => _filteredMatches = data);
      }
    } catch (e) {
      print('[SearchTab] 필터 전적 로드 실패: $e');
    } finally {
      if (mounted) setState(() => _filteredLoading = false);
    }
  }

  Future<void> _backfill() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _backfilling) return;
    setState(() => _backfilling = true);
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/user/lookup/backfill'
            '?name=${Uri.encodeComponent(name)}&mode=$_mode'),
      ).timeout(const Duration(seconds: 90));
      final data = json.decode(response.body);
      if (mounted && data['success'] == true) {
        setState(() => _matches = data);
        // 필터가 걸려 있으면 필터 결과도 새 수집분 반영
        if (_filterActive) _loadFilteredMatches();
        final bf = data['backfill'];
        if (bf != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(bf['exhausted'] == true
                  ? '과거 경기를 모두 수집했습니다.'
                  : '+${bf['added']}경기 수집 (누적 ${data['stored_total']}경기)')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('경기 수집 중 오류가 발생했습니다.')));
      }
    } finally {
      if (mounted) setState(() => _backfilling = false);
    }
  }

  Color get _accent => Theme.of(context).colorScheme.primary;
  Color get _subColor => Colors.grey.shade500;
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  // 승무패 색 (색상 프리셋 2026-09-04: 승=승리색·무=중립 회색·패=패배색, 라이트는 대비 보정)
  Color get _winColor => PanenkaTokens.of(context).winInk;
  Color get _drawColor =>
      _isDark ? const Color(0xFF8B87A0) : const Color(0xFF6E6884);
  Color get _loseColor => PanenkaTokens.of(context).loseInk;

  Widget _tierLogo(String? url, {double size = 44}) {
    if (url == null || url.isEmpty) {
      return Icon(Icons.shield_outlined, size: size, color: _subColor);
    }
    return Image.network(url,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (c, e, s) =>
            Icon(Icons.shield_outlined, size: size, color: _subColor));
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: _subColor)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _kvRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          SizedBox(
              width: 96,
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: _subColor))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  // 당겨서 새로고침 — 현재 세그먼트의 데이터만 재조회 (로딩 정책 2026-08-19)
  Future<void> _refreshCurrent() async {
    if (_result == null || _result!['found'] != true) {
      await _loadClubs(); // 결과가 없으면 갱신할 데이터 없음 (클럽 목록만)
      return;
    }
    switch (_resultSeg) {
      case 0:
        await _refreshOverview();
        break;
      case 1:
        await _loadSquad(force: true);
        break;
      case 2:
      case 3:
        await _loadMatches();
        break;
      case 4:
        await _loadMining(force: true);
        break;
    }
  }

  // 개요(현재 랭킹)만 재조회 — 세그·다른 캐시는 건드리지 않음
  Future<void> _refreshOverview() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/user/lookup/manager'
            '?name=${Uri.encodeComponent(name)}&mode=$_mode'),
      ).timeout(const Duration(seconds: 25));
      final data = json.decode(response.body);
      if (mounted && response.statusCode == 200 && data['success'] == true) {
        setState(() => _result = data);
      }
    } catch (e) {
      print('[SearchTab] 개요 새로고침 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _refreshCurrent,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('감독 검색',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: _accent)),
          const SizedBox(height: 12),
          _buildSearchBar(),
          const SizedBox(height: 10),
          PillTabs(
            labels: _modeLabels.values.toList(),
            selectedIndex: _modeLabels.keys.toList().indexOf(_mode),
            onSelected: (i) =>
                setState(() => _mode = _modeLabels.keys.toList()[i]),
          ),
          const SizedBox(height: 14),
          if (_error != null)
            Card(
              color: Colors.red.withOpacity(0.1),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child:
                    Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            ),
          // 로딩 중에는 최근 검색을 숨기고 로딩만 표시 (사용자 지정)
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (!_loading && _result == null && _error == null)
            _buildRecentList(),
          if (!_loading && _result != null) ..._buildResult(),
        ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent, width: 1.4),
      ),
      child: TextField(
        controller: _nameController,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _search(),
        decoration: InputDecoration(
          hintText: '감독명 검색',
          hintStyle: TextStyle(color: _subColor),
          prefixIcon: Icon(Icons.search, color: _subColor),
          suffixIcon: _loading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_nameController.text.isNotEmpty)
                      IconButton(
                          icon: Icon(Icons.close,
                              size: 18, color: _subColor),
                          onPressed: () => _nameController.clear()),
                    IconButton(
                        icon: Icon(Icons.arrow_forward, color: _accent),
                        onPressed: _search),
                  ],
                ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
        ),
      ),
    );
  }

  Widget _buildRecentList() {
    if (_recent.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(
          child: Text('감독명을 입력해 순위·티어·전적을 조회하세요.',
              style: TextStyle(color: _subColor)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('최근 검색',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        ...List.generate(_recent.length, (i) {
          final r = _recent[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: _tierLogo(r['tier_icon'], size: 38),
            title: Text(r['name'] ?? '',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
                '${r['tier'] ?? ''} · ${_modeLabels[r['mode']] ?? r['mode']}',
                style: TextStyle(fontSize: 12, color: _subColor)),
            trailing: IconButton(
              icon: Icon(Icons.close, size: 18, color: _subColor),
              onPressed: () async {
                final list = await RecentSearchStore.removeAt(i);
                if (mounted) setState(() => _recent = list);
              },
            ),
            onTap: () {
              _nameController.text = r['name'] ?? '';
              setState(() => _mode = r['mode'] ?? 'manager');
              _search();
            },
          );
        }),
      ],
    );
  }

  List<Widget> _buildResult() {
    final res = _result!;
    final dateInfo = res['date_info'] ?? '';
    if (res['found'] != true) {
      return [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${res['name']} · ${_modeLabels[res['mode']] ?? res['mode']}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('랭킹 데이터에 없는 감독명입니다.'),
              ],
            ),
          ),
        ),
      ];
    }
    final d = Map<String, dynamic>.from(res['data'] ?? {});
    final showMatches = _mode != '2vs2';
    return [
      // 헤더: 티어 로고 + 이름
      Row(
        children: [
          _tierLogo(d['tier_icon']?.toString(), size: 48),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(res['name'] ?? '',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                Text(
                    '${d['tier'] ?? ''} · ${_modeLabels[res['mode']] ?? ''}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _accent)),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      // 결과 탭 (A안: 개요 | 전적 | 경기 | 채굴 — 모드 탭과 동일한 알약 스타일·동일 폭)
      if (showMatches) ...[
        PillTabs(
          labels: const ['개요', '스쿼드', '전적', '경기', '채굴'],
          selectedIndex: _resultSeg,
          onSelected: (i) {
            setState(() => _resultSeg = i);
            if (i == 1 && _squad == null) _loadSquad();
            if (i == 4 && _mining == null) _loadMining();
          },
        ),
        const SizedBox(height: 12),
      ],
      if (!showMatches || _resultSeg == 0) ..._buildOverview(d),
      if (showMatches && _resultSeg == 1) ..._buildSquadSeg(),
      if (showMatches && _resultSeg == 2) ..._buildRecordSeg(),
      if (showMatches && _resultSeg == 3) ..._buildMatchListSeg(),
      if (showMatches && _resultSeg == 4) ..._buildMiningSeg(),
      if (dateInfo.toString().isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('※ $dateInfo 데이터',
              style: TextStyle(fontSize: 12, color: _subColor)),
        ),
    ];
  }

  /// 등급명 → 넥슨 티어 로고 URL.
  /// 등급 순서(높은 순) = ico_rank0~20 순번 — 2026-08-19 update_2026 아이콘 21종 실측 확인
  /// (슈챔 왕관·챌린저 청록·마스터 초록·월클 보라·프로 주황·유망주 살구로 그룹 일치 검증).
  static const List<String> _tierOrder = [
    '슈퍼 챔피언스', '챔피언스', '슈퍼 챌린지',
    '챌린저1', '챌린저2', '챌린저3',
    '마스터1', '마스터2', '마스터3',
    '월드클래스1', '월드클래스2', '월드클래스3',
    '프로1', '프로2', '프로3',
    '세미프로1', '세미프로2', '세미프로3',
    '유망주1', '유망주2', '유망주3',
  ];

  String? _tierIconUrl(String tier) {
    final idx = _tierOrder.indexOf(tier.trim());
    if (idx < 0) return null;
    return 'https://ssl.nexon.com/s2/game/fo4/obt/rank/large/update_2026/ico_rank${idx}_m.png';
  }

  // ── 개요 세그: 현재 랭킹 + 역대 최고 등급 ──
  List<Widget> _buildOverview(Map<String, dynamic> d) {
    final maxDiv = _result!['max_division'] as Map<String, dynamic>?;
    return [
      _sectionCard(title: '현재 랭킹', children: [
        _kvRow('순위',
            d['rank']?.toString().isNotEmpty == true ? '${d['rank']}위' : '-'),
        _kvRow('점수', d['score']?.toString() ?? '-'),
        _kvRow('구단가치', d['price']?.toString() ?? '-'),
        _kvRow('승률', d['win_rate']?.toString() ?? '-'),
        _kvRow('전적 (승|무|패)', d['wdl']?.toString() ?? '-'),
        _kvRow('팀컬러', d['team_color']?.toString() ?? '-'),
        _kvRow('포메이션', d['formation']?.toString() ?? '-'),
      ]),
      if (maxDiv != null)
        _sectionCard(title: '역대 최고 등급', children: [
          for (final entry in [
            ['manager', '감독모드'],
            ['1vs1', '1vs1'],
          ])
            if (maxDiv[entry[0]] != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                        width: 70,
                        child: Text(entry[1],
                            style:
                                TextStyle(fontSize: 13, color: _subColor))),
                    // 등급명 앞 티어 로고 (텍스트 크기에 맞춤 — 2026-08-19 사용자 지시)
                    if (_tierIconUrl(maxDiv[entry[0]]['tier'] ?? '') != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Image.network(
                          _tierIconUrl(maxDiv[entry[0]]['tier'] ?? '')!,
                          height: 20,
                          errorBuilder: (c, e, s) => const SizedBox.shrink(),
                        ),
                      ),
                    Text(maxDiv[entry[0]]['tier'] ?? '',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Text('${maxDiv[entry[0]]['date'] ?? ''} 달성',
                        style: TextStyle(fontSize: 12, color: _subColor)),
                  ],
                ),
              ),
        ]),
    ];
  }

  // ── 전적 세그: 승무패 + 필터 + 포메이션 승률/상성 ──
  // 2026-08-19 개편: 상대전적 섹션 제거(사용자 확정), 필터 활성 시 그 자리에
  // 필터된 경기 목록(탭 → 경기분석) 표시. 경기 세그는 항상 전체 유지.
  List<Widget> _buildRecordSeg() {
    if (_matchesLoading && _matches == null) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    // 필터 활성 시 요약·포메이션도 필터된 응답 기준 (기존 동작 유지)
    final m = _filterActive ? (_filteredMatches ?? _matches) : _matches;
    if (m == null || m['found'] != true) {
      return [
        _sectionCard(title: '전적', children: [
          Text('전적 데이터를 찾지 못했습니다.',
              style: TextStyle(color: _subColor, fontSize: 13)),
        ]),
      ];
    }
    final summary = Map<String, dynamic>.from(m['summary'] ?? {});
    final myTactics = (m['my_tactics'] as List? ?? []);
    final oppTactics = (m['opp_tactics'] as List? ?? []);
    final total = summary['total'] ?? 0;
    final filteredList =
        _filterActive ? (_filteredMatches?['matches'] as List? ?? []) : [];
    return [
      _sectionCard(title: '전적 (수집 ${m['stored_total']}경기)', children: [
        Row(
          children: [
            // 승무패 색: 전체 UI 톤 통일 — 승=퍼플·무=퍼플그레이·패=로즈 (상태탭 A안 규칙)
            _wdlBox('승', summary['win'] ?? 0, _winColor),
            const SizedBox(width: 6),
            _wdlBox('무', summary['draw'] ?? 0, _drawColor),
            const SizedBox(width: 6),
            _wdlBox('패', summary['lose'] ?? 0, _loseColor),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${summary['win_rate'] ?? '-'}%',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _accent)),
                Text('$total경기 승률',
                    style: TextStyle(fontSize: 11, color: _subColor)),
              ],
            ),
          ],
        ),
        if ((summary['forfeit_win'] ?? 0) > 0 ||
            (summary['forfeit_lose'] ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                '몰수승 ${summary['forfeit_win'] ?? 0} · 몰수패 ${summary['forfeit_lose'] ?? 0}',
                style: TextStyle(fontSize: 11, color: _subColor)),
          ),
        const SizedBox(height: 10),
        // 필터 (클럽 / 키워드) — 전적 세그 전용 (경기 세그는 항상 전체)
        Row(
          children: [
            Expanded(
              child: DropdownButton<String>(
                value: _club,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: '', child: Text('전체 상대')),
                  ..._clubs.map((c) =>
                      DropdownMenuItem(value: c, child: Text('클럽: $c'))),
                ],
                onChanged: (v) {
                  setState(() => _club = v ?? '');
                  _loadFilteredMatches();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _kwController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _loadFilteredMatches(),
                decoration: const InputDecoration(
                  hintText: '상대명 키워드',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        if (_filterActive && _filteredMatches != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('필터 결과 ${_filteredMatches!['filtered_total']}경기',
                style: TextStyle(fontSize: 11, color: _subColor)),
          ),
      ]),
      // 필터 활성 시: 필터된 경기 목록 (탭 → 경기분석)
      if (_filterActive) ...[
        if (_filteredLoading && _filteredMatches == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (filteredList.isNotEmpty)
          _sectionCard(title: '필터된 경기 목록', children: [
            for (final match in filteredList.take(_visibleFiltered))
              _matchRow(match),
            if (filteredList.length > _visibleFiltered)
              TextButton(
                onPressed: () => setState(() => _visibleFiltered += 100),
                child: Text(
                    '더 보기 (${filteredList.length - _visibleFiltered}경기 남음)'),
              ),
          ])
        else if (_filteredMatches != null)
          _sectionCard(title: '필터된 경기 목록', children: [
            Text('필터 조건에 맞는 경기가 없습니다.',
                style: TextStyle(fontSize: 13, color: _subColor)),
          ]),
      ],
      if (myTactics.isNotEmpty)
        _sectionCard(title: '내 포메이션별 승률', children: [
          for (final t in myTactics.take(6)) _tacticRow(t),
        ]),
      if (oppTactics.isNotEmpty)
        _sectionCard(title: '상대 포메이션 상성', children: [
          for (final t in oppTactics.take(6)) _tacticRow(t),
        ]),
    ];
  }

  // ── 경기 세그: 목록(최초 100) + 더 보기 + 과거 수집 ──
  List<Widget> _buildMatchListSeg() {
    if (_matchesLoading && _matches == null) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    final m = _matches;
    if (m == null || m['found'] != true) {
      return [
        _sectionCard(title: '경기 목록', children: [
          Text('경기 데이터를 찾지 못했습니다.',
              style: TextStyle(color: _subColor, fontSize: 13)),
        ]),
      ];
    }
    final matches = (m['matches'] as List? ?? []);
    return [
      // 경기 세그는 필터와 무관하게 항상 전체 경기 표시 (2026-08-19 확정)
      _sectionCard(
          title: '경기 목록 (${matches.length}경기)',
          children: [
            for (final match in matches.take(_visibleMatches))
              _matchRow(match),
            if (matches.length > _visibleMatches)
              TextButton(
                onPressed: () => setState(() => _visibleMatches += 100),
                child:
                    Text('더 보기 (${matches.length - _visibleMatches}경기 남음)'),
              ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: (m['backfill_done'] == true || _backfilling)
                    ? null
                    : _backfill,
                icon: _backfilling
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.history, size: 16),
                label: Text(m['backfill_done'] == true
                    ? '과거 경기 수집 완료'
                    : (_backfilling ? '수집 중...' : '+100경기 더 수집')),
              ),
            ),
          ]),
    ];
  }

  // ── 채굴 세그: 기간 필터 + 승리당 FC 합산 ──
  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadMining({bool force = false}) async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _miningLoading) return;
    final period = _miningPeriod;
    // 기간별 캐시 유지 — 탭/기간 전환 재호출 없음, 당겨서 새로고침만 재조회 (2026-08-19)
    if (!force && _miningCache[period] != null) return;
    // 이전 데이터를 비우지 않는다 — 성공 시에만 교체 (실패 시 이전 데이터 유지)
    setState(() => _miningLoading = true);
    try {
      final now = DateTime.now();
      final from = period == 0
          ? _dateStr(now)
          : _dateStr(now.subtract(const Duration(days: 6)));
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/user/lookup/mining'
            '?name=${Uri.encodeComponent(name)}&mode=$_mode&from=$from'),
      ).timeout(const Duration(seconds: 240)); // 첫 조회는 기간 전체 수집이라 오래 걸릴 수 있음
      final data = json.decode(response.body);
      if (mounted && data['success'] == true) {
        setState(
            () => _miningCache[period] = Map<String, dynamic>.from(data));
      }
    } catch (e) {
      print('[SearchTab] 채굴량 로드 실패: $e');
      if (mounted && _miningCache[period] == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('채굴량 조회에 실패했습니다. 아래로 당겨 다시 시도하세요.')));
      }
    } finally {
      if (mounted) setState(() => _miningLoading = false);
    }
  }

  List<Widget> _buildMiningSeg() {
    final widgets = <Widget>[
      PillTabs(
        labels: const ['오늘', '7일'],
        selectedIndex: _miningPeriod,
        onSelected: (i) {
          setState(() => _miningPeriod = i);
          _loadMining(); // 기간별 캐시 있으면 즉시 표시, 없을 때만 조회
        },
      ),
      const SizedBox(height: 12),
    ];
    if (_miningLoading && _mining == null) {
      widgets.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ));
      return widgets;
    }
    final m = _mining;
    if (m == null || m['found'] != true) {
      widgets.add(_sectionCard(title: 'FC 채굴량', children: [
        Text('채굴량 데이터를 찾지 못했습니다.',
            style: TextStyle(color: _subColor, fontSize: 13)),
      ]));
      return widgets;
    }
    final totalMatches = (m['total_matches'] as num? ?? 0).toInt();
    final breakdown = (m['breakdown'] as List? ?? []);
    final otherWins = (m['other_wins'] as num? ?? 0).toInt();
    final unknownWins = (m['unknown_wins'] as num? ?? 0).toInt();

    if (totalMatches == 0) {
      // 기간 내 수집된 경기가 없는 경우 (사용자 지정 — 명확히 안내)
      widgets.add(_sectionCard(title: 'FC 채굴량', children: [
        Text('이 기간에 수집된 경기가 없습니다.',
            style: TextStyle(fontSize: 13, color: _subColor)),
        const SizedBox(height: 4),
        Text('전적은 조회 시점부터 수집됩니다. 경기 탭의 [+100경기 더 수집]으로 과거 경기를 모으면 채굴량에도 반영됩니다.',
            style: TextStyle(fontSize: 11.5, color: _subColor)),
      ]));
      return widgets;
    }

    widgets.addAll([
      _sectionCard(title: 'FC 채굴량', children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${m['total_fc'] ?? 0}',
                style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    color: _accent)),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('FC',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _accent)),
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${m['wins']}승 ${m['draws']}무 ${m['loses']}패',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                Text('$totalMatches경기 기준',
                    style: TextStyle(fontSize: 11, color: _subColor)),
                // 7일 선택 시 1일 평균 (오늘 포함 최근 7일 ÷ 7 — 2안: 우측 요약 열)
                if (_miningPeriod == 1)
                  Text(
                      '일평균 ${((m['total_fc'] as num? ?? 0) / 7).round()} FC',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: _accent)),
              ],
            ),
          ],
        ),
        const Divider(height: 20),
        if (breakdown.isEmpty && unknownWins == 0)
          Text('챔피언스 이상 티어의 승리가 없어 지급된 FC가 없습니다.',
              style: TextStyle(fontSize: 12.5, color: _subColor)),
        for (final b in breakdown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Text(b['tier'] ?? '',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${b['wins']}승 × ${b['rate']}FC',
                    style: TextStyle(fontSize: 12, color: _subColor)),
                const SizedBox(width: 8),
                Text('${b['fc']}FC',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _accent)),
              ],
            ),
          ),
        if (otherWins > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('챔피언스 미만 승리 $otherWins건',
                style: TextStyle(fontSize: 11.5, color: _subColor)),
          ),
        if (unknownWins > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                '티어 정보가 없는 승리 $unknownWins건은 제외했습니다. 다시 조회하면 추가로 채워집니다.',
                style: TextStyle(fontSize: 11.5, color: _subColor)),
          ),
        if (m['covered'] == false)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                '기간 내 경기가 많아 일부만 수집했습니다. 다시 조회하면 이어서 수집됩니다.'
                '${_miningPeriod == 1 ? ' 일평균도 수집된 경기 기준입니다.' : ''}',
                style: TextStyle(fontSize: 11.5, color: Colors.orange)),
          ),
      ]),
      Text(
        '승리당 지급: 감독모드 챔피언스 15 · 슈챔 20 / 1vs1 챔피언스 30 · 슈챔 40 FC',
        style: TextStyle(fontSize: 11, color: _subColor),
      ),
    ]);
    return widgets;
  }

  // ── 스쿼드 세그: 감독의 최근 경기 라인업 (서버 user-squad — !라인업 방식) ──
  Future<void> _loadSquad({bool force = false}) async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _squadLoading) return;
    if (!force && _squad != null && _squad!['success'] == true) return;
    // 이전 데이터를 비우지 않는다 — 성공 시에만 교체 (로딩 정책 2026-08-19)
    setState(() => _squadLoading = true);
    try {
      final mode = _mode == '1vs1' ? '1vs1' : 'manager';
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/user/squad/user-squad'
            '?name=${Uri.encodeComponent(name)}&mode=$mode'),
      ).timeout(const Duration(seconds: 40));
      final data = json.decode(response.body);
      if (mounted) {
        final parsed = Map<String, dynamic>.from(data);
        // 실패 응답은 보여줄 이전 데이터가 없을 때만 채택 (안내 문구 표시용)
        if (parsed['success'] == true ||
            _squad == null ||
            _squad!['success'] != true) {
          setState(() => _squad = parsed);
        }
      }
    } catch (e) {
      print('[SearchTab] 스쿼드 로드 실패: $e');
    } finally {
      if (mounted) setState(() => _squadLoading = false);
    }
  }

  List<Widget> _buildSquadSeg() {
    if (_squadLoading && _squad == null) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    final s = _squad;
    if (s == null || s['success'] != true) {
      return [
        _sectionCard(title: '최근 경기 스쿼드', children: [
          Text(s?['message'] ?? '최근 경기 스쿼드를 찾지 못했습니다.',
              style: TextStyle(fontSize: 13, color: _subColor)),
        ]),
      ];
    }
    final players = (s['players'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return [
      Row(
        children: [
          Text('최근 경기 선발 스쿼드',
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const Spacer(),
          if ((s['formation5'] ?? '').toString().isNotEmpty)
            Text('포메이션 ${s['formation5']}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _accent)),
        ],
      ),
      const SizedBox(height: 8),
      _squadFieldView(players),
      const SizedBox(height: 6),
      Text('가장 최근 경기의 선발 11명 기준입니다.',
          style: TextStyle(fontSize: 11, color: _subColor)),
    ];
  }

  Widget _squadFieldView(List<Map<String, dynamic>> players) {
    return AspectRatio(
      aspectRatio: 0.75,
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
                for (final p in players)
                  Builder(builder: (context) {
                    final pos = (p['sp_position'] as num?)?.toInt() ?? 14;
                    final role = kSpposRole[pos] ?? 'cm';
                    final coord = kRoleCoord[role] ?? const [50, 40];
                    final fx = coord[0] / 100.0;
                    final fy = (85 - coord[1]) / 100.0;
                    final spid = (p['spid'] as num?)?.toInt();
                    // 공용 카드 (2026-08-19 재확정 배치):
                    // 좌상 POS·아래 신규특성 / 좌하 시즌·우하 강화 (카드 내부 처리)
                    return Positioned(
                      left: (w - cardW) * fx,
                      top: 8 + (h - cardW * 0.62 - 50) * fy,
                      child: PlayerFieldCard(
                        cardW: cardW,
                        spPos: pos,
                        spid: spid,
                        faceUrl:
                            'https://fco.dn.nexoncdn.co.kr/live/externalAssets/common/playersAction/p$spid.png',
                        name: '${p['name']}',
                        grade: (p['grade'] as num? ?? 1).toInt(),
                        seasonFallback: p['season']?.toString(),
                        // 카드 탭 → 집훈 계산기 (2026-08-22)
                        onTap: spid == null
                            ? null
                            : () => Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => TrainingCalcScreen(
                                    spid: spid,
                                    name: '${p['name']}',
                                    grade: (p['grade'] as num? ?? 1).toInt(),
                                    role: role,
                                    faceUrl:
                                        'https://fco.dn.nexoncdn.co.kr/live/externalAssets/common/playersAction/p$spid.png',
                                    season: p['season']?.toString(),
                                  ),
                                )),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _wdlBox(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text('$count',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: _subColor)),
        ],
      ),
    );
  }

  Widget _tacticRow(dynamic t) {
    final rate = (t['win_rate'] as num? ?? 0).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(t['formation'] ?? '',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(
                  '${t['win']}승 ${t['draw']}무 ${t['lose']}패 · ${t['win_rate']}%',
                  style: TextStyle(fontSize: 12, color: _subColor)),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: rate / 100,
              minHeight: 5,
              backgroundColor: Colors.grey.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation(_accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _matchRow(dynamic match) {
    final result = match['result']?.toString() ?? '';
    final isWin = result.contains('승');
    final isLose = result.contains('패');
    // 승무패 색 통일 (상태탭 A안 규칙과 동일)
    final color = isWin ? _winColor : (isLose ? _loseColor : _drawColor);
    return InkWell(
      onTap: match['match_id'] == null
          ? null
          : () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MatchDetailScreen(
                    matchId: match['match_id'],
                    myName: _nameController.text.trim(),
                    mode: _mode,
                  ),
                ),
              );
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Text(result.isNotEmpty ? result.substring(0, 1) : '?',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: color)),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('vs ${match['opp'] ?? '?'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('${match['ts'] ?? ''} · ${match['opp_form'] ?? ''}',
                      style: TextStyle(fontSize: 10.5, color: _subColor)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${match['my_goal']} : ${match['opp_goal']}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
                // 승부차기 표기: "2:2" + "승부차기 1:4" (사용자 지정 형식)
                if ((match['my_pk'] ?? 0) > 0 || (match['opp_pk'] ?? 0) > 0)
                  Text('승부차기 ${match['my_pk']}:${match['opp_pk']}',
                      style: TextStyle(fontSize: 10, color: _subColor)),
              ],
            ),
            Icon(Icons.chevron_right, size: 18, color: _subColor),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.requestNotifier?.removeListener(_onExternalRequest);
    _nameController.dispose();
    _kwController.dispose();
    super.dispose();
  }
}
