import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import '../providers/theme_provider.dart';
import 'pill_tabs.dart';

/// 랭킹/컷라인 탭 — 넥슨 홈페이지 직접 크롤링 (로그인 불필요)
/// dashboard_screen.dart에서 추출해 매크로 대시보드와 게스트 공개 홈이 공용 사용 (2026-08-17)
///
/// 2026-08-19 A안 리디자인 (사용자 승인 시안):
/// - 컷라인 2종 = 상단 벤토 타일: 컷 순위(구간 마지막 순위) 점수를 대표 큰 숫자로 강조,
///   직전 순위들은 보조 표기, 이전 시즌 컷은 구분선 아래
/// - 랭킹 목록 = 카드 리스트 (1~3위 금·은·동 원형 배지, 팀컬러 이름 부제)
/// - 컷 순위는 모드별 상이: 감독 20/200위, 1vs1 100/1,000위, 2vs2 100/500위
/// - 모드별 결과 캐시: 탭 전환 재호출 없음, 당겨서 새로고침 시에만 재조회
class RankingTab extends StatefulWidget {
  const RankingTab({Key? key}) : super(key: key);

  @override
  State<RankingTab> createState() => _RankingTabState();
}

class _RankingTabState extends State<RankingTab> with AutomaticKeepAliveClientMixin {
  String _mode = 'manager'; // 감독모드 기본 (사용자 지정) — 1vs1/2vs2 전환 가능

  // 모드별 결과 캐시 — 실패 시 이전 데이터 유지, 성공 시에만 교체 (로딩 정책 2026-08-19)
  final Map<String, Map<String, dynamic>> _modeCache = {};
  final Set<String> _loadingModes = {};

  static const _modeLabels = {
    'manager': '감독모드',
    '1vs1': '1vs1',
    '2vs2': '2vs2',
  };

