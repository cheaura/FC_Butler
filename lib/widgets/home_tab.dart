import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/recent_search_store.dart';

/// 홈 탭 — 벤토 위젯 보드 (허브 역할, 사용자 확정 구조).
/// 타일을 누르면 해당 하단 탭으로 이동만 한다 (검색 타일 → 검색 탭 등).
/// 구성: 감독 검색 / 시즌 D-day / 실시간 랭킹(3모드 TOP3) / 최근 감독 / 랭커 스쿼드 / 컷라인.
class HomeTab extends StatefulWidget {
  /// 하단 탭 전환 콜백 ('search' | 'ranking' | 'squad' | 'market' | 'more')
  final void Function(String dest)? onNavigate;

  /// 검색 탭으로 이동하면서 특정 감독 즉시 검색 (최근 감독 탭 시)
  final void Function(String name, String mode)? onSearch;

  const HomeTab({Key? key, this.onNavigate, this.onSearch}) : super(key: key);

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with AutomaticKeepAliveClientMixin {
  final _apiService = ApiService();
  List<Map<String, dynamic>> _recent = [];
  // 모드별 실시간 랭킹 TOP3 (사용자 지정: 감독모드·1vs1·2vs2 전부 표시)
  final Map<String, List<Map<String, String>>> _top3 = {};
  String? _superCut;
  String? _weeklyCut;
  String? _cutDate;
  bool _cutLoading = false;
  // 시즌 D-day (서버 season_config — 공식경기 전/후반기·감독모드, fc-info.com 대문 표기 동일)
  Map<String, dynamic>? _seasonDday;

  static const _rankModes = [
    ['manager', '감독모드'],
    ['1vs1', '1vs1'],
    ['2vs2', '2vs2'],
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  // 컷라인·랭킹은 앱 시작 시 1회만 조회, 이후엔 당겨서 새로고침할 때만 (사용자 지정)
  static bool _netLoadedOnce = false;

  Future<void> _refresh({bool force = false}) async {
    RecentSearchStore.load().then((list) {
      if (mounted) setState(() => _recent = list);
    });
    await _loadCachedCutline();
    if (!force && _netLoadedOnce) return;
    _netLoadedOnce = true;
    _loadTop3();
    _loadCutline();
    _loadSeasonDday();
  }

  // 시즌 D-day — 마지막 값 캐시로 즉시 표시 후 서버 갱신 (컷라인과 같은 방식)
  Future<void> _loadSeasonDday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('home_season_dday');
      if (cached != null && mounted && _seasonDday == null) {
        setState(() =>
            _seasonDday = json.decode(cached) as Map<String, dynamic>);
      }
    } catch (_) {}
    try {
      final response = await http
          .get(Uri.parse('${ApiService.baseUrl}/api/user/lookup/season_dday'))
          .timeout(const Duration(seconds: 15));
      final data = json.decode(response.body);
      if (data['success'] != true || data['dday'] == null) return;
      final dday = data['dday'] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _seasonDday = dday);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('home_season_dday', json.encode(dday));
    } catch (e) {
      print('[HomeTab] 시즌 D-day 로드 실패: $e');
    }
  }

  // "공식경기 시즌4 후반기 D-18 · 9월 10일(목) 종료" 한 줄 (fc-info.com 대문 형식)
  Widget _seasonDdayRow(IconData icon, Map<String, dynamic>? e) {
    if (e == null) return const SizedBox.shrink();
    final days = (e['days_remaining'] as num?)?.toInt();
    final dText = days == null
        ? '-'
        : (days < 0 ? '종료' : (days == 0 ? 'D-DAY' : 'D-$days'));
    final urgent = days != null && days >= 0 && days <= 3;
    final endLabel = (e['end_label'] ?? e['end_date'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // 앱 공통 아이콘 체계(머티리얼 아웃라인) — 검색 타일 아이콘 박스의 축소형
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 14, color: _accent),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: '${e['mode']} ',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _accent)),
                TextSpan(
                    text: (e['season'] ?? '').toString(),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 오른쪽은 D-day 위·종료일 아래 2단 — 좁은 화면에서도 한 줄 유지 (줄바꿈 금지)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(dText,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      color: urgent ? Colors.redAccent : _accent)),
              if (endLabel.isNotEmpty)
                Text('$endLabel 종료',
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(fontSize: 10, color: _subColor)),
            ],
          ),
        ],
      ),
    );
  }

  // 마지막 컷라인 값을 즉시 표시 (로딩 지연 체감 제거 — 백그라운드에서 갱신)
  Future<void> _loadCachedCutline() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _superCut ??= prefs.getString('home_cut_super');
        _weeklyCut ??= prefs.getString('home_cut_weekly');
        _cutDate ??= prefs.getString('home_cut_date');
      });
    } catch (e) {
      print('[HomeTab] 컷라인 캐시 로드 실패: $e');
    }
  }

  Future<void> _saveCachedCutline() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_superCut != null) await prefs.setString('home_cut_super', _superCut!);
      if (_weeklyCut != null) {
        await prefs.setString('home_cut_weekly', _weeklyCut!);
      }
      if (_cutDate != null) await prefs.setString('home_cut_date', _cutDate!);
    } catch (e) {
      print('[HomeTab] 컷라인 캐시 저장 실패: $e');
    }
  }

  // 실시간 랭킹 TOP3 — 3개 모드 병렬 (랭킹 탭과 동일한 넥슨 페이지 파싱)
  Future<void> _loadTop3() async {
    const headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    };
    await Future.wait(_rankModes.map((m) async {
      final mode = m[0];
      try {
        // 세 모드 동시 요청 시 넥슨이 간헐적으로 빈 200 응답을 주므로 행이 없으면 재시도 (2026-09-05)
        http.Response? response;
        for (var attempt = 0; attempt < 3; attempt++) {
          response = await http.get(
            Uri.parse(
                'https://fconline.nexon.com/datacenter/rank_inner?rt=$mode&n4pageno=1'),
            headers: headers,
          ).timeout(const Duration(seconds: 12));
          if (response.statusCode == 200 && response.body.contains('rank_no')) break;
          await Future.delayed(Duration(milliseconds: 700 * (attempt + 1)));
        }
        if (response == null || response.statusCode != 200) return;
        final doc = html_parser.parse(response.body);
        final rows = doc.querySelectorAll('.tbody .tr');
        final top = <Map<String, String>>[];
        for (final row in rows) {
          final rank = row.querySelector('.rank_no')?.text.trim() ?? '';
          final coach = row
                  .querySelector('.rank_coach .name.profile_pointer')
                  ?.text
                  .trim() ??
              '';
          if (rank.isEmpty || coach.isEmpty || rank == '순위') continue;
          top.add({'rank': rank, 'coach': coach});
          if (top.length >= 3) break;
        }
        if (mounted && top.isNotEmpty) {
          setState(() => _top3[mode] = top);
        }
      } catch (e) {
        print('[HomeTab] TOP3($mode) 로드 실패: $e');
      }
    }));
  }

  Future<void> _loadCutline() async {
    if (_cutLoading) return;
    setState(() => _cutLoading = true);
    // 넥슨 페이지 크롤링이 간헐 실패하므로 종류별 2회 재시도 + 타일 탭으로 수동 재시도
    for (final kind in ['super', 'weekly']) {
      var ok = false;
      for (var attempt = 0; attempt < 2 && !ok; attempt++) {
        try {
          // light=1: 과거 시즌 없이 현재 컷만 — 서버가 즉답 (로딩 지연 개선)
          final response = await http.get(
            Uri.parse('${ApiService.baseUrl}/api/user/lookup/cutline'
                '?kind=$kind&mode=manager&light=1'),
          ).timeout(const Duration(seconds: 20));
          final data = json.decode(response.body);
          final current = (data['success'] == true)
              ? (data['current'] as List? ?? [])
              : [];
          if (current.isEmpty) throw Exception('빈 응답');
          final score = current.last['score']?.toString() ?? '';
          if (!mounted) return;
          setState(() {
            if (kind == 'super') {
              _superCut = score;
            } else {
              _weeklyCut = score;
            }
            _cutDate = data['date_info']?.toString();
          });
          ok = true;
        } catch (e) {
          print('[HomeTab] 컷라인($kind) 로드 실패(${attempt + 1}차): $e');
          if (attempt == 0) {
            await Future.delayed(const Duration(seconds: 1));
          }
        }
      }
    }
    if (mounted) setState(() => _cutLoading = false);
    _saveCachedCutline();
  }

  Color get _accent => Theme.of(context).colorScheme.primary;
  Color get _subColor => Colors.grey.shade500;

  Widget _tileBox({required Widget child, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: child,
      ),
    );
  }

  /// TOP3 순위 금·은·동 원형 배지 — 랭킹 탭 _rankRow 색 체계와 동일
  Widget _medalBadge(String rankStr) {
    Gradient? gradient;
    Color textColor;
    switch (int.tryParse(rankStr)) {
      case 1:
        gradient = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF2C14E), Color(0xFFC9922A)]);
        textColor = const Color(0xFF3A2A05);
        break;
      case 2:
        gradient = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFC9CDD8), Color(0xFF9AA0AE)]);
        textColor = const Color(0xFF2A2E38);
        break;
      case 3:
        gradient = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFD89A6A), Color(0xFFA96F42)]);
        textColor = const Color(0xFF3A2412);
        break;
      default:
        gradient = null;
        textColor = _subColor;
    }
    return Container(
      width: 14,
      height: 14,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient),
      child: Text(rankStr,
          style: TextStyle(
              fontSize: 8.5, fontWeight: FontWeight.w800, color: textColor)),
    );
  }

  Widget _tileLabel(String text, {Widget? trailing}) {
    return Row(
      children: [
        Text(text,
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w800,
                color: _subColor)),
        if (trailing != null) ...[const Spacer(), trailing],
      ],
    );
  }

  Widget _tierLogo(String? url, {double size = 26}) {
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final loggedIn = _apiService.isLoggedIn;
    return RefreshIndicator(
      onRefresh: () async => _refresh(force: true), // 당겨서 새로고침은 항상 갱신
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 브랜드 헤더 + 계정 아바타
            Row(
              children: [
                Text('Panenka',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: _accent)),
                const Spacer(),
                GestureDetector(
                  onTap: () => widget.onNavigate?.call('more'),
                  child: CircleAvatar(
                    radius: 15,
                    backgroundColor:
                        loggedIn ? _accent : Theme.of(context).cardColor,
                    child: loggedIn
                        ? Text(
                            (_apiService.username ?? '?')
                                .substring(0, 1)
                                .toUpperCase(),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white))
                        : Icon(Icons.person_outline,
                            size: 17, color: _subColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // 검색 타일 (와이드) → 검색 탭 이동
            GestureDetector(
              onTap: () => widget.onNavigate?.call('search'),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _accent.withOpacity(0.22),
                      Theme.of(context).cardColor,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _accent.withOpacity(0.35)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _accent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.search,
                          size: 19, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('감독 검색',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w800)),
                        Text('이름으로 순위·티어·전적 조회',
                            style:
                                TextStyle(fontSize: 11, color: _subColor)),
                      ],
                    ),
                    const Spacer(),
                    Icon(Icons.chevron_right, color: _subColor),
                  ],
                ),
              ),
            ),
            if (_seasonDday != null) ...[
              const SizedBox(height: 10),
              // 시즌 D-day (와이드 — 공식경기 전/후반기 + 감독모드, fc-info.com 대문 표기)
              _tileBox(
                onTap: _loadSeasonDday,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _tileLabel('시즌 종료 D-DAY'),
                    const SizedBox(height: 8),
                    // 공식경기=직접 조작(게임패드) / 감독모드=전술 지시만(전술 클립보드, FM 감독)
                    _seasonDdayRow(Icons.sports_esports_outlined,
                        _seasonDday!['official'] as Map<String, dynamic>?),
                    _seasonDdayRow(Icons.assignment_outlined,
                        _seasonDday!['manager'] as Map<String, dynamic>?),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            // 실시간 랭킹 (와이드 — 3모드 TOP3, 사용자 지정)
            _tileBox(
              onTap: () => widget.onNavigate?.call('ranking'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _tileLabel('실시간 랭킹 TOP3',
                      trailing: Text('전체 ›',
                          style:
                              TextStyle(fontSize: 10, color: _accent))),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final m in _rankModes)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m[1],
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: _accent)),
                              const SizedBox(height: 5),
                              if (_top3[m[0]] == null)
                                Text('불러오는 중...',
                                    style: TextStyle(
                                        fontSize: 10, color: _subColor))
                              else
                                for (final t in _top3[m[0]]!)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 3),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // 랭킹 탭과 동일한 금·은·동 원형 배지 (2026-08-19 사용자 지시)
                                        _medalBadge(t['rank'] ?? ''),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(t['coach'] ?? '',
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight:
                                                      FontWeight.w600)),
                                        ),
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
            const SizedBox(height: 10),
            // 최근 감독 + 랭커 스쿼드
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _tileBox(
                      onTap: () => widget.onNavigate?.call('search'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _tileLabel('최근 감독',
                              trailing: Text('전체 ›',
                                  style: TextStyle(
                                      fontSize: 10, color: _subColor))),
                          const SizedBox(height: 8),
                          if (_recent.isEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                              child: Text('아직 검색 기록이\n없습니다.',
                                  style: TextStyle(
                                      fontSize: 11.5, color: _subColor)),
                            ),
                          for (var i = 0; i < _recent.take(2).length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 7),
                              child: GestureDetector(
                                onTap: () => widget.onSearch?.call(
                                    _recent[i]['name'] ?? '',
                                    _recent[i]['mode'] ?? 'manager'),
                                child: Row(
                                  children: [
                                    _tierLogo(_recent[i]['tier_icon'],
                                        size: 26),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(_recent[i]['name'] ?? '',
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight:
                                                      FontWeight.w800)),
                                          Text(_recent[i]['tier'] ?? '',
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight:
                                                      FontWeight.w700,
                                                  color: _accent)),
                                        ],
                                      ),
                                    ),
                                    // 개별 삭제 (사용자 요구)
                                    GestureDetector(
                                      onTap: () async {
                                        final list = await RecentSearchStore
                                            .removeAt(i);
                                        if (mounted) {
                                          setState(() => _recent = list);
                                        }
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: Icon(Icons.close,
                                            size: 13, color: _subColor),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _tileBox(
                      onTap: () => widget.onNavigate?.call('squad'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _tileLabel('랭커 스쿼드'),
                          const SizedBox(height: 8),
                          Container(
                            height: 54,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(9),
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xFF2E7D32),
                                  Color(0xFF1B5E20)
                                ],
                              ),
                            ),
                            child: Stack(
                              children: [
                                for (final pos in const [
                                  [0.46, 0.78],
                                  [0.18, 0.55],
                                  [0.74, 0.55],
                                  [0.32, 0.28],
                                  [0.60, 0.28],
                                  [0.46, 0.08],
                                ])
                                  Align(
                                    alignment:
                                        FractionalOffset(pos[0], pos[1]),
                                    child: Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _accent.withOpacity(0.9),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text('랭커 실사용 스쿼드 만들기 ›',
                              style:
                                  TextStyle(fontSize: 10, color: _accent)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // 컷라인 (와이드)
            _tileBox(
              onTap: _loadCutline, // 크롤링 간헐 실패 대비 — 탭하면 재조회
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _tileLabel('컷라인 (감독모드)',
                      trailing: _cutLoading
                          ? const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5))
                          : null),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('슈챔컷 (20위)',
                                style: TextStyle(
                                    fontSize: 10, color: _subColor)),
                            Text(
                                _superCut ??
                                    (_cutLoading ? '...' : '탭하여 재시도'),
                                style: TextStyle(
                                    fontSize:
                                        _superCut == null && !_cutLoading
                                            ? 11
                                            : 17,
                                    fontWeight: FontWeight.w800,
                                    color:
                                        _superCut == null && !_cutLoading
                                            ? _subColor
                                            : null)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('주차컷 (200위)',
                                style: TextStyle(
                                    fontSize: 10, color: _subColor)),
                            Text(
                                _weeklyCut ??
                                    (_cutLoading ? '...' : '탭하여 재시도'),
                                style: TextStyle(
                                    fontSize:
                                        _weeklyCut == null && !_cutLoading
                                            ? 11
                                            : 17,
                                    fontWeight: FontWeight.w800,
                                    color:
                                        _weeklyCut == null && !_cutLoading
                                            ? _subColor
                                            : null)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_cutDate != null && _cutDate!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('※ $_cutDate 데이터 기준',
                    style: TextStyle(fontSize: 10.5, color: _subColor)),
              ),
          ],
        ),
      ),
    );
  }
}
