import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../constants/positions.dart';
import '../services/api_service.dart';
import '../widgets/badges.dart';
import '../widgets/pill_tabs.dart';
import '../widgets/player_field_card.dart';

/// 경기별 분석 화면 — 전적 목록에서 경기 탭으로 진입.
/// 상단에 양팀 비교 스트립(구단가치·팀컬러·순위·포메이션 — "구단가치 차이가 얼마나
/// 나서 이겼지? 상대 팀컬러가 뭐지?"에 바로 답하는 구조, 사용자 지정) 고정 +
/// [요약 | 스쿼드 | 선수] 알약 탭. 필드 선수 카드에 포지션·강화·시즌·평점 표기,
/// 선수 상세 바텀시트에 현재 시세 표시.
class MatchDetailScreen extends StatefulWidget {
  final String matchId;
  final String myName;
  final String mode; // 팀 랭킹(구단가치·팀컬러) 조회용
  const MatchDetailScreen(
      {Key? key,
      required this.matchId,
      required this.myName,
      this.mode = 'manager'})
      : super(key: key);

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  int _seg = 0;
  int _squadSide = 0; // 스쿼드/선수 세그: 0=나, 1=상대
  // 닉네임 → 랭킹 조회 결과 (구단가치·팀컬러·순위)
  final Map<String, Map<String, dynamic>> _teamInfo = {};
  // spid:grade → 시세 표시 문자열 (바텀시트 캐시)
  final Map<String, String> _priceCache = {};

