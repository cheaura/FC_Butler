import 'package:flutter/material.dart';

import '../models/player_query.dart';
import '../providers/theme_provider.dart';
import '../screens/player_detail_screen.dart';
import '../screens/training_calc_screen.dart';
import '../services/error_reporter.dart';
import '../services/favorite_player_store.dart';
import '../services/player_api.dart';
import '../services/player_calc.dart';
import 'badges.dart';
import 'face_image.dart';
import 'pill_tabs.dart';
import 'player_compare_sheet.dart';
import 'player_filter_sheet.dart';
import 'player_list_row.dart';

/// '선수(집훈)' 탭 (2026-09-30 — 기존 집훈 탭 자리).
///
/// 위에서 '선수 검색 / 집훈 계산기' 둘로 나눈다(시안 후보 1 확정).
/// 선수 검색: 이름(쉼표로 여러 명)·조건 검색 → 목록 → 줄마다 상세·비교 버튼. 검색 전에는 최근 검색과 관심선수를 보여준다.
/// 비교: 비교 버튼을 누른 첫 선수를 목록 위에 고정하고, 다른 선수의 비교 버튼을 누르면 비교 팝업이 뜬다.
class PlayerTab extends StatefulWidget {
  const PlayerTab({super.key});

  @override
  State<PlayerTab> createState() => _PlayerTabState();
}

class _PlayerTabState extends State<PlayerTab> with AutomaticKeepAliveClientMixin {
  /// 정렬 선택지: (서버 정렬 키, 내림차순 여부, 표시 이름)
  static const _sorts = [
    ('ovr', true, 'OVR 높은 순'),
    ('pay', false, '급여 낮은 순'),
    ('pay', true, '급여 높은 순'),
    ('price', true, '선수 가치 높은 순'),
    ('price', false, '선수 가치 낮은 순'),
  ];

  int _seg = 0; // 0 = 선수 검색, 1 = 집훈 계산기
  final _nameCtrl = TextEditingController();
  PlayerQuery _query = PlayerQuery();
  List<Map<String, dynamic>>? _rows; // null = 아직 검색 전 (홈 화면)
  bool _truncated = false;
  bool _loading = false;
  String? _error;
  List<PlayerQuery> _recent = [];

