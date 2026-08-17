import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'pill_tabs.dart';

/// 랭킹/컷라인 탭 — 넥슨 홈페이지 직접 크롤링 (로그인 불필요)
/// dashboard_screen.dart에서 추출해 매크로 대시보드와 게스트 공개 홈이 공용 사용 (2026-08-17)
class RankingTab extends StatefulWidget {
  const RankingTab({Key? key}) : super(key: key);

  @override
  State<RankingTab> createState() => _RankingTabState();
}

class _RankingTabState extends State<RankingTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _top40Rankings = [];
  List<Map<String, dynamic>> _bottom11Rankings = [];
  Map<String, dynamic>? _cutlines;
  bool _rankingLoading = false;
  String _rankingDateInfo = '';
  String _mode = 'manager'; // 감독모드 기본 (사용자 지정) — 1vs1/2vs2 전환 가능

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
    _loadRankingData();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_rankingLoading && _top40Rankings.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return _buildRankingTab();
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
          
          // 원하는 순위 데이터 찾기
          for (var row in rows) {
            final rankElem = row.querySelector('.rank_no');
            if (rankElem != null && rankElem.text.trim() == rank) {
              final scoreElem = row.querySelector('.rank_r_win_point');
              if (scoreElem != null) {
                final score = scoreElem.text.trim();
                if (score.isNotEmpty && score != '-') {
                  print('[시즌 데이터] ${season['name']} ${rank}위: $score');
                  return score;  // 성공 시 즉시 반환 (대기 없음)
                }
              }
            }
          }
        }
      } catch (e) {
        print('[시즌 데이터 오류] ${season['name']} ${rank}위 시도 ${attempt + 1}: $e');
      }
      
      // 마지막 시도가 아니면 1초만 대기 (2초 → 1초)
      if (attempt < maxAttempts - 1) {
        await Future.delayed(Duration(seconds: 1));
      }
    }
    
    return null;  // 실패
  }

  // ===== 랭킹 데이터 로드 (Nexon 웹 크롤링) =====
  Future<void> _loadRankingData() async {
    setState(() {
      _rankingLoading = true;
    });

    try {
      // 선택된 모드 (기본 감독모드)
      final rtMode = _mode;
      
      final headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
      };

      // ===== 병렬 처리: 3개 요청을 동시에 실행 (3배 속도 향상) =====
      final url1 = 'https://fconline.nexon.com/datacenter/rank_inner?rt=$rtMode&n4pageno=1';
      final url2 = 'https://fconline.nexon.com/datacenter/rank_inner?rt=$rtMode&n4pageno=2';
      final url10 = 'https://fconline.nexon.com/datacenter/rank_inner?rt=$rtMode&n4pageno=10';

      // Future.wait로 동시 실행 - 가장 느린 요청 시간만큼만 대기
      final responses = await Future.wait([
        http.get(Uri.parse(url1), headers: headers).timeout(Duration(seconds: 10)),
        http.get(Uri.parse(url2), headers: headers).timeout(Duration(seconds: 10)),
        http.get(Uri.parse(url10), headers: headers).timeout(Duration(seconds: 10)),
      ]);

      final response1 = responses[0];
      final response2 = responses[1];
      final response10 = responses[2];

      if (response1.statusCode == 200 && response2.statusCode == 200 && response10.statusCode == 200) {
        final doc1 = html_parser.parse(response1.body);
        final doc2 = html_parser.parse(response2.body);
        final doc10 = html_parser.parse(response10.body);

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
              final teamColorUrls = teamColorImgs.map((img) => img.attributes['src'] ?? '').where((src) => src.isNotEmpty).toList();
              
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

        final top20 = parseRankings(doc1);
        final next20 = parseRankings(doc2);
        final allPage10 = parseRankings(doc10);
        
        // 190-200위는 페이지 10의 9-19 인덱스
        final bottom11 = allPage10.length > 9 ? allPage10.sublist(9) : allPage10;

        // 날짜 정보 파싱
        final rankAdvice = doc1.querySelector('.rank_advice');
        String dateInfo = '날짜 정보 없음';
        if (rankAdvice != null) {
          final dateRegex = RegExp(r'※\s*(\d{4}-\d{2}-\d{2})\s*(\d{2}):\d{2}:\d{2}');
          final match = dateRegex.firstMatch(rankAdvice.text);
          if (match != null) {
            dateInfo = '※ ${match.group(1)} ${match.group(2)}시';
          }
        }

        // ===== 컷라인 데이터 (슈챔컷: 16-20위, 주차컷: 196-200위 + 이전 시즌) =====
        Map<String, dynamic>? cutlines;
        
        // 슈챔컷: 16-20위
        List<Map<String, String>> superChampList = [];
        if (top20.length >= 20) {
          for (int i = 15; i < 20; i++) {
            superChampList.add({
              'rank': top20[i]['rank'],
              'score': top20[i]['score'],
            });
          }
        }
        
        // 주차컷: 196-200위
        List<Map<String, String>> parkingList = [];
        if (allPage10.length >= 20) {
          for (int i = 15; i < 20; i++) {  // 페이지 10의 16-20번째 = 196-200위
            parkingList.add({
              'rank': allPage10[i]['rank'],
              'score': allPage10[i]['score'],
            });
          }
        }

        // 이전 시즌 목록 가져오기
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
          
          // ===== 각 시즌의 20위, 200위 점수 가져오기 (병렬 처리로 10배 빠름) =====
          // 5개 시즌을 동시에 요청 (순차 50초 → 병렬 5초)
          final seasonFutures = seasons.map((season) async {
            Map<String, dynamic> result = {'season': season['name']};
            
            // 슈챔컷과 주차컷을 병렬로 동시 실행
            final results = await Future.wait([
              _fetchSeasonRank(season, rtMode, headers, rank: '20', maxAttempts: 2),
              _fetchSeasonRank(season, rtMode, headers, rank: '200', page: 10, maxAttempts: 2),
            ]);
            
            result['superScore'] = results[0];
            result['parkingScore'] = results[1];
            return result;
          }).toList();
          
          // 모든 시즌 데이터를 동시에 가져오기 (병렬 실행)
          final seasonResults = await Future.wait(seasonFutures);
          
          // 결과 정리
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
        
        cutlines = {
          'super_champ_cut': {
            'current': superChampList,
            'history': superChampHistory,
          },
          'parking_cut': {
            'current': parkingList,
            'history': parkingHistory,
          },
        };

        setState(() {
          _top40Rankings = [...top20, ...next20];
          _bottom11Rankings = bottom11;
          _cutlines = cutlines;
          _rankingDateInfo = dateInfo;
          _rankingLoading = false;
        });
      } else {
        throw Exception('HTTP ${response1.statusCode}/${response2.statusCode}/${response10.statusCode}');
      }
    } catch (e) {
      print('[랭킹 로드 오류] $e');
      setState(() {
        _rankingLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('랭킹 데이터 로드 실패: $e')),
      );
    }
  }

  // ===== 랭킹 탭 =====
  Widget _buildRankingTab() {
    return RefreshIndicator(
      onRefresh: _loadRankingData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 모드 선택 (감독모드 기본) — 알약 슬라이드 탭 (앱 공통 컨트롤)
            PillTabs(
              labels: _modeLabels.values.toList(),
              selectedIndex: _modeLabels.keys.toList().indexOf(_mode),
              onSelected: (i) {
                setState(() {
                  _mode = _modeLabels.keys.toList()[i];
                  _top40Rankings = [];
                  _bottom11Rankings = [];
                  _cutlines = null;
                });
                _loadRankingData();
              },
            ),
            const SizedBox(height: 12),
            // 날짜 정보
            if (_rankingDateInfo.isNotEmpty) ...[
              Text(
                _rankingDateInfo,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
            ],

            // ===== 슈챔컷 (16-20위) =====
            if (_cutlines != null && _cutlines!['super_champ_cut'] != null) ...[
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '슈챔컷 (16-20위)',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      
                      // 현재 시즌 16-20위 리스트
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey.shade900
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: const [
                                Expanded(flex: 1, child: Text('순위', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                Expanded(flex: 2, child: Text('점수', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              ],
                            ),
                            const Divider(height: 16),
                            ...(_cutlines!['super_champ_cut']['current'] as List).map((item) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Expanded(flex: 1, child: Text(item['rank'], style: const TextStyle(fontSize: 13))),
                                    Expanded(flex: 2, child: Text(item['score'], style: const TextStyle(fontSize: 13))),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                      
                      // 이전 시즌 데이터
                      if ((_cutlines!['super_champ_cut']['history'] as List).isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text('이전 시즌 20위 점수', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey)),
                        const SizedBox(height: 8),
                        ...(_cutlines!['super_champ_cut']['history'] as List).map((item) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(
                              '${item['name']} : ${item['score']}점',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          );
                        }).toList(),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ===== 주차컷 (196-200위) =====
            if (_cutlines != null && _cutlines!['parking_cut'] != null) ...[
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '주차컷 (196-200위)',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      
                      // 현재 시즌 196-200위 리스트
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey.shade900
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: const [
                                Expanded(flex: 1, child: Text('순위', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                Expanded(flex: 2, child: Text('점수', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              ],
                            ),
                            const Divider(height: 16),
                            ...(_cutlines!['parking_cut']['current'] as List).map((item) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Expanded(flex: 1, child: Text(item['rank'], style: const TextStyle(fontSize: 13))),
                                    Expanded(flex: 2, child: Text(item['score'], style: const TextStyle(fontSize: 13))),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                      
                      // 이전 시즌 데이터
                      if ((_cutlines!['parking_cut']['history'] as List).isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text('이전 시즌 200위 점수', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey)),
                        const SizedBox(height: 8),
                        ...(_cutlines!['parking_cut']['history'] as List).map((item) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Text(
                              '${item['name']} : ${item['score']}점',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          );
                        }).toList(),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 1-40위 랭킹
            const Text('1-40위', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildRankingTable(_top40Rankings),
            const SizedBox(height: 24),

            // 190-200위 랭킹
            const Text('190-200위', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildRankingTable(_bottom11Rankings),
          ],
        ),
      ),
    );
  }

  Widget _buildRankingTable(List<Map<String, dynamic>> rankings) {
    if (_rankingLoading) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(32.0),
        child: CircularProgressIndicator(),
      ));
    }

    if (rankings.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Text(
          '데이터가 없습니다',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      ));
    }

    return Table(
      border: TableBorder.all(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey.shade700
            : Colors.grey.shade300,
      ),
      columnWidths: const {
        0: FixedColumnWidth(50),
        1: FlexColumnWidth(2),
        2: FixedColumnWidth(80),
        3: FixedColumnWidth(100),
      },
      children: [
        // 헤더
        TableRow(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey.shade800
                : Colors.grey.shade200,
          ),
          children: const [
            Padding(
              padding: EdgeInsets.all(8),
              child: Text('순위', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            Padding(
              padding: EdgeInsets.all(8),
              child: Text('감독명', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            Padding(
              padding: EdgeInsets.all(8),
              child: Text('점수', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            Padding(
              padding: EdgeInsets.all(8),
              child: Text('구단가치', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        ),
        // 데이터 행
        ...rankings.map((ranking) {
          return TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  ranking['rank'] ?? '',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  ranking['coach'] ?? '',
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  ranking['score'] ?? '',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  ranking['value'] ?? '',
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        }).toList(),
      ],
    );
  }
}