  // 모드별 컷 순위 [슈챔컷, 주차컷] — 컷라인 = 구간 마지막 순위의 점수
  static const Map<String, List<int>> _cutRanks = {
    'manager': [20, 200],
    '1vs1': [100, 1000],
    '2vs2': [100, 500],
  };

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadRankingData();
  }

  bool get _isLoadingCurrent => _loadingModes.contains(_mode);

  // 1,000 단위 쉼표 표기 (넥슨 순위 텍스트는 쉼표 없이 옴 — 2026-08-19 실측)
  String _fmtNum(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // ===== 시즌별 순위 데이터 가져오기 (재시도 포함) =====
  Future<String?> _fetchSeasonRank(
    Map<String, String> season,
    String rtMode,
    Map<String, String> headers, {
    required String rank,
    int page = 1,
    int maxAttempts = 2,
  }) async {
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final pageParam = page > 1 ? '&n4pageno=$page' : '';
        final url = 'https://fconline.nexon.com/datacenter/rank_inner?rt=$rtMode&n4seasonno=${season['no']}$pageParam';

        final response = await http.get(Uri.parse(url), headers: headers).timeout(Duration(seconds: 10));

        if (response.statusCode == 200) {
          final doc = html_parser.parse(response.body);
          final rows = doc.querySelectorAll('.tbody .tr');

          // 원하는 순위 데이터 찾기 (쉼표 제거 후 비교)
          for (var row in rows) {
            final rankElem = row.querySelector('.rank_no');
            if (rankElem != null && rankElem.text.trim().replaceAll(',', '') == rank) {
              final scoreElem = row.querySelector('.rank_r_win_point');
              if (scoreElem != null) {
                final score = scoreElem.text.trim();
                if (score.isNotEmpty && score != '-') {
                  print('[시즌 데이터] ${season['name']} ${rank}위: $score');
                  return score; // 성공 시 즉시 반환 (대기 없음)
                }
              }
            }
          }
        }
      } catch (e) {
        print('[시즌 데이터 오류] ${season['name']} ${rank}위 시도 ${attempt + 1}: $e');
      }

      // 마지막 시도가 아니면 1초만 대기
      if (attempt < maxAttempts - 1) {
        await Future.delayed(Duration(seconds: 1));
      }
    }

    return null; // 실패
  }

  // ===== 랭킹 데이터 로드 (Nexon 웹 크롤링) =====
  Future<void> _loadRankingData({bool force = false}) async {
    final rtMode = _mode;
    if (!force && _modeCache.containsKey(rtMode)) return; // 캐시 유지 (당겨서 새로고침만 재조회)
    if (_loadingModes.contains(rtMode)) return;
    setState(() => _loadingModes.add(rtMode));

    try {
      final superCut = _cutRanks[rtMode]![0];
      final parkingCut = _cutRanks[rtMode]![1];
      // 넥슨 랭킹은 20행/페이지, 현재 시즌은 결번 없이 컷 순위가 해당 페이지 마지막 행
      final superPage = (superCut + 19) ~/ 20; // 감독 1p / 1vs1·2vs2 5p
      final parkingPage = (parkingCut + 19) ~/ 20; // 감독 10p / 1vs1 50p / 2vs2 25p

      final headers = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
      };

      String pageUrl(int page) =>
          'https://fconline.nexon.com/datacenter/rank_inner?rt=$rtMode${page > 1 ? '&n4pageno=$page' : ''}';

      // ===== 병렬 처리: TOP40(1·2p) + 주차컷 페이지 + (모드별) 슈챔컷 페이지 동시 요청 =====
      final futures = <Future<http.Response>>[
        http.get(Uri.parse(pageUrl(1)), headers: headers).timeout(Duration(seconds: 10)),
        http.get(Uri.parse(pageUrl(2)), headers: headers).timeout(Duration(seconds: 10)),
        http.get(Uri.parse(pageUrl(parkingPage)), headers: headers).timeout(Duration(seconds: 10)),
        if (superPage > 2) http.get(Uri.parse(pageUrl(superPage)), headers: headers).timeout(Duration(seconds: 10)),
      ];
      final responses = await Future.wait(futures);

      if (responses.any((r) => r.statusCode != 200)) {
        throw Exception('HTTP ${responses.map((r) => r.statusCode).join('/')}');
      }

      // 랭킹 파싱 함수
      List<Map<String, dynamic>> parseRankings(dom.Document doc) {
        List<Map<String, dynamic>> rankings = [];
        final rows = doc.querySelectorAll('.tbody .tr');

        for (var row in rows) {
          try {
            final rankElem = row.querySelector('.rank_no');
            if (rankElem == null || rankElem.text == '순위') continue;

            final rank = rankElem.text.trim();
            final score = row.querySelector('.rank_r_win_point')?.text.trim() ?? '-';
            final coach = row.querySelector('.rank_coach .name.profile_pointer')?.text.trim() ?? '-';
            final value = row.querySelector('.rank_coach .price')?.text.trim() ?? '-';

            // 팀컬러 이미지 URL
            final teamColorImgs = row.querySelectorAll('.team_color .ico_rank img');
            final teamColorUrls =
                teamColorImgs.map((img) => img.attributes['src'] ?? '').where((src) => src.isNotEmpty).toList();

            // 팀컬러 이름
            final teamColorTexts = row.querySelectorAll('.team_color .name .inner');
            final teamColorNames = teamColorTexts.map((text) => text.text.trim()).toList();

            rankings.add({
              'rank': rank,
              'score': score,
              'coach': coach,
              'value': value,
              'team_color_urls': teamColorUrls,
              'team_color_names': teamColorNames,
            });
          } catch (e) {
            print('[랭킹 파싱 오류] $e');
            continue;
          }
        }

        return rankings;
      }

      final page1Rows = parseRankings(html_parser.parse(responses[0].body));
      final page2Rows = parseRankings(html_parser.parse(responses[1].body));
      final parkingRows = parseRankings(html_parser.parse(responses[2].body));
      final superRows = superPage > 2
          ? parseRankings(html_parser.parse(responses[3].body))
          : (superPage == 1 ? page1Rows : page2Rows);

      int? rankOf(Map<String, dynamic> r) => int.tryParse((r['rank'] as String).replaceAll(',', ''));

      // 컷 구간 추출: 컷-4 ~ 컷 (5행), 하위 리스트: 컷-10 ~ 컷 (11행)
      List<Map<String, String>> cutSlice(List<Map<String, dynamic>> rows, int cut) {
        return rows
            .where((r) {
              final n = rankOf(r);
              return n != null && n >= cut - 4 && n <= cut;
            })
            .map((r) => {'rank': r['rank'] as String, 'score': r['score'] as String})
            .toList();
      }

      final superChampList = cutSlice(superRows, superCut);
      final parkingList = cutSlice(parkingRows, parkingCut);
      final bottomList = parkingRows.where((r) {
        final n = rankOf(r);
        return n != null && n >= parkingCut - 10 && n <= parkingCut;
      }).toList();

      // 날짜 정보 파싱
      final rankAdvice = html_parser.parse(responses[0].body).querySelector('.rank_advice');
      String dateInfo = '';
      if (rankAdvice != null) {
        final dateRegex = RegExp(r'※\s*(\d{4}-\d{2}-\d{2})\s*(\d{2}):\d{2}:\d{2}');
        final match = dateRegex.firstMatch(rankAdvice.text);
        if (match != null) {
          dateInfo = '※ ${match.group(1)} ${match.group(2)}시 기준';
        }
      }

      // ===== 이전 시즌 컷 히스토리 =====
      final seasonListUrl = 'https://fconline.nexon.com/datacenter/rank?rt=$rtMode';
      final seasonResponse = await http.get(Uri.parse(seasonListUrl), headers: headers).timeout(Duration(seconds: 10));

      List<Map<String, String>> superChampHistory = [];
      List<Map<String, String>> parkingHistory = [];

      if (seasonResponse.statusCode == 200) {
        final seasonDoc = html_parser.parse(seasonResponse.body);
        final seasonElements = seasonDoc.querySelectorAll('.club_list.selector_list li a[onclick^=ChangeSeason]');

        List<Map<String, String>> seasons = [];
        for (var aElem in seasonElements) {
          final seasonNameElem = aElem.querySelector('span');
          if (seasonNameElem == null) continue;

          final seasonNameText = seasonNameElem.text.trim();
          if (seasonNameText.contains('현재 시즌')) continue;

          final onclickAttr = aElem.attributes['onclick'] ?? '';
          final seasonNoMatch = RegExp(r'ChangeSeason\((\d+)\)').firstMatch(onclickAttr);
          if (seasonNoMatch != null) {
            final seasonNo = seasonNoMatch.group(1)!;
            final seasonName = seasonNameText.split(' (')[0];
            seasons.add({'no': seasonNo, 'name': seasonName});

            if (seasons.length >= 5) break;
          }
        }

        // 각 시즌의 컷 순위 점수 (시즌 병렬 + 슈챔/주차 병렬)
        final seasonFutures = seasons.map((season) async {
          Map<String, dynamic> result = {'season': season['name']};

          final results = await Future.wait([
            _fetchSeasonRank(season, rtMode, headers, rank: '$superCut', page: superPage, maxAttempts: 2),
            _fetchSeasonRank(season, rtMode, headers, rank: '$parkingCut', page: parkingPage, maxAttempts: 2),
          ]);

          result['superScore'] = results[0];
          result['parkingScore'] = results[1];
          return result;
        }).toList();

        final seasonResults = await Future.wait(seasonFutures);

        for (var result in seasonResults) {
          if (result['superScore'] != null) {
            superChampHistory.add({
              'name': result['season'] as String,
              'score': result['superScore'] as String,
            });
          }
          if (result['parkingScore'] != null) {
            parkingHistory.add({
              'name': result['season'] as String,
              'score': result['parkingScore'] as String,
            });
          }
        }
      }

      // 상단 상세 목록: 감독모드는 TOP 40(슈챔컷 20위가 그 안에 있음), 1vs1·2vs2는 슈챔컷 부근 81~100위 (2026-08-23 사용자 지시)
      // 1vs1·2vs2는 1~3위도 함께 보여준다 (2026-09-05 사용자 지시) — 1페이지 상위 3행 + 슈챔컷 부근
      final top3Rows = rtMode == 'manager'
          ? <Map<String, dynamic>>[]
          : page1Rows.where((r) {
              final n = rankOf(r);
              return n != null && n >= 1 && n <= 3;
            }).toList();
      final cutRows = rtMode == 'manager'
          ? <Map<String, dynamic>>[]
          : superRows.where((r) {
              final n = rankOf(r);
              return n != null && n >= superCut - 19 && n <= superCut;
            }).toList();
      final topRows = rtMode == 'manager' ? [...page1Rows, ...page2Rows] : [...top3Rows, ...cutRows];
      final cutTitle = cutRows.isEmpty ? '슈챔컷 부근' : '슈챔컷 부근 (${cutRows.first['rank']}-${cutRows.last['rank']}위)';
      final data = <String, dynamic>{
        'top40': topRows,
        'top_title': rtMode == 'manager'
            ? 'TOP 40'
            : (top3Rows.isEmpty ? cutTitle : 'TOP 3 · $cutTitle'),
'bottom': bottomList,
        'date_info': dateInfo,
        'cutlines': {
          'super_champ_cut': {
            'cut': superCut,
            'current': superChampList,
            'history': superChampHistory,
          },
          'parking_cut': {
            'cut': parkingCut,
            'current': parkingList,
            'history': parkingHistory,
          },
        },
      };

      if (!mounted) return;
      setState(() {
        _modeCache[rtMode] = data; // 성공 시에만 교체
        _loadingModes.remove(rtMode);
      });
    } catch (e) {
      print('[랭킹 로드 오류] $e');
      if (!mounted) return;
      setState(() => _loadingModes.remove(rtMode));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('랭킹 데이터 로드 실패: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final data = _modeCache[_mode];

    return RefreshIndicator(
      onRefresh: () => _loadRankingData(force: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 모드 선택 (감독모드 기본) — 알약 슬라이드 탭 (앱 공통 컨트롤)
            PillTabs(
              labels: _modeLabels.values.toList(),
              selectedIndex: _modeLabels.keys.toList().indexOf(_mode),
              onSelected: (i) {
                setState(() => _mode = _modeLabels.keys.toList()[i]);
                _loadRankingData(); // 캐시 있으면 즉시 표시, 없을 때만 조회
              },
            ),
            const SizedBox(height: 12),

            if (data == null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(48),
                  child: _isLoadingCurrent
                      ? const CircularProgressIndicator()
                      : Text('데이터를 불러오지 못했습니다.\n아래로 당겨 새로고침하세요.',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ),
              )
            else ...[
              // 날짜 정보
              if ((data['date_info'] as String).isNotEmpty) ...[
                Text(
                  data['date_info'] as String,
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 10),
              ],

              // ===== 컷라인 벤토 타일 2종 (컷 순위 점수 대표 강조) =====
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _cutTile('슈챔컷', data['cutlines']['super_champ_cut'] as Map<String, dynamic>),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _cutTile('주차컷', data['cutlines']['parking_cut'] as Map<String, dynamic>),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ===== TOP 40 카드 리스트 =====
              _rankListCard(
                  data['top_title'] as String? ?? 'TOP 40', (data['top40'] as List).cast<Map<String, dynamic>>()),
              const SizedBox(height: 16),

              // ===== 주차컷 부근 카드 리스트 =====
              _rankListCard(
                _bottomTitle(data),
                (data['bottom'] as List).cast<Map<String, dynamic>>(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _bottomTitle(Map<String, dynamic> data) {
    final bottom = (data['bottom'] as List).cast<Map<String, dynamic>>();
    if (bottom.isEmpty) return '주차컷 부근';
    return '주차컷 부근 (${bottom.first['rank']}-${bottom.last['rank']}위)';
  }

  // ===== 컷라인 벤토 타일 =====
  Widget _cutTile(String label, Map<String, dynamic> cut) {
    final theme = Theme.of(context);
    final tokens = PanenkaTokens.of(context);
    final accent = theme.colorScheme.primary;
    final bigColor = tokens.accentInk;
    final subColor = Colors.grey.shade500;
    final dividerColor = tokens.line;

    final cutRank = cut['cut'] as int;
    final current = (cut['current'] as List).cast<Map<String, String>>();
    final history = (cut['history'] as List).cast<Map<String, String>>();

    // 대표 숫자 = 컷 순위(구간 마지막 순위) 점수, 직전 순위들은 보조 표기
    String cutScore = '-';
    final prevRows = <Map<String, String>>[];
    for (final row in current) {
      final n = int.tryParse((row['rank'] ?? '').replaceAll(',', ''));
      if (n == cutRank) {
        cutScore = row['score'] ?? '-';
      } else {
        prevRows.add(row);
      }
    }
    // 보조 줄: "96위 2,640 · 97위 2,633" 식 2개씩 줄바꿈
    final prevParts = prevRows.map((r) {
      final n = int.tryParse((r['rank'] ?? '').replaceAll(',', ''));
      final rankText = n != null ? _fmtNum(n) : (r['rank'] ?? '');
      return '$rankText위 ${r['score']}';
    }).toList();
    final prevLines = <String>[];
    for (int i = 0; i < prevParts.length; i += 2) {
      prevLines.add(prevParts.sublist(i, (i + 2).clamp(0, prevParts.length)).join(' · '));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: accent)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('${_fmtNum(cutRank)}위 컷',
                    style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: bigColor)),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text.rich(
            TextSpan(
              text: cutScore,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: bigColor),
              children: [
                TextSpan(text: ' 점', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: subColor)),
              ],
            ),
          ),
          if (prevLines.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(prevLines.join('\n'), style: TextStyle(fontSize: 9, height: 1.5, color: subColor)),
          ],
          if (history.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              height: 1,
              color: dividerColor,
            ),
            Text('이전 시즌 ${_fmtNum(cutRank)}위',
                style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: subColor)),
            const SizedBox(height: 2),
            ...history.map((h) => Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Text('${h['name']} · ${h['score']}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, color: subColor)),
                )),
          ],
        ],
      ),
    );
  }

  // ===== 랭킹 카드 리스트 =====
  Widget _rankListCard(String title, List<Map<String, dynamic>> rankings) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = isDark ? PanenkaTokens.of(context).ink.withOpacity(0.85) : Colors.grey.shade700;

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 6),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: titleColor)),
          const SizedBox(height: 4),
          if (rankings.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text('데이터가 없습니다', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ),
            )
          else
            ...List.generate(rankings.length, (i) {
              return _rankRow(rankings[i], isLast: i == rankings.length - 1);
            }),
        ],
      ),
    );
  }

  Widget _rankRow(Map<String, dynamic> r, {required bool isLast}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tokens = PanenkaTokens.of(context);
    final subColor = Colors.grey.shade500;
    final dividerColor = tokens.line;

    final rankStr = (r['rank'] ?? '').toString();
    final rankNum = int.tryParse(rankStr.replaceAll(',', ''));
    final teamColorNames = (r['team_color_names'] as List?)?.cast<String>() ?? const <String>[];

    // 1~3위 금·은·동 원형 배지
    Gradient? badgeGradient;
    Color badgeTextColor;
    Color? badgeBg;
    switch (rankNum) {
      case 1:
        badgeGradient = const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF2C14E), Color(0xFFC9922A)]);
        badgeTextColor = const Color(0xFF3A2A05);
        break;
      case 2:
        badgeGradient = const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFC9CDD8), Color(0xFF9AA0AE)]);
        badgeTextColor = const Color(0xFF2A2E38);
        break;
      case 3:
        badgeGradient = const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFD89A6A), Color(0xFFA96F42)]);
        badgeTextColor = const Color(0xFF3A2412);
        break;
      default:
        badgeBg = isDark ? tokens.soft : Colors.grey.shade200;
        badgeTextColor = isDark ? tokens.mute : Colors.grey.shade600;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: dividerColor)),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: badgeGradient,
              color: badgeGradient == null ? badgeBg : null,
            ),
            child: Text(rankStr,
                style: TextStyle(
                    fontSize: rankStr.length > 3 ? 8 : 10.5, fontWeight: FontWeight.w800, color: badgeTextColor)),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((r['coach'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                if (teamColorNames.isNotEmpty)
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                tokens.accentInk,
                                Color.lerp(tokens.accentInk, Colors.black, 0.35)!
                              ]),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(teamColorNames.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 9.5, color: subColor)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text((r['score'] ?? '').toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              if ((r['value'] ?? '').toString().isNotEmpty && (r['value'] ?? '').toString() != '-')
                Text((r['value'] ?? '').toString(), style: TextStyle(fontSize: 9.5, color: subColor)),
            ],
          ),
        ],
      ),
    );
  }
}