  /// 비교 첫 번째 선수 (목록 위 고정) — 검색 결과·관심선수 공통
  Map<String, dynamic>? _compareFirst;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    FavoritePlayerStore.ensureLoaded();
    PlayerRecentStore.load().then((list) {
      if (mounted) setState(() => _recent = list);
    });
    // 조건 목록은 미리 받아 둔다 (조건 시트가 바로 열리도록)
    PlayerApi.options();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ── 검색 ──
  Future<void> _runSearch() async {
    _query.name = _nameCtrl.text.trim();
    if (_query.isEmpty) {
      _toast('선수명이나 조건을 입력하세요.');
      return;
    }
    FocusScope.of(context).unfocus();
    final q = _query.copy();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await PlayerApi.search(q);
      if (!mounted) return;
      if (d['success'] != true) {
        setState(() {
          _loading = false;
          _error = '${d['message'] ?? '선수 검색에 실패했습니다. 잠시 후 다시 시도해주세요.'}';
          _rows = const [];
        });
        return;
      }
      final rows = [for (final p in (d['players'] as List? ?? const [])) if (p is Map) Map<String, dynamic>.from(p)];
      setState(() {
        _rows = rows;
        _truncated = d['truncated'] == true;
        _loading = false;
      });
      if (rows.isNotEmpty) {
        final list = await PlayerRecentStore.add(q);
        if (mounted) setState(() => _recent = list);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '네트워크 오류가 발생했습니다.';
          _rows = const [];
        });
      }
    }
  }

  void _clearSearch() {
    setState(() {
      _nameCtrl.clear();
      _query = PlayerQuery()..grade = _query.grade;
      _rows = null;
      _error = null;
      _truncated = false;
    });
  }

  Future<void> _openFilter() async {
    _query.name = _nameCtrl.text.trim();
    final picked = await showPlayerFilterSheet(context, _query);
    if (picked == null || !mounted) return;
    setState(() => _query = picked);
    if (!_query.isEmpty) _runSearch();
  }

  void _applyRecent(PlayerQuery q) {
    setState(() {
      _query = q.copy();
      _nameCtrl.text = q.name;
    });
    _runSearch();
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  // ── 줄 동작 ──
  Future<void> _openDetail(Map<String, dynamic> row) async {
    final r = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => PlayerDetailScreen(row: row, grade: _query.grade),
    ));
    ErrorReporter.currentScreen = '선수 검색';
    if (r == 'compare' && mounted) setState(() => _compareFirst = row);
  }

  void _onCompare(Map<String, dynamic> row) {
    final first = _compareFirst;
    if (first == null) {
      setState(() => _compareFirst = row);
      return;
    }
    if ('${first['spid']}' == '${row['spid']}') return;
    showPlayerCompareSheet(context, first: first, second: row, grade: _query.grade);
  }

  Future<void> _toggleFavorite(Map<String, dynamic> row) async {
    final spid = row['spid'] as num?;
    if (FavoritePlayerStore.contains(spid)) {
      await FavoritePlayerStore.remove(spid);
    } else {
      final ok = await FavoritePlayerStore.add(row);
      if (!ok && mounted) _toast('관심선수는 ${FavoritePlayerStore.max}명까지 등록할 수 있습니다.');
    }
  }

  PlayerCompareMode _modeOf(Map<String, dynamic> row) {
    final first = _compareFirst;
    if (first == null) return PlayerCompareMode.none;
    return '${first['spid']}' == '${row['spid']}' ? PlayerCompareMode.picked : PlayerCompareMode.target;
  }

  Widget _row(Map<String, dynamic> row, List<Map<String, dynamic>> favorites) => PlayerListRow(
        key: ValueKey('p-${row['spid']}'),
        row: row,
        grade: _query.grade,
        favorite: favorites.any((f) => '${f['spid']}' == '${row['spid']}'),
        compare: _modeOf(row),
        onDetail: () => _openDetail(row),
        onCompare: () => _onCompare(row),
        onFavorite: () => _toggleFavorite(row),
      );

  // ── 화면 ──
  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_seg == 0) ErrorReporter.currentScreen = '선수 검색';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: PillTabs(
            labels: const ['선수 검색', '집훈 계산기'],
            selectedIndex: _seg,
            onSelected: (i) => setState(() => _seg = i),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _seg,
            children: [
              _searchBody(),
              const TrainingCalcScreen(asTab: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _searchBody() {
    final tokens = PanenkaTokens.of(context);
    final count = _query.conditionCount;
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: FavoritePlayerStore.players,
      builder: (context, favorites, _) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: TextField(
                      controller: _nameCtrl,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _runSearch(),
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '선수 이름 (쉼표로 여러 명)',
                        hintStyle: TextStyle(fontSize: 13.5, color: tokens.mute),
                        prefixIcon: const Icon(Icons.search, size: 19),
                        suffixIcon: (_nameCtrl.text.isNotEmpty || _rows != null)
                            ? IconButton(
                                tooltip: '검색 지우기',
                                icon: const Icon(Icons.close, size: 17),
                                onPressed: _clearSearch,
                              )
                            : null,
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _openFilter,
                    icon: const Icon(Icons.tune, size: 17),
                    label: Text(count > 0 ? '조건 $count' : '조건',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
          if (_compareFirst != null) _compareBand(tokens),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_rows == null ? _home(tokens, favorites) : _results(tokens, favorites)),
          ),
        ],
      ),
    );
  }

  /// 비교 첫 번째 선수 고정 띠
  Widget _compareBand(PanenkaTokens tokens) {
    final f = _compareFirst!;
    final ovrs = PlayerCalc.shownPositions(f['positions'] as List?, _query.grade);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
      decoration: BoxDecoration(
        color: tokens.accentSoft,
        border: Border.all(color: tokens.accentInk.withOpacity(.45)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.push_pin, size: 15, color: tokens.accentInk),
                  Text('비교 1', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: tokens.accentInk)),
                ],
              ),
              const SizedBox(width: 8),
              ClipOval(
                child: Container(
                  color: tokens.soft,
                  child: FaceImage(
                      url: f['face_url']?.toString(),
                      spid: f['spid'] as num?,
                      width: 36,
                      height: 36,
                      fallback: Icon(Icons.person, size: 24, color: tokens.mute)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      SeasonBadge(spid: f['spid'] as num?, height: 13, fallbackText: f['season_img']?.toString()),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text('${f['name'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    Text(
                        [
                          ...ovrs.map((p) => '${p.pos} ${p.ovr}'),
                          '급여 ${f['pay'] ?? '-'}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: tokens.subInk)),
                  ],
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(52, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => setState(() => _compareFirst = null),
                child: const Text('해제', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Text('비교할 두 번째 선수의 비교 버튼을 누르세요', style: TextStyle(fontSize: 11, color: tokens.subInk)),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(PanenkaTokens tokens, String title, {String right = '', Widget? action}) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 4),
        child: Row(
          children: [
            Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: tokens.subInk)),
            const Spacer(),
            if (right.isNotEmpty) Text(right, style: TextStyle(fontSize: 11, color: tokens.mute)),
            if (action != null) action,
          ],
        ),
      );

  /// 최근 검색 한 건의 표시 이름 ('손흥민, 메시' / '손흥민 · 조건 2개' / '조건 3개')
  static String recentLabel(PlayerQuery q) {
    final names = q.names.join(', ');
    final c = q.conditionCount;
    if (names.isEmpty) return '조건 $c개';
    return c > 0 ? '$names · 조건 $c개' : names;
  }

  /// 검색 전 화면: 안내 + 최근 검색 + 관심선수
  Widget _home(PanenkaTokens tokens, List<Map<String, dynamic>> favorites) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Text('이름만 넣으면 시즌별 카드가 모두 나옵니다 · 예: 손흥민, 메시',
              style: TextStyle(fontSize: 11, color: tokens.mute)),
        ),
        if (_recent.isNotEmpty) ...[
          _sectionTitle(tokens, '최근 검색',
              action: TextButton(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () async {
                  final list = await PlayerRecentStore.clear();
                  if (mounted) setState(() => _recent = list);
                },
                child: Text('지우기', style: TextStyle(fontSize: 11, color: tokens.mute)),
              )),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final q in _recent)
                  ActionChip(
                    avatar: Icon(q.names.isEmpty ? Icons.tune : Icons.history, size: 15, color: tokens.mute),
                    label: Text(recentLabel(q), style: const TextStyle(fontSize: 12)),
                    onPressed: () => _applyRecent(q),
                  ),
              ],
            ),
          ),
        ],
        _sectionTitle(tokens, '관심선수', right: '${favorites.length} / ${FavoritePlayerStore.max}'),
        if (favorites.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('목록에서 별을 누르면 관심선수로 등록됩니다.', style: TextStyle(fontSize: 12, color: tokens.mute)),
          )
        else
          for (final f in favorites) _row(f, favorites),
      ],
    );
  }

  /// 검색 결과 목록
  Widget _results(PanenkaTokens tokens, List<Map<String, dynamic>> favorites) {
    final rows = _rows ?? const [];
    final sortIdx = _sorts.indexWhere((s) => s.$1 == _query.sort && s.$2 == _query.desc);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 8, 2),
          child: Row(
            children: [
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: '${rows.length}${_truncated ? '+' : ''}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                TextSpan(text: '장', style: TextStyle(fontSize: 12, color: tokens.mute)),
              ])),
              const Spacer(),
              _menu<int>(
                label: '${_query.grade}강 기준',
                items: [for (var g = 1; g <= 13; g++) (g, '$g강 기준')],
                onSelected: (g) {
                  final rerun = _query.ovrMin != null ||
                      _query.ovrMax != null ||
                      _query.priceMin != null ||
                      _query.priceMax != null ||
                      _query.sort == 'price';
                  setState(() => _query.grade = g);
                  // OVR·선수 가치 조건은 강화 기준에 따라 결과가 달라지므로 다시 찾는다
                  if (rerun) _runSearch();
                },
              ),
              _menu<int>(
                label: sortIdx >= 0 ? _sorts[sortIdx].$3 : _sorts[0].$3,
                items: [for (var i = 0; i < _sorts.length; i++) (i, _sorts[i].$3)],
                onSelected: (i) {
                  setState(() {
                    _query.sort = _sorts[i].$1;
                    _query.desc = _sorts[i].$2;
                  });
                  _runSearch();
                },
              ),
            ],
          ),
        ),
        Divider(height: 1, color: tokens.line),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error ?? '검색 결과가 없습니다.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: tokens.mute)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: rows.length + (_truncated ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= rows.length) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: Text('결과가 많아 앞부분만 표시했습니다. 조건을 더 좁혀 주세요.',
                            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: tokens.mute)),
                      );
                    }
                    return _row(rows[i], favorites);
                  },
                ),
        ),
      ],
    );
  }

  Widget _menu<T>({required String label, required List<(T, String)> items, required ValueChanged<T> onSelected}) {
    return PopupMenuButton<T>(
      tooltip: label,
      onSelected: onSelected,
      itemBuilder: (_) => [for (final it in items) PopupMenuItem<T>(value: it.$1, height: 40, child: Text(it.$2))],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const Icon(Icons.expand_more, size: 15),
          ],
        ),
      ),
    );
  }
}