  /// 선수 status 필드 → 한국어 라벨 (순서 = 표시 순서)
  static const List<List<String>> _statusLabels = [
    ['spRating', '평점'],
    ['goal', '골'],
    ['assist', '도움'],
    ['shoot', '슈팅'],
    ['effectiveShoot', '유효슈팅'],
    ['passTry', '패스 시도'],
    ['passSuccess', '패스 성공'],
    ['dribbleTry', '드리블 시도'],
    ['dribbleSuccess', '드리블 성공'],
    ['ballPossesionTry', '볼 소유 시도'],
    ['ballPossesionSuccess', '볼 소유 성공'],
    ['aerialTry', '공중볼 시도'],
    ['aerialSuccess', '공중볼 성공'],
    ['tackle', '태클'],
    ['tackleTry', '태클 시도'],
    ['tackleSuccess', '태클 성공'],
    ['block', '블록'],
    ['blockTry', '블록 시도'],
    ['intercept', '인터셉트'],
    ['defending', '수비 액션'],
    ['yellowCards', '경고'],
    ['redCards', '퇴장'],
    ['dribble', '드리블 거리(m)'],
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/user/lookup/match-detail'
            '?matchid=${Uri.encodeComponent(widget.matchId)}'
            '&name=${Uri.encodeComponent(widget.myName)}'),
      ).timeout(const Duration(seconds: 30));
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() => _data = data);
        _loadTeamInfo();
      } else {
        setState(() => _error = data['message'] ?? '경기 상세 조회에 실패했습니다.');
      }
    } catch (e) {
      setState(() => _error = '네트워크 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // 양팀 랭킹 조회 → 구단가치·팀컬러·순위 (서버 120초 캐시라 부담 적음)
  Future<void> _loadTeamInfo() async {
    final names = [
      _me['nickname']?.toString() ?? '',
      _opp['nickname']?.toString() ?? '',
    ];
    await Future.wait(names.where((n) => n.isNotEmpty).map((name) async {
      try {
        final response = await http.get(
          Uri.parse('${ApiService.baseUrl}/api/user/lookup/manager'
              '?name=${Uri.encodeComponent(name)}&mode=${widget.mode}'),
        ).timeout(const Duration(seconds: 25));
        final data = json.decode(response.body);
        if (data['success'] == true && data['found'] == true && mounted) {
          setState(() =>
              _teamInfo[name] = Map<String, dynamic>.from(data['data'] ?? {}));
        }
      } catch (e) {
        print('[MatchDetail] 팀 정보($name) 조회 실패: $e');
      }
    }));
  }

  int get _myIndex => ((_data!['my_index'] as num?) ?? 0).toInt();

  Map<String, dynamic> get _me {
    final sides = _data!['sides'] as List;
    return Map<String, dynamic>.from(sides[_myIndex]);
  }

  Map<String, dynamic> get _opp {
    final sides = _data!['sides'] as List;
    return Map<String, dynamic>.from(
        sides.length > 1 ? sides[1 - _myIndex] : sides[0]);
  }

  Color get _accent => Theme.of(context).colorScheme.primary;
  Color get _subColor => Colors.grey.shade500;

  num _stat(Map<String, dynamic> side, String group, String key) {
    final g = side[group];
    if (g is Map && g[key] is num) return g[key];
    return 0;
  }

  // "15경 1,893조" → 조 단위 숫자 (구단가치 우세 판정용, 실패 시 null)
  static num? _parsePrice(String? text) {
    if (text == null || text.isEmpty) return null;
    num total = 0;
    var found = false;
    final gyeong = RegExp(r'([\d,]+)\s*경').firstMatch(text);
    if (gyeong != null) {
      total += (num.tryParse(gyeong.group(1)!.replaceAll(',', '')) ?? 0) *
          10000; // 1경 = 1만 조
      found = true;
    }
    final jo = RegExp(r'([\d,]+)\s*조').firstMatch(text);
    if (jo != null) {
      total += num.tryParse(jo.group(1)!.replaceAll(',', '')) ?? 0;
      found = true;
    }
    return found ? total : null;
  }

  static num? _parseRank(String? text) {
    if (text == null) return null;
    return num.tryParse(text.replaceAll(',', '').replaceAll('위', '').trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('경기 분석')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.red)),
                  ),
                )
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        _buildVsStrip(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: PillTabs(
            labels: const ['요약', '스쿼드', '선수'],
            selectedIndex: _seg,
            onSelected: (i) => setState(() => _seg = i),
          ),
        ),
        Expanded(
          child: _seg == 0
              ? _buildSummary()
              : (_seg == 1 ? _buildSquad() : _buildPlayers()),
        ),
      ],
    );
  }

  // ── 양팀 비교 스트립 (항상 상단 고정) ──
  Widget _buildVsStrip() {
    final myName = _me['nickname']?.toString() ?? '';
    final oppName = _opp['nickname']?.toString() ?? '';
    final myInfo = _teamInfo[myName];
    final oppInfo = _teamInfo[oppName];
    final myGoal = _stat(_me, 'shoot', 'goalTotal');
    final oppGoal = _stat(_opp, 'shoot', 'goalTotal');

    final myPrice = _parsePrice(myInfo?['price']?.toString());
    final oppPrice = _parsePrice(oppInfo?['price']?.toString());
    final myRank = _parseRank(myInfo?['rank']?.toString());
    final oppRank = _parseRank(oppInfo?['rank']?.toString());

    Widget vsRow(String label, String? left, String? right,
        {bool? leftWins}) {
      final loading = left == null && right == null;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          children: [
            Expanded(
              child: Text(left ?? (loading ? '조회 중...' : '-'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: leftWins == true ? _accent : null)),
            ),
            SizedBox(
              width: 62,
              child: Center(
                child: Text(label,
                    style: TextStyle(fontSize: 9.5, color: _subColor)),
              ),
            ),
            Expanded(
              child: Text(right ?? (loading ? '조회 중...' : '-'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: leftWins == false ? _accent : null)),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(myName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      children: [
                        Text('$myGoal : $oppGoal',
                            style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: _accent)),
                        Text(_data!['match_date'] ?? '',
                            style:
                                TextStyle(fontSize: 9, color: _subColor)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(oppName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              vsRow('구단가치', myInfo?['price']?.toString(),
                  oppInfo?['price']?.toString(),
                  leftWins: (myPrice != null && oppPrice != null)
                      ? myPrice > oppPrice
                      : null),
              vsRow('팀컬러', myInfo?['team_color']?.toString(),
                  oppInfo?['team_color']?.toString()),
              vsRow(
                  '순위',
                  myInfo?['rank'] != null ? '${myInfo!['rank']}위' : null,
                  oppInfo?['rank'] != null ? '${oppInfo!['rank']}위' : null,
                  leftWins: (myRank != null && oppRank != null)
                      ? myRank < oppRank
                      : null),
              vsRow('포메이션', _me['formation']?.toString(),
                  _opp['formation']?.toString()),
              // 팀 급여 (선발 11명 합, 사용자 지정)
              vsRow(
                  '급여',
                  _me['total_pay'] != null
                      ? '${_me['total_pay']}${_me['pay_complete'] == false ? '+' : ''}'
                      : null,
                  _opp['total_pay'] != null
                      ? '${_opp['total_pay']}${_opp['pay_complete'] == false ? '+' : ''}'
                      : null,
                  leftWins: (_me['total_pay'] is num &&
                          _opp['total_pay'] is num)
                      ? (_me['total_pay'] as num) > (_opp['total_pay'] as num)
                      : null),
            ],
          ),
        ),
      ),
    );
  }

  // ── 요약: 좌우 비교 바 ──
  Widget _buildSummary() {
    final rows = <List<dynamic>>[
      ['점유율(%)', _stat(_me, 'detail', 'possession'), _stat(_opp, 'detail', 'possession')],
      ['슈팅', _stat(_me, 'shoot', 'shootTotal'), _stat(_opp, 'shoot', 'shootTotal')],
      ['유효슈팅', _stat(_me, 'shoot', 'effectiveShootTotal'), _stat(_opp, 'shoot', 'effectiveShootTotal')],
      ['골', _stat(_me, 'shoot', 'goalTotal'), _stat(_opp, 'shoot', 'goalTotal')],
      ['패스 시도', _stat(_me, 'pass', 'passTry'), _stat(_opp, 'pass', 'passTry')],
      ['패스 성공', _stat(_me, 'pass', 'passSuccess'), _stat(_opp, 'pass', 'passSuccess')],
      ['코너킥', _stat(_me, 'detail', 'cornerKick'), _stat(_opp, 'detail', 'cornerKick')],
      ['파울', _stat(_me, 'detail', 'foul'), _stat(_opp, 'detail', 'foul')],
      ['오프사이드', _stat(_me, 'detail', 'offsideCount'), _stat(_opp, 'detail', 'offsideCount')],
      ['경고', _stat(_me, 'detail', 'yellowCards'), _stat(_opp, 'detail', 'yellowCards')],
      ['퇴장', _stat(_me, 'detail', 'redCards'), _stat(_opp, 'detail', 'redCards')],
      ['평균 평점', _stat(_me, 'detail', 'averageRating'), _stat(_opp, 'detail', 'averageRating')],
      ['드리블 거리(m)', _stat(_me, 'detail', 'dribble'), _stat(_opp, 'detail', 'dribble')],
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        for (final r in rows) _compareRow(r[0], r[1], r[2]),
      ],
    );
  }

  Widget _compareRow(String label, num my, num opp) {
    final total = (my + opp) == 0 ? 1 : (my + opp);
    String fmt(num v) =>
        v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);
    final myBetter = my >= opp;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        children: [
          Row(
            children: [
              Text(fmt(my),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: myBetter ? _accent : null)),
              Expanded(
                child: Center(
                  child: Text(label,
                      style: TextStyle(fontSize: 12, color: _subColor)),
                ),
              ),
              Text(fmt(opp),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: !myBetter ? Colors.orange : null)),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                flex: (my / total * 100).round().clamp(1, 99),
                child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                        color: _accent,
                        borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(3)))),
              ),
              const SizedBox(width: 2),
              Expanded(
                flex: (opp / total * 100).round().clamp(1, 99),
                child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.75),
                        borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(3)))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _teamToggle() {
    return PillTabs(
      labels: [
        _me['nickname']?.toString() ?? '나',
        _opp['nickname']?.toString() ?? '상대',
      ],
      selectedIndex: _squadSide,
      onSelected: (i) => setState(() => _squadSide = i),
    );
  }

  // ── 스쿼드: 필드 (선수 카드에 포지션·강화·시즌·평점 — 사용자 지정) ──
  Widget _buildSquad() {
    final side = _squadSide == 0 ? _me : _opp;
    final starters = (side['players'] as List)
        .where((p) => (p['position'] ?? 28) < 28)
        .toList();
    final subs = (side['players'] as List)
        .where((p) => (p['position'] ?? 28) >= 28)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _teamToggle(),
        const SizedBox(height: 10),
        _fieldView(starters),
        if (subs.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('교체 명단',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, color: _subColor)),
          const SizedBox(height: 4),
          for (final p in subs) _playerRow(p, compact: true),
        ],
      ],
    );
  }

  Widget _fieldView(List<dynamic> players) {
    // 평점 최고/최저 선수 판정 (배지 색이 아이콘 역할 — 최고 금색+★, 최저 로즈+▽)
    num? maxRating;
    num? minRating;
    for (final p in players) {
      final r = p['status']?['spRating'] as num?;
      if (r == null) continue;
      if (maxRating == null || r > maxRating) maxRating = r;
      if (minRating == null || r < minRating) minRating = r;
    }
    final distinct = maxRating != null && maxRating != minRating;

    return AspectRatio(
      aspectRatio: 0.72,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final cardW = w / 5.2;
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
                    final pos = (p['position'] as num?)?.toInt() ?? 14;
                    final role = kSpposRole[pos] ?? 'cm';
                    final coord = kRoleCoord[role] ?? const [50, 40];
                    final fx = coord[0] / 100.0;
                    final fy = (85 - coord[1]) / 100.0;
                    final rating = p['status']?['spRating'] as num?;
                    return Positioned(
                      left: (w - cardW) * fx,
                      top: 8 + (h - cardW * 0.62 - 56) * fy,
                      // 공용 카드 (2026-08-19 재확정 배치):
                      // 좌상 POS·아래 신규특성 / 좌하 시즌·우하 강화 / 평점=선수명 아래 알약
                      child: PlayerFieldCard(
                        cardW: cardW,
                        spPos: pos,
                        spid: p['spid'] as num?,
                        faceUrl: p['face_url']?.toString(),
                        name: '${p['name']}',
                        grade: (p['grade'] as num?)?.toInt() ?? 1,
                        rating: rating,
                        isBestRating: rating != null && rating == maxRating,
                        isWorstRating:
                            distinct && rating != null && rating == minRating,
                        seasonFallback: p['season']?.toString(),
                        onTap: () => _showPlayerStats(p),
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

  // ── 선수: 리스트 → 바텀시트 상세 ──
  Widget _buildPlayers() {
    final side = _squadSide == 0 ? _me : _opp;
    final players = List<dynamic>.from(side['players'] as List)
      ..sort((a, b) =>
          ((a['position'] ?? 99) as num).compareTo((b['position'] ?? 99) as num));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _teamToggle(),
        const SizedBox(height: 6),
        for (final p in players) _playerRow(p),
      ],
    );
  }

  Widget _playerRow(dynamic p, {bool compact = false}) {
    final pos = (p['position'] as num?)?.toInt() ?? 28;
    final status = Map<String, dynamic>.from(p['status'] ?? {});
    final rating = status['spRating'];
    return ListTile(
      dense: compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: ClipOval(
        child: Image.network(
          p['face_url'] ?? '',
          width: 38,
          height: 38,
          fit: BoxFit.cover,
          errorBuilder: (c, e, s) => const Icon(Icons.person, size: 38),
        ),
      ),
      title: Row(
        children: [
          if (pos < 28)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: posColor(pos),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(kSpposRole[pos]?.toUpperCase() ?? '',
                  style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
          Flexible(
            child: Text('${p['name']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          SeasonBadge(
              spid: p['spid'] as num?,
              height: 13,
              fallbackText: p['season']?.toString()),
          const SizedBox(width: 5),
          GradeBadge(grade: (p['grade'] as num? ?? 1).toInt(), fontSize: 9.5),
          Flexible(
            child: Text(
                '${(status['goal'] ?? 0) > 0 ? ' ${status['goal']}골' : ''}'
                '${(status['assist'] ?? 0) > 0 ? ' ${status['assist']}도움' : ''}'
                '${p['pay'] != null ? ' · 급여 ${p['pay']}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: _subColor)),
          ),
        ],
      ),
      trailing: rating == null
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text((rating as num).toStringAsFixed(1),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _accent)),
            ),
      onTap: () => _showPlayerStats(p),
    );
  }

  // 선수 시세 조회 (서버 30분 캐시 + 화면 내 캐시)
  Future<String> _fetchPrice(dynamic p) async {
    final key = '${p['spid']}:${p['grade']}';
    if (_priceCache.containsKey(key)) return _priceCache[key]!;
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/user/lookup/player-price'
            '?spid=${p['spid']}&grade=${p['grade']}'),
      ).timeout(const Duration(seconds: 25));
      final data = json.decode(response.body);
      final display = (data['success'] == true && data['display'] != null)
          ? data['display'] as String
          : '시세 없음';
      _priceCache[key] = display;
      return display;
    } catch (e) {
      return '조회 실패';
    }
  }

  void _showPlayerStats(dynamic p) {
    final status = Map<String, dynamic>.from(p['status'] ?? {});
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        maxChildSize: 0.9,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                ClipOval(
                  child: Image.network(
                    p['face_url'] ?? '',
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) =>
                        const Icon(Icons.person, size: 52),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${p['name']}',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      Row(
                        children: [
                          SeasonBadge(
                              spid: p['spid'] as num?,
                              height: 14,
                              fallbackText: p['season']?.toString()),
                          const SizedBox(width: 5),
                          GradeBadge(
                              grade: (p['grade'] as num? ?? 1).toInt(),
                              fontSize: 10),
                          Text(
                              ' ${kSpposRole[(p['position'] as num?)?.toInt() ?? 28]?.toUpperCase() ?? '교체'}'
                              '${p['pay'] != null ? ' · 급여 ${p['pay']}' : ''}',
                              style: TextStyle(
                                  fontSize: 12, color: _subColor)),
                        ],
                      ),
                    ],
                  ),
                ),
                // 현재 시세 (사용자 지정 — 궁금한 정보)
                FutureBuilder<String>(
                  future: _fetchPrice(p),
                  builder: (context, snap) => Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('현재 시세',
                          style:
                              TextStyle(fontSize: 9.5, color: _subColor)),
                      Text(snap.data ?? '조회 중...',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFFFD54F))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final entry in _statusLabels)
              if (status[entry[0]] != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 130,
                          child: Text(entry[1],
                              style: TextStyle(
                                  fontSize: 13, color: _subColor))),
                      Text(
                          entry[0] == 'spRating'
                              ? (status[entry[0]] as num).toStringAsFixed(1)
                              : '${status[entry[0]]}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
