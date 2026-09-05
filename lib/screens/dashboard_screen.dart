import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_service.dart';
import '../widgets/panenka_logo.dart';
import '../widgets/pill_nav_bar.dart';
import 'match_detail_screen.dart';
import '../providers/theme_provider.dart';
import '../services/socket_service.dart';
import 'public_home_screen.dart';
import 'notifications_screen.dart';
import 'market_tab.dart';
import 'analysis_tab.dart';
import '../widgets/ranking_tab.dart';

// ── 상태탭 팔레트 (2026-09-04 색상 프리셋: 기능·표현 전부 유지, 색만 역할 색으로 연결) ──
// 승·일시정지 = 승리색 / 패·중지 = 패배색(테라코타) / 무 = 중립 회색
// 경기 중 배너·상대 점수 = 강조색 / 온라인 = 민트 점(고정) / 주계정 = 보조색 테두리 알약
// 시작·긍정 스낵바 = 강조색 채움
Color _wdlWin(BuildContext context) => PanenkaTokens.of(context).winInk;
Color _wdlDraw(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF8B87A0)
        : const Color(0xFF6E6884);
Color _wdlLose(BuildContext context) => PanenkaTokens.of(context).loseInk;
const Color _mintDot = Color(0xFF6EE7B7); // 온라인 표시 점 (프리셋 무관 고정)
Color _stopSolid(BuildContext context) => PanenkaTokens.of(context).lose; // 중지·취소 계열 채움
Color _ctaSolid(BuildContext context) => PanenkaTokens.of(context).accentInk; // 시작·긍정 계열 채움

class DashboardScreen extends StatefulWidget {
  final String username;
  final ApiService apiService;

  const DashboardScreen({
    Key? key,
    required this.username,
    required this.apiService,
  }) : super(key: key);

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final ApiService _apiService = ApiService();
  Timer? _timer;
  List<Map<String, dynamic>> _accounts = [];
  bool _isLoading = true;
  bool _isInputting = false;  // 사용자 입력 중 플래그
  int _statisticsLoadingCount = 0;  // 통계 로딩 카운터 (3개 API 동시 로딩)
  bool get _statisticsLoading => _statisticsLoadingCount > 0;
  late TabController _tabController;
  String _selectedAccount = '';
  
  // 통계 필터 상태
  String _fcPeriod = '1';
  String _rankPeriod = '4h';
  String _matchPeriod = '7';
  bool _showFCDatePicker = false;
  bool _showRankDatePicker = false;
  bool _showMatchDatePicker = false;
  DateTime? _fcStartDate, _fcEndDate;
  DateTime? _rankStartDate, _rankEndDate;
  DateTime? _matchStartDate, _matchEndDate;
  
  // 통계 데이터
  Map<String, dynamic>? _fcMiningData;
  Map<String, dynamic>? _rankScoreData;
  Map<String, dynamic>? _matchCountData;

  // 시간대별 승률 (2026-07-25, 웹 대시보드 카드 이식)
  Map<String, dynamic>? _hourlyWinrateData;
  int? _hwSelectedWindow;  // 히트맵에서 탭한 셀 (구간 인덱스)
  int? _hwSelectedHour;    // 히트맵에서 탭한 셀 (시간)
  
  // 전적 필터 상태
  String _matchMode = 'manager_mode';  // manager_mode, official_mode, classic_1on1
  String _matchResult = 'all';  // all, win, draw, lose, error
  String _matchHistoryPeriod = 'all';  // all, 6h, 12h, today, week, month, custom
  String _matchSeason = 'all';  // 시즌 필터: all / 넥슨 시즌 번호 문자열 / none(시즌 정보 없음) — 2026-09-05
  List<Map<String, dynamic>> _matchSeasons = [];  // 서버 응답 seasons (모드별 시즌 목록)
  DateTime? _matchHistoryStartDate, _matchHistoryEndDate;
  bool _showMatchHistoryDatePicker = false;
  String _opponentSearch = '';  // 상대팀 검색
  String _clubFilter = 'all';  // 클럽별조회
  
  // 전적 데이터 (페이지네이션)
  List<Map<String, dynamic>> _matchHistory = [];
  bool _matchHistoryLoading = false;
  Map<String, int> _matchStats = {};
  int _displayedMatchCount = 10;  // 처음에 10경기만 표시
  final int _matchesPerPage = 10;  // 한 번에 로드할 경기 수

  // 랭킹 탭 상태

  // 시즌 D-day
  int? _seasonDaysRemaining;

  // 탭별 최초 로드 여부 (탭 전환 시 중복 로드 방지)
  bool _statisticsLoaded = false;
  bool _matchHistoryLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedAccount = widget.username;
    _tabController = TabController(length: 6, vsync: this);
    
    // 탭 전환 리스너 추가
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return; // 탭 전환 애니메이션 중 중복 발화 방지
      setState(() {}); // AppBar 조건부 버튼 업데이트
      if (_tabController.index == 1 && _selectedAccount != null && _selectedAccount!.isNotEmpty) {
        // 통계 탭: 최초 1회만 로드 (이후 스와이프로 갱신)
        if (!_statisticsLoaded && !_statisticsLoading) {
          _statisticsLoaded = true;
          _loadFCStatistics();
          _loadRankScoreStatistics();
          _loadMatchCountStatistics();
          _loadHourlyWinrate();
        }
      } else if (_tabController.index == 2 && _selectedAccount != null && _selectedAccount!.isNotEmpty) {
        // 전적 탭: 최초 1회만 로드 (이후 스와이프로 갱신)
        if (!_matchHistoryLoaded) {
          _matchHistoryLoaded = true;
          _loadMatchHistory();
        }
      }
    });
    
    _loadStatus();
    _loadSeasonInfo();

    // WebSocket 연결 (알림 수신)
    _connectWebSocket();
    
    _timer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (!_isInputting) {  // 입력 중이 아닐 때만 새로고침
        _loadStatus();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _tabController.dispose();
    SocketService().disconnect();  // WebSocket 연결 해제
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      // 앱이 포그라운드로 돌아올 때 WebSocket 재연결
      print('App resumed - reconnecting WebSocket');
      _connectWebSocket();
    } else if (state == AppLifecycleState.paused) {
      // 앱이 백그라운드로 갈 때
      print('App paused - WebSocket may disconnect');
    }
  }

// API 호출 함수들
  Future<void> _loadSeasonInfo() async {
    try {
      final data = await _apiService.getSeasonInfo();
      if (data['success'] == true && data['days_remaining'] != null) {
        if (mounted) {
          setState(() {
            _seasonDaysRemaining = (data['days_remaining'] as num).toInt();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadFCStatistics() async {
    if (_selectedAccount == null || _selectedAccount!.isEmpty) return;

    setState(() {
      _statisticsLoadingCount++;
    });

    try {
      String? startDate;
      String? endDate;

      if (_fcPeriod == 'custom') {
        if (_fcStartDate != null && _fcEndDate != null) {
          startDate = '${_fcStartDate!.year}-${_fcStartDate!.month.toString().padLeft(2, "0")}-${_fcStartDate!.day.toString().padLeft(2, "0")}';
          endDate = '${_fcEndDate!.year}-${_fcEndDate!.month.toString().padLeft(2, "0")}-${_fcEndDate!.day.toString().padLeft(2, "0")}';
        }
      }

      final data = await _apiService.getFCMining(
        _selectedAccount!,
        _fcPeriod == 'custom' ? 'custom' : _fcPeriod,
        startDate: startDate,
        endDate: endDate,
      );

      setState(() {
        _fcMiningData = data;
        _statisticsLoadingCount--;
      });
    } catch (e) {
      setState(() {
        _statisticsLoadingCount--;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('FC 채굴량 로드 실패: $e')),
        );
      }
    }
  }

  Future<void> _loadRankScoreStatistics() async {
    if (_selectedAccount == null || _selectedAccount!.isEmpty) return;

    setState(() {
      _statisticsLoadingCount++;
    });

    try {
      String? startDate;
      String? endDate;

      if (_rankPeriod == 'custom') {
        if (_rankStartDate != null && _rankEndDate != null) {
          startDate = '${_rankStartDate!.year}-${_rankStartDate!.month.toString().padLeft(2, "0")}-${_rankStartDate!.day.toString().padLeft(2, "0")}';
          endDate = '${_rankEndDate!.year}-${_rankEndDate!.month.toString().padLeft(2, "0")}-${_rankEndDate!.day.toString().padLeft(2, "0")}';
        }
      }

      final data = await _apiService.getRankScore(
        _selectedAccount!,
        _rankPeriod == 'custom' ? 'custom' : _rankPeriod,
        startDate: startDate,
        endDate: endDate,
      );

      setState(() {
        _rankScoreData = data;
        _statisticsLoadingCount--;
      });
    } catch (e) {
      setState(() {
        _statisticsLoadingCount--;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('순위/점수 로드 실패: $e')),
        );
      }
    }
  }

  Future<void> _loadMatchCountStatistics() async {
    if (_selectedAccount == null || _selectedAccount!.isEmpty) return;

    setState(() {
      _statisticsLoadingCount++;
    });

    try {
      String? startDate;
      String? endDate;

      if (_matchPeriod == 'custom') {
        if (_matchStartDate != null && _matchEndDate != null) {
          startDate = '${_matchStartDate!.year}-${_matchStartDate!.month.toString().padLeft(2, "0")}-${_matchStartDate!.day.toString().padLeft(2, "0")}';
          endDate = '${_matchEndDate!.year}-${_matchEndDate!.month.toString().padLeft(2, "0")}-${_matchEndDate!.day.toString().padLeft(2, "0")}';
        }
      }

      final data = await _apiService.getMatchCount(
        _selectedAccount!,
        _matchPeriod == 'custom' ? 'custom' : _matchPeriod,
        'manager_mode',  // all -> manager_mode (웹과 동일)
        startDate: startDate,
        endDate: endDate,
      );

      setState(() {
        _matchCountData = data;
        _statisticsLoadingCount--;
      });
    } catch (e) {
      setState(() {
        _statisticsLoadingCount--;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('경기수 로드 실패: $e')),
        );
      }
    }
  }

  Future<void> _loadHourlyWinrate() async {
    if (_selectedAccount == null || _selectedAccount!.isEmpty) return;

    setState(() {
      _statisticsLoadingCount++;
    });

    try {
      final data = await _apiService.getHourlyWinrate(_selectedAccount!);
      setState(() {
        _hourlyWinrateData = data;
        _hwSelectedWindow = null;
        _hwSelectedHour = null;
        _statisticsLoadingCount--;
      });
    } catch (e) {
      setState(() {
        _statisticsLoadingCount--;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('시간대별 승률 로드 실패: $e')),
        );
      }
    }
  }

  Future<void> _loadMatchHistory() async {
    if (_selectedAccount == null || _selectedAccount!.isEmpty) return;
    
    setState(() {
      _matchHistoryLoading = true;
      _displayedMatchCount = 10;  // 리셋 시 10경기만 표시
    });

    try {
      String? startDate;
      String? endDate;
      final now = DateTime.now();
      
      // 기간별 날짜 계산 (웹 대시보드와 동일)
      if (_matchHistoryPeriod == '6h') {
        startDate = now.subtract(const Duration(hours: 6)).toIso8601String();
        endDate = now.toIso8601String();
      } else if (_matchHistoryPeriod == '12h') {
        startDate = now.subtract(const Duration(hours: 12)).toIso8601String();
        endDate = now.toIso8601String();
      } else if (_matchHistoryPeriod == 'today') {
        final today = DateTime(now.year, now.month, now.day);
        startDate = today.toIso8601String();
        endDate = now.toIso8601String();
      } else if (_matchHistoryPeriod == 'week') {
        startDate = now.subtract(const Duration(days: 7)).toIso8601String();
        endDate = now.toIso8601String();
      } else if (_matchHistoryPeriod == 'month') {
        startDate = now.subtract(const Duration(days: 30)).toIso8601String();
        endDate = now.toIso8601String();
      } else if (_matchHistoryPeriod == 'custom' && _matchHistoryStartDate != null && _matchHistoryEndDate != null) {
        startDate = '${_matchHistoryStartDate!.year}-${_matchHistoryStartDate!.month.toString().padLeft(2, "0")}-${_matchHistoryStartDate!.day.toString().padLeft(2, "0")}';
        endDate = '${_matchHistoryEndDate!.year}-${_matchHistoryEndDate!.month.toString().padLeft(2, "0")}-${_matchHistoryEndDate!.day.toString().padLeft(2, "0")}';
      }

      final data = await _apiService.getMatchHistory(
        username: _selectedAccount!,
        mode: _matchMode,
        result: _matchResult,
        period: _matchHistoryPeriod,
        startDate: startDate,
        endDate: endDate,
        season: _matchSeason,
      );

      setState(() {
        if (data['success'] == true) {
          _matchHistory = List<Map<String, dynamic>>.from(data['matches'] ?? []);
          _matchStats = Map<String, int>.from(data['statistics'] ?? {});
          _matchSeasons = List<Map<String, dynamic>>.from(data['seasons'] ?? []);
          // 선택 시즌이 목록에 없으면(모드 전환 등) 전체로 복귀
          if (_matchSeason != 'all' && !_matchSeasons.any((s) => _seasonKey(s['season_id']) == _matchSeason)) {
            _matchSeason = 'all';
          }
        } else {
          _matchHistory = [];
          _matchStats = {};
        }
        _matchHistoryLoading = false;
      });
    } catch (e) {
      setState(() {
        _matchHistory = [];
        _matchStats = {};
        _matchHistoryLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('전적 로드 실패: $e')),
        );
      }
    }
  }

  Widget _buildPeriodButton(String label, String value, String currentValue, Function(String) onPressed) {
    final isActive = currentValue == value;
    return OutlinedButton(
      onPressed: () => onPressed(value),
      style: OutlinedButton.styleFrom(
        backgroundColor: isActive ? Theme.of(context).primaryColor : null,
        foregroundColor: isActive ? Colors.white : Theme.of(context).primaryColor,
      ),
      child: Text(label),
    );
  }


  Future<void> _loadStatus() async {
    final result = await widget.apiService.getDashboardStatus();
    // 응답 대기 중 화면이 사라진 경우(로그아웃 직후 등) setState 금지 — iOS 오류 보고 'Null check operator' (09-05)
    if (!mounted) return;
    if (result['success']) {
      setState(() {
        _accounts = List<Map<String, dynamic>>.from(result['accounts'] ?? []);
        _isLoading = false;
      });
    } else {
      // 실패 시에도 로딩 상태 해제
      setState(() {
        _isLoading = false;
      });
      // 연결 오류는 조용히 처리 (60초 주기 자동 갱신 중 반복 노출 방지)
      // 인증 실패 등 서버 응답 오류만 사용자에게 표시
      final msg = result['message'];
      if (mounted && msg != null && msg != '서버 연결 오류') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('상태 로드 실패: $msg')),
        );
      }
    }
  }

  Future<void> _startMacro(String username, String mode,
      Map<String, dynamic>? parkingConditions,
      {String? leagueSub, bool? bgMode}) async {
    final result = await widget.apiService.startMacro(
      username,
      mode,
      parkingConditions: parkingConditions,
      leagueSub: leagueSub,
      bgMode: bgMode,
    );

    if (result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$username: 매크로 시작 명령 전송됨'), backgroundColor: _ctaSolid(context)),
      );
      await _loadStatus();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류: ${result['message']}'), backgroundColor: Colors.red),
      );
    }
  }

  // 원격 제어 공통 헬퍼 (2026-07-18 원격 제어 확장) — 명령 전송 + 결과 스낵바 + 상태 갱신
  Future<void> _sendControl(String username,
      Future<Map<String, dynamic>> request, String okMsg,
      {Color? color}) async {
    final result = await request;
    if (!mounted) return;
    color ??= _ctaSolid(context);
    if (result['success'] == true) {
      final msg = (result['message'] is String && (result['message'] as String).isNotEmpty)
          ? result['message'] as String
          : okMsg;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$username: $msg'), backgroundColor: color),
      );
      await _loadStatus();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류: ${result['message']}'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _stopMacro(String username) async {
    final result = await widget.apiService.stopMacro(username);
    if (result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$username: 매크로 중지 명령 전송됨'), backgroundColor: _stopSolid(context)),
      );
      await _loadStatus();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류: ${result['message']}'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 우측 요소(시즌 D-day 등)에 밀려 텍스트가 잘리던 문제 — 아이콘만 표시 (2026-08-16)
        title: const PanenkaLogo(size: 28),
        backgroundColor: PanenkaTokens.of(context).band, // 프리셋 띠색 (2026-09-04)
        foregroundColor: PanenkaTokens.of(context).bandInk, // 띠 위 아이콘은 라이트에서도 밝은색 (대비 보장)
        actions: [
          if (_seasonDaysRemaining != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _seasonDaysRemaining! <= 0
                      ? Colors.red[700]
                      : _seasonDaysRemaining! <= 3
                          ? Colors.red
                          : Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _seasonDaysRemaining! <= 0
                      ? '시즌종료'
                      : '시즌종료 D-$_seasonDaysRemaining',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: Icon(
              Provider.of<ThemeProvider>(context).isDarkMode 
                ? Icons.light_mode 
                : Icons.dark_mode
            ),
            onPressed: () {
              Provider.of<ThemeProvider>(context, listen: false).toggleTheme();
            },
            tooltip: '다크모드 전환',
          ),
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => NotificationsScreen(
                    username: widget.username,
                    apiService: widget.apiService,
                  ),
                ),
              );
            },
            tooltip: '알림',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await widget.apiService.logout();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const PublicHomeScreen()),
                (route) => false,
              );
            },
            tooltip: '로그아웃',
          ),
        ],
        // 상단 탭 — 하단 탭바와 완전히 동일한 위젯(PanenkaPillBar) 공유 (사용자 지정).
        // 탭 구성·기능은 기존 6탭 그대로, TabController와 양방향 동기.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) => PanenkaPillBar(
                height: 50,
                items: const [
                  PillBarItem(Icons.dashboard, '상태'),
                  PillBarItem(Icons.bar_chart, '통계'),
                  PillBarItem(Icons.list, '전적'),
                  PillBarItem(Icons.emoji_events, '랭킹'),
                  PillBarItem(Icons.storefront, '이적시장'),
                  PillBarItem(Icons.pie_chart, '전적분석'),
                ],
                selectedIndex: _tabController.index,
                onSelected: (i) => _tabController.animateTo(i),
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStatusTab(),
          _buildStatisticsTab(),
          _buildMatchHistoryTab(),
          const RankingTab(),  // 넥슨 직접 크롤링 — 공용 위젯 (게스트 홈과 공유)
          // 계정 전환 시 상태가 초기화되도록 계정명을 key로 사용
          MarketTab(key: ValueKey('market-$_selectedAccount'), username: _selectedAccount),
          AnalysisTab(key: ValueKey('analysis-$_selectedAccount'), username: _selectedAccount),
        ],
      ),
    );
  }

  Widget _buildStatusTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_accounts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('연동된 계정이 없습니다.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadStatus,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _accounts.length,
        itemBuilder: (context, index) {
          final account = _accounts[index];
          return _buildAccountCard(account);
        },
      ),
    );
  }

  Widget _buildAccountCard(Map<String, dynamic> account) {
    final username = account['username'] ?? '';
    final isPrimary = account['is_primary'] ?? false;
    final status = account['status'] ?? 'offline';
    final mode = account['mode'] ?? '';
    final tier = account['tier'] ?? '-';
    final score = account['score']?.toString() ?? '-';
    final rank = account['rank']?.toString() ?? '-';
    final recordRaw = account['record'] ?? '0-0-0';
    final fcTotal = account['fc_total']?.toString() ?? '0';
    final highestScore = account['highest_score']?.toString() ?? '0';
    final highestScoreTime = account['highest_score_time'] ?? '';
    final timeAgo = account['time_ago'] ?? '알 수 없음';
    
    final isOnline = status == 'online';
    final isRunning = isOnline && mode.isNotEmpty && mode != 'stopped' && mode != '정지';

    // 인게임 상태
    final ingameTime = account['ingame_time'] as String?;
    final ingameMyScore = account['ingame_my_score'];
    final ingameOppScore = account['ingame_opp_score'];
    final isMatching = ingameTime == '매칭대기중';
    final isPenaltyKick = ingameTime == '승부차기중';
    final isPlaying = ingameTime != null && !isMatching && !isPenaltyKick;

    // 상대방 정보 (combined 화면)
    final opponentManagerImg = account['opponent_manager_img'] as String?;
    final opponentScore = account['opponent_score'];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.person, color: PanenkaTokens.of(context).subInk, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      username,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    if (isPrimary) ...[
                      const SizedBox(width: 8),
                      // 주계정 뱃지: 보조색 토널 + 테두리 알약 (색상 프리셋)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: PanenkaTokens.of(context).subInk.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: PanenkaTokens.of(context).subInk.withOpacity(0.55)),
                        ),
                        child: Text(
                          '주 계정',
                          style: TextStyle(
                              color: PanenkaTokens.of(context).subInk,
                              fontSize: 10,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
                // 온라인 뱃지: 민트 점 + 중립 알약, 오프라인은 회색 점 파생 (A안)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withOpacity(0.06)
                        : Colors.black.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.circle,
                          size: 10,
                          color: isOnline ? _mintDot : Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        isOnline ? '온라인' : '오프라인',
                        style: TextStyle(
                            color: Theme.of(context).brightness ==
                                    Brightness.dark
                                ? Colors.white70
                                : Colors.grey.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 인게임 상태 배너 (경기 중 / 승부차기 중 / 매칭대기중)
            // 상대방 감독명·점수 (combined 화면 감지 시 표시)
            if (opponentManagerImg != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: const Border(
                    left: BorderSide(color: Color(0xFFADB5BD), width: 4),
                  ),
                ),
                child: Row(
                  children: [
                    // 상대 정보 강조: 프리셋 강조색 (2026-09-04)
                    Text(
                      'vs',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: PanenkaTokens.of(context).accentInk,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Builder(
                      builder: (_) {
                        try {
                          return Image.memory(
                            base64Decode(opponentManagerImg),
                            height: 18,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          );
                        } catch (_) {
                          return const SizedBox.shrink();
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${opponentScore ?? '-'}점',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: PanenkaTokens.of(context).accentInk,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (ingameTime != null) ...[
              // 인게임 배너 색 (색상 프리셋): 경기중=강조색+경기 중 띠 배경,
              // 승부차기=민트 토널(고정), 매칭대기=중립 회색 토널
              Builder(builder: (context) {
                final isDark =
                    Theme.of(context).brightness == Brightness.dark;
                final tokens = PanenkaTokens.of(context);
                final bannerColor = isPlaying
                    ? tokens.accentInk
                    : isPenaltyKick
                        ? (isDark
                            ? _mintDot
                            : const Color(0xFF0E9F6E))
                        : _wdlDraw(context);
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isPlaying
                        ? tokens.liveBg
                        : bannerColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border(
                      left: BorderSide(color: bannerColor, width: 4),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isPlaying
                                ? Icons.sports_soccer
                                : isPenaltyKick
                                    ? Icons.sports_score
                                    : Icons.hourglass_empty,
                            size: 16,
                            color: bannerColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isPlaying
                                ? '경기 중  $ingameTime'
                                : isPenaltyKick
                                    ? '승부차기 중'
                                    : '매칭대기중',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: bannerColor,
                            ),
                          ),
                        ],
                      ),
                      if (isPlaying)
                        Text(
                          '${ingameMyScore ?? '-'} : ${ingameOppScore ?? '-'}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            letterSpacing: 2,
                            color: bannerColor,
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ],
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                _buildInfoItem(Icons.gamepad, '모드', mode.isEmpty ? '-' : mode),
                _buildInfoItem(Icons.emoji_events, '티어', tier),
                _buildInfoItem(Icons.star, '점수', _formatNumber(score)),
                _buildInfoItem(Icons.leaderboard, '순위', _formatNumber(rank)),
                _buildInfoItem(Icons.monetization_on, 'FC', '$fcTotal FC'),
                _buildInfoItem(Icons.workspace_premium, '최고점수', _formatNumber(highestScore), subtitle: highestScoreTime.isNotEmpty ? highestScoreTime : null),
                if (account['protection_status'] != null && account['protection_status'].toString().isNotEmpty)
                  _buildInfoItem(
                    account['protection_status'] == '보호날' ? Icons.shield : Icons.warning,
                    '보호상태',
                    account['protection_status'],
                  ),
              ],
            ),
            // 전적 5칸 표기 (승/무/패 | 전체·무제외 승률) — 전체 폭
            const SizedBox(height: 8),
            _buildRecordColumns(recordRaw),
            // 최근 경기 승무패 도트 (20경기, 스와이프+기본버튼)
            Builder(builder: (context) {
              final rawResults = account['recent_results'] ?? [];
              final recentResults = (rawResults as List).map<String>((r) {
                if (r is String) return r;
                if (r is Map) return (r['result'] as String?) ?? '';
                return '';
              }).where((r) => r.isNotEmpty).toList();
              if (recentResults.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _RecentGamesDots(results: recentResults),
              );
            }),
            const Divider(height: 24),
            _buildControlSection(username, isOnline, isRunning, mode,
                account['control_state'] is Map<String, dynamic>
                    ? account['control_state'] as Map<String, dynamic>
                    : null),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '마지막 활동: $timeAgo',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value, {String? subtitle}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: PanenkaTokens.of(context).subInk),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
              Text(
                value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null && subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 9, color: Colors.grey[500]),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 전적 5칸 표기 — 승/무/패(고유색) + 전체 승률/무제외 승률 (recordRaw: "W-D-L")
  Widget _buildRecordColumns(String recordRaw) {
    int wins = 0, draws = 0, losses = 0;
    try {
      final parts = recordRaw.split('-');
      if (parts.length == 3) {
        wins = int.parse(parts[0]);
        draws = int.parse(parts[1]);
        losses = int.parse(parts[2]);
      }
    } catch (e) {
      // 파싱 실패 시 0-0-0으로 표기
    }
    final total = wins + draws + losses;
    final rateAll = total > 0 ? (wins / total * 100).toStringAsFixed(1) : '0.0';
    final woTotal = wins + losses;
    final rateWo = woTotal > 0 ? (wins / woTotal * 100).toStringAsFixed(1) : '0.0';

    // A안 색: 승=퍼플·무=퍼플그레이·패=로즈, 박스 배경은 테마 연동
    // (다크모드 밝은 회색 #F6F7F9 고정 해제 — 2026-08-19)
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final winColor = _wdlWin(context);
    final drawColor = _wdlDraw(context);
    final loseColor = _wdlLose(context);

    Widget countCol(String label, int value, Color color) => Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
          Text('$value', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );

    Widget rateCol(String label, String value) => Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey[isDark ? 500 : 600])),
          Text(value, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.grey[850])),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : const Color(0xFFF6F7F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          countCol('승', wins, winColor),
          countCol('무', draws, drawColor),
          countCol('패', losses, loseColor),
          Container(width: 1, height: 28,
              color: isDark ? Colors.white12 : const Color(0xFFDDE1E6)),
          rateCol('전체 승률', '$rateAll%'),
          rateCol('무제외 승률', '$rateWo%'),
        ],
      ),
    );
  }

  // _buildRecentGamesDots는 _RecentGamesDots StatefulWidget으로 대체됨

  // ── 예약 정지 (경기 수 / 시각 지정) — 2026-07-18 원격 제어 확장 ──
  Widget _buildReserveStopTile(String username, Map<String, dynamic> cs) {
    final reserve = cs['reserve_stop'] is Map ? cs['reserve_stop'] as Map : null;
    final reserveTime = cs['reserve_stop_time'] is Map ? cs['reserve_stop_time'] as Map : null;
    int? gamesValue;
    bool shutdown = false;
    TimeOfDay? pickedTime;
    bool timeShutdown = false;

    final parts = <String>[];
    if (reserve != null) {
      parts.add('${reserve['games']}경기 후${reserve['shutdown'] == true ? '+PC종료' : ''}');
    }
    if (reserveTime != null) parts.add('${reserveTime['time']} 정지');
    final summary = parts.isEmpty ? '예약 정지' : '예약 정지: ${parts.join(' · ')}';

    return StatefulBuilder(builder: (context, setState) {
      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(summary,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                  color: parts.isNotEmpty ? _wdlWin(context) : null)),
          children: [
            // 경기 수 예약 (N경기 후 정지 +PC종료 옵션)
            Row(children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                      labelText: '경기 수', border: OutlineInputBorder(), isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => gamesValue = int.tryParse(v),
                ),
              ),
              Checkbox(value: shutdown, onChanged: (v) => setState(() => shutdown = v!)),
              const Text('PC종료', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              ElevatedButton(
                onPressed: () {
                  if (gamesValue == null || gamesValue! < 1 || gamesValue! > 999) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: const Text('경기 수는 1~999 사이로 입력하세요.'),
                        backgroundColor: _stopSolid(context)));
                    return;
                  }
                  _sendControl(username,
                      widget.apiService.reserveStop(username, gamesValue!, shutdown),
                      '예약 정지 전송됨');
                },
                child: const Text('예약', style: TextStyle(fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 6),
            // 시각 지정 예약 (HH:MM에 정지 +PC종료 옵션)
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final t = await showTimePicker(
                        context: context, initialTime: TimeOfDay.now());
                    if (t != null) setState(() => pickedTime = t);
                  },
                  child: Text(
                      pickedTime == null
                          ? '정지 시각 선택'
                          : '${pickedTime!.hour.toString().padLeft(2, '0')}:${pickedTime!.minute.toString().padLeft(2, '0')} 에 정지',
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
              Checkbox(value: timeShutdown, onChanged: (v) => setState(() => timeShutdown = v!)),
              const Text('PC종료', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              ElevatedButton(
                onPressed: () {
                  if (pickedTime == null) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: const Text('정지 시각을 먼저 선택하세요.'),
                        backgroundColor: _stopSolid(context)));
                    return;
                  }
                  _sendControl(username,
                      widget.apiService.reserveStopTime(
                          username, pickedTime!.hour, pickedTime!.minute, timeShutdown),
                      '시간 예약 전송됨');
                },
                child: const Text('예약', style: TextStyle(fontSize: 12)),
              ),
            ]),
            if (reserve != null || reserveTime != null)
              Row(children: [
                if (reserve != null)
                  TextButton(
                      onPressed: () => _sendControl(username,
                          widget.apiService.cancelReserveStop(username),
                          '경기 수 예약 취소 전송됨', color: _stopSolid(context)),
                      child: Text('경기 수 예약 취소',
                          style: TextStyle(
                              fontSize: 12, color: _wdlLose(context)))),
                if (reserveTime != null)
                  TextButton(
                      onPressed: () => _sendControl(username,
                          widget.apiService.cancelReserveStopTime(username),
                          '시간 예약 취소 전송됨', color: _stopSolid(context)),
                      child: Text('시간 예약 취소',
                          style: TextStyle(
                              fontSize: 12, color: _wdlLose(context)))),
              ]),
          ],
        ),
      );
    });
  }

  // ── PC 설정 원격 토글 (자동재시작·전술류) — 2026-07-18 원격 제어 확장 ──
  // 스위치는 화면의 임시 상태만 바꾸고, [적용]을 눌러야 변경분을 묶어 전송
  // (실수 방지 + 명령 1~2건으로 일괄 처리. 되돌리기로 PC 현재값 복원)
  Widget _buildRemoteTogglesTile(String username, Map<String, dynamic> cs, bool isRunning) {
    final toggles = cs['toggles'] is Map
        ? Map<String, dynamic>.from(cs['toggles'] as Map)
        : <String, dynamic>{};
    final current = <String, bool>{
      'auto_restart': cs['auto_restart'] == true,
      'rage_mode': toggles['rage_mode'] == true,
      'offside_trap': toggles['offside_trap'] == true,
      'team_press': toggles['team_press'] == true,
      'relegation_defense': toggles['relegation_defense'] == true,
      'club_donation': toggles['club_donation'] == true,
    };
    const labels = {
      'auto_restart': '자동재시작',
      'rage_mode': '격앙모드',
      'offside_trap': '옵사트랩',
      'team_press': '팀압박',
      'relegation_defense': '강등방어',
      'club_donation': '클럽기부',
    };
    final draft = Map<String, bool>.from(current);

    return StatefulBuilder(builder: (context, setState) {
      final dirtyKeys =
          draft.keys.where((k) => draft[k] != current[k]).toList();

      Widget row(String key) {
        final dirty = draft[key] != current[key];
        return SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('${labels[key]}${dirty ? ' *' : ''}',
              style: TextStyle(fontSize: 13,
                  fontWeight: dirty ? FontWeight.bold : FontWeight.normal,
                  color: dirty ? _wdlWin(context) : null)),
          value: draft[key]!,
          onChanged: (v) {
            setState(() {
              draft[key] = v;
              _isInputting = true; // 임시 상태가 자동 새로고침에 지워지지 않게
            });
            Future.delayed(const Duration(seconds: 5), () {
              if (mounted) setState(() => _isInputting = false);
            });
          },
        );
      }

      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          initiallyExpanded: dirtyKeys.isNotEmpty,
          title: Text(
              'PC 설정 제어${isRunning ? ' (전술류는 다음 시작부터 적용)' : ''}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          children: [
            for (final key in labels.keys) row(key),
            if (dirtyKeys.isNotEmpty)
              Row(
                children: [
                  Expanded(
                    child: Text('적용 안 된 변경 ${dirtyKeys.length}건',
                        style: TextStyle(fontSize: 12, color: _wdlWin(context),
                            fontWeight: FontWeight.bold)),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      draft
                        ..clear()
                        ..addAll(current);
                    }),
                    child: const Text('되돌리기', style: TextStyle(fontSize: 12)),
                  ),
                  ElevatedButton(
                    onPressed: () => _applyToggleDraft(username, current, draft),
                    child: const Text('적용', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
          ],
        ),
      );
    });
  }

  // 토글 임시 상태 적용: 변경분만 묶어 전송 (전술류 1건 + 자동재시작 변경 시 1건)
  Future<void> _applyToggleDraft(String username,
      Map<String, bool> current, Map<String, bool> draft) async {
    final toggleChanges = <String, bool>{};
    bool? autoRestartChange;
    draft.forEach((k, v) {
      if (v == current[k]) return;
      if (k == 'auto_restart') {
        autoRestartChange = v;
      } else {
        toggleChanges[k] = v;
      }
    });
    final total = toggleChanges.length + (autoRestartChange != null ? 1 : 0);
    if (total == 0) return;

    bool ok = true;
    String errMsg = '';
    if (toggleChanges.isNotEmpty) {
      final r = await widget.apiService.setToggles(username, toggleChanges);
      if (r['success'] != true) {
        ok = false;
        errMsg = '${r['message']}';
      }
    }
    if (ok && autoRestartChange != null) {
      final r = await widget.apiService.setAutoRestart(username, autoRestartChange!);
      if (r['success'] != true) {
        ok = false;
        errMsg = '${r['message']}';
      }
    }
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$username: 설정 변경 $total건 전송됨'),
            backgroundColor: _ctaSolid(context)),
      );
      await _loadStatus();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류: $errMsg'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildControlSection(String username, bool isOnline, bool isRunning,
      String currentMode, Map<String, dynamic>? controlState) {
    String selectedMode = 'coach';
    bool showParkingConditions = false;
    String leagueSub = 'manager';   // 리그모드 서브모드 (감독전/AI전)
    String runModeChoice = 'keep';  // 실행 방식: keep=PC 설정 유지 / normal / bg

    // 주차모드 조건 상태
    bool tierEnabled = false;
    String selectedTier = '슈퍼챔피언스감독';
    bool rankEnabled = false;
    int? rankValue;
    String rankCondition = '이하';
    bool scoreEnabled = false;
    int? scoreValue;
    String scoreCondition = '이상';

    // 원격 제어 확장 지원 여부 (구버전 클라이언트는 control_state 미전송 → 기존 UI만)
    final supports = (controlState?['supports'] is List)
        ? List<String>.from(controlState!['supports'] as List)
        : <String>[];
    final isPaused = controlState?['paused'] == true;

    return StatefulBuilder(
      builder: (context, setState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isRunning) ...[
              if (supports.contains('pause')) ...[
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _sendControl(
                          username,
                          isPaused
                              ? widget.apiService.resumeMacro(username)
                              : widget.apiService.pauseMacro(username),
                          isPaused ? '재개 명령 전송됨' : '일시정지 명령 전송됨',
                        ),
                        icon: Icon(isPaused ? Icons.play_arrow : Icons.pause),
                        label: Text(isPaused ? '재개' : '일시정지'),
                        // 일시정지: 퍼플 토널 (A안)
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _wdlWin(context).withOpacity(0.16),
                          foregroundColor: _wdlWin(context),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _stopMacro(username),
                        icon: const Icon(Icons.stop),
                        label: const Text('중지'),
                        // 중지: 로즈 토널 (A안)
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _wdlLose(context).withOpacity(0.16),
                          foregroundColor: _wdlLose(context),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _stopMacro(username),
                    icon: const Icon(Icons.stop),
                    label: const Text('중지'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _wdlLose(context).withOpacity(0.16),
                      foregroundColor: _wdlLose(context),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
              if (isPaused)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Icon(Icons.pause_circle,
                          size: 14, color: _wdlWin(context)),
                      const SizedBox(width: 4),
                      Text('일시정지 중',
                          style: TextStyle(fontSize: 12, color: _wdlWin(context),
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              if (supports.contains('reserve_stop'))
                _buildReserveStopTile(username, controlState!),
            ],
            if (isOnline && supports.contains('set_toggles'))
              _buildRemoteTogglesTile(username, controlState!, isRunning),
            if (!isRunning && isOnline) ...[
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: selectedMode,
                      decoration: const InputDecoration(
                        labelText: '모드',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'coach', child: Text(' 감독모드')),
                        DropdownMenuItem(value: 'league', child: Text(' 리그모드')),
                        DropdownMenuItem(value: 'parking', child: Text(' 주차모드')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _isInputting = true;  // 입력 시작
                          selectedMode = value!;
                          showParkingConditions = (value == 'parking');
                        });
                        // 5초 후 플래그 해제
                        Future.delayed(const Duration(seconds: 5), () {
                          if (mounted) {
                            setState(() {
                              _isInputting = false;
                            });
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Map<String, dynamic>? parkingConditions;
                        
                        if (selectedMode == 'parking') {
                          parkingConditions = {};
                          if (tierEnabled) {
                            parkingConditions['tier'] = selectedTier;
                          }
                          if (rankEnabled && rankValue != null) {
                            parkingConditions['rank'] = {
                              'value': rankValue,
                              'condition': rankCondition,
                            };
                          }
                          if (scoreEnabled && scoreValue != null) {
                            parkingConditions['score'] = {
                              'value': scoreValue,
                              'condition': scoreCondition,
                            };
                          }
                          
                          if (parkingConditions.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('주차모드 조건을 최소 1개 이상 선택해주세요.'),
                                backgroundColor: _stopSolid(context),
                              ),
                            );
                            return;
                          }
                        }
                        
                        _startMacro(username, selectedMode, parkingConditions,
                            leagueSub: selectedMode == 'league' ? leagueSub : null,
                            bgMode: runModeChoice == 'keep' ? null : runModeChoice == 'bg');
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('시작'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: PanenkaTokens.of(context).accentInk,
                        foregroundColor: PanenkaTokens.of(context).onAccentInk,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 서브모드(리그) + 실행 방식 — 신버전 클라(control_state 있음)에서만 표시
              if (supports.contains('league_sub') || supports.contains('bg_mode'))
                Row(
                  children: [
                    if (selectedMode == 'league' && supports.contains('league_sub')) ...[
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: leagueSub,
                          decoration: const InputDecoration(
                            labelText: '서브모드',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'manager', child: Text(' 감독전', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'ai', child: Text(' AI전', style: TextStyle(fontSize: 13))),
                          ],
                          onChanged: (value) => setState(() => leagueSub = value!),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (supports.contains('bg_mode'))
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: runModeChoice,
                          decoration: const InputDecoration(
                            labelText: '실행 방식',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'keep', child: Text(' PC 설정 유지', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'normal', child: Text(' 일반 모드', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'bg', child: Text(' 백그라운드', style: TextStyle(fontSize: 13))),
                          ],
                          onChanged: (value) => setState(() => runModeChoice = value!),
                        ),
                      ),
                  ],
                ),
              if (supports.contains('league_sub') || supports.contains('bg_mode'))
                const SizedBox(height: 8),

              // 주차모드 조건 입력
              if (showParkingConditions) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[850]
                        : PanenkaTokens.of(context).accentSoft,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[700]!
                          : PanenkaTokens.of(context).accentInk.withOpacity(0.45),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        ' 주차모드 조건',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      
                      // 티어 조건
                      Row(
                        children: [
                          Checkbox(
                            value: tierEnabled,
                            onChanged: (value) {
                              setState(() {
                                tierEnabled = value!;
                              });
                            },
                          ),
                          const Text('티어:', style: TextStyle(fontSize: 13)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: selectedTier,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                isDense: true,
                              ),
                              style: TextStyle(
                                fontSize: 12, 
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                              ),
                              items: const [
                                DropdownMenuItem(value: '슈퍼챔피언스감독', child: Text('슈퍼챔피언스감독', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: '챔피언스감독', child: Text('챔피언스감독', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: '슈퍼챌린저감독', child: Text('슈퍼챌린저감독', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: '챌린저1부감독', child: Text('챌린저1부감독', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: '챌린저2부감독', child: Text('챌린저2부감독', style: TextStyle(fontSize: 12))),
                                DropdownMenuItem(value: '챌린저3부감독', child: Text('챌린저3부감독', style: TextStyle(fontSize: 12))),
                              ],
                              onChanged: tierEnabled ? (value) {
                                setState(() {
                                  selectedTier = value!;
                                });
                              } : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      
                      // 순위 조건
                      Row(
                        children: [
                          Checkbox(
                            value: rankEnabled,
                            onChanged: (value) {
                              setState(() {
                                rankEnabled = value!;
                              });
                            },
                          ),
                          const Text('순위:', style: TextStyle(fontSize: 13)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: '순위',
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                isDense: true,
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                              ),
                              keyboardType: TextInputType.number,
                              enabled: rankEnabled,
                              onChanged: (value) {
                                setState(() {
                                  _isInputting = true;
                                });
                                rankValue = int.tryParse(value);
                                Future.delayed(const Duration(seconds: 5), () {
                                  if (mounted) {
                                    setState(() {
                                      _isInputting = false;
                                    });
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          DropdownButton<String>(
                            value: rankCondition,
                            items: const [
                              DropdownMenuItem(value: '이하', child: Text('이하', style: TextStyle(fontSize: 12))),
                              DropdownMenuItem(value: '이상', child: Text('이상', style: TextStyle(fontSize: 12))),
                            ],
                            onChanged: rankEnabled ? (value) {
                              setState(() {
                                rankCondition = value!;
                              });
                            } : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      
                      // 점수 조건
                      Row(
                        children: [
                          Checkbox(
                            value: scoreEnabled,
                            onChanged: (value) {
                              setState(() {
                                scoreEnabled = value!;
                              });
                            },
                          ),
                          const Text('점수:', style: TextStyle(fontSize: 13)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                hintText: '점수',
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                isDense: true,
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white
                                    : Colors.black,
                              ),
                              keyboardType: TextInputType.number,
                              enabled: scoreEnabled,
                              onChanged: (value) {
                                setState(() {
                                  _isInputting = true;
                                });
                                scoreValue = int.tryParse(value);
                                Future.delayed(const Duration(seconds: 5), () {
                                  if (mounted) {
                                    setState(() {
                                      _isInputting = false;
                                    });
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          DropdownButton<String>(
                            value: scoreCondition,
                            items: const [
                              DropdownMenuItem(value: '이상', child: Text('이상', style: TextStyle(fontSize: 12))),
                              DropdownMenuItem(value: '이하', child: Text('이하', style: TextStyle(fontSize: 12))),
                            ],
                            onChanged: scoreEnabled ? (value) {
                              setState(() {
                                scoreCondition = value!;
                              });
                            } : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              
              // 클럽 기부 시작용 체크박스 제거 (2026-07-18) — 'PC 설정 제어' 토글로 일원화.
              // 시작 명령에 club_donation을 보내지 않으면 1.8.1+ 클라가 PC 설정을 유지함
            ],
            if (!isOnline) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: Colors.grey),
                    SizedBox(width: 8),
                    Text('오프라인 상태에서는 제어할 수 없습니다.', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  // 통계·전적 탭 공용 계정 선택기 (본계정+연동계정 — 연동계정 없으면 숨김)
  Widget _buildAccountDropdown() {
    final usernames = _accounts.map((a) => a['username'].toString()).toSet().toList();
    if (_selectedAccount.isNotEmpty && !usernames.contains(_selectedAccount)) {
      usernames.insert(0, _selectedAccount);
    }
    if (usernames.length <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Icon(Icons.person, size: 16),
          const SizedBox(width: 6),
          const Text('계정', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButton<String>(
              value: _selectedAccount,
              isDense: true,
              isExpanded: true,
              style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodyMedium?.color),
              items: usernames
                  .map((u) => DropdownMenuItem(
                        value: u,
                        child: Text(u == widget.username ? u : '$u (연동계정)'),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v == null || v == _selectedAccount) return;
                setState(() => _selectedAccount = v);
                // 통계·전적 모두 선택 계정으로 재조회
                _loadFCStatistics();
                _loadRankScoreStatistics();
                _loadMatchCountStatistics();
                _loadHourlyWinrate();
                _loadMatchHistory();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsTab() {
    if (_statisticsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () async {
        _loadFCStatistics();
        _loadRankScoreStatistics();
        _loadMatchCountStatistics();
        _loadHourlyWinrate();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAccountDropdown(),
            // FC 채굴량 차트
            _buildFCMiningChart(),
            const SizedBox(height: 24),

            // 순위/점수 차트
            _buildRankScoreChart(),
            const SizedBox(height: 24),

            // 경기수 차트
            _buildMatchCountChart(),
            const SizedBox(height: 24),

            // 시간대별 승률 히트맵
            _buildHourlyWinrateCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildFCMiningChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('FC 채굴량', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            
            // 필터 버튼
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildPeriodButton('1일', '1', _fcPeriod, (value) {
                  setState(() {
                    _fcPeriod = value;
                    _showFCDatePicker = false;
                  });
                  _loadFCStatistics();
                }),
                _buildPeriodButton('7일', '7', _fcPeriod, (value) {
                  setState(() {
                    _fcPeriod = value;
                    _showFCDatePicker = false;
                  });
                  _loadFCStatistics();
                }),
                _buildPeriodButton('30일', '30', _fcPeriod, (value) {
                  setState(() {
                    _fcPeriod = value;
                    _showFCDatePicker = false;
                  });
                  _loadFCStatistics();
                }),
                _buildPeriodButton('기간 선택', 'custom', _fcPeriod, (value) {
                  setState(() {
                    _fcPeriod = value;
                    _showFCDatePicker = true;
                  });
                }),
              ],
            ),
            
            if (_showFCDatePicker) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _fcStartDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setState(() {
                            _fcStartDate = date;
                          });
                        }
                      },
                      child: Text(_fcStartDate != null 
                        ? '${_fcStartDate!.year}-${_fcStartDate!.month.toString().padLeft(2, "0")}-${_fcStartDate!.day.toString().padLeft(2, "0")}'
                        : '시작일'),
                    ),
                  ),
                  const Text('~'),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _fcEndDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setState(() {
                            _fcEndDate = date;
                          });
                        }
                      },
                      child: Text(_fcEndDate != null 
                        ? '${_fcEndDate!.year}-${_fcEndDate!.month.toString().padLeft(2, "0")}-${_fcEndDate!.day.toString().padLeft(2, "0")}'
                        : '종료일'),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: (_fcStartDate != null && _fcEndDate != null) ? () {
                      _loadFCStatistics();
                    } : null,
                    child: const Text('적용'),
                  ),
                ],
              ),
            ],
            
            
            // 차트
            if (_fcMiningData != null && _fcMiningData!['daily_data'] != null && (_fcMiningData!['daily_data'] as List).isNotEmpty) ...[
              Container(
                height: 350,
                padding: const EdgeInsets.only(right: 16, top: 50, bottom: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: (_fcMiningData!['daily_data'] as List).length * 70.0 > 300 
                      ? (_fcMiningData!['daily_data'] as List).length * 70.0 
                      : 300,
                    child: Stack(
                      children: [
                        LineChart(
                          LineChartData(
                            gridData: FlGridData(show: true),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 50,
                                  interval: null,
                                  getTitlesWidget: (value, meta) {
                                    // maxY는 눈금선 없는데 레이블 표시되어 잘림 - 제외
                                    if (value == meta.max) {
                                      return const SizedBox.shrink();
                                    }
                                    return Text(
                                      value.toInt().toString(),
                                      style: const TextStyle(fontSize: 9),
                                    );
                                  },
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 32,
                                  interval: 1,
                                  getTitlesWidget: (value, meta) {
                                    final data = _fcMiningData!['daily_data'] as List;
                                    final index = value.toInt();
                                    if (index >= 0 && index < data.length) {
                                      String date = data[index]['date'] ?? '';
                                      if (date.length >= 10) {
                                        date = date.substring(5);
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 8.0),
                                        child: Text(
                                          date, 
                                          style: const TextStyle(fontSize: 9),
                                        ),
                                      );
                                    }
                                    return const Text('');
                                  },
                                ),
                              ),
                              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            borderData: FlBorderData(show: true),
                            lineBarsData: [
                              LineChartBarData(
                                spots: (_fcMiningData!['daily_data'] as List).asMap().entries.map((entry) {
                                  return FlSpot(
                                    entry.key.toDouble(), 
                                    (entry.value['total_fc'] ?? 0).toDouble()
                                  );
                                }).toList(),
                                isCurved: true,
                                color: Theme.of(context).primaryColor,
                                barWidth: 2,
                                dotData: FlDotData(
                                  show: true,
                                  getDotPainter: (spot, percent, barData, index) {
                                    return FlDotCirclePainter(
                                      radius: 4,
                                      color: Theme.of(context).primaryColor,
                                      strokeWidth: 1,
                                      strokeColor: Colors.white,
                                    );
                                  },
                                ),
                                belowBarData: BarAreaData(show: false),
                              ),
                            ],
                            lineTouchData: LineTouchData(
                              enabled: true,
                              touchTooltipData: LineTouchTooltipData(
                                getTooltipItems: (touchedSpots) {
                                  return touchedSpots.map((spot) {
                                    return LineTooltipItem(
                                      spot.y.toInt().toString(),
                                      const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    );
                                  }).toList();
                                },
                              ),
                            ),
                            minY: 0,
                            maxY: (() {
                              final maxValue = (_fcMiningData!['daily_data'] as List)
                                  .map((e) => (e['total_fc'] ?? 0) as num)
                                  .reduce((a, b) => a > b ? a : b)
                                  .toDouble();
                              return maxValue * 1.3;
                            })(),
                          ),
                        ),
                        // 각 점 위에 수치 표시
                        ...(_fcMiningData!['daily_data'] as List).asMap().entries.map((entry) {
                          final value = entry.value['total_fc'] ?? 0;
                          final maxValue = (_fcMiningData!['daily_data'] as List)
                              .map((e) => (e['total_fc'] ?? 0) as num)
                              .reduce((a, b) => a > b ? a : b)
                              .toDouble();
                          final chartHeight = 260.0;
                          final yRatio = value / (maxValue * 1.3);
                          final yPos = 50 + (chartHeight * (1 - yRatio));
                          final dataCount = (_fcMiningData!['daily_data'] as List).length;
                          final chartWidth = dataCount * 70.0 > 300 ? dataCount * 70.0 : 300.0;
                          final pointSpacing = (chartWidth - 50 - 16) / (dataCount > 1 ? dataCount - 1 : 1);
                          final xPos = 50 + (entry.key * pointSpacing);
                          
                          return Positioned(
                            left: xPos - 15,
                            top: yPos - 25,
                            child: Text(
                              value.toString(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ),
              ),
            ] else
              const Center(child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('데이터가 없습니다'),
              )),
          ],
        ),
      ),
    );
  }

  Widget _buildRankScoreChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('순위/점수', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            
            // 필터 버튼
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildPeriodButton('4시간', '4h', _rankPeriod, (value) {
                  setState(() {
                    _rankPeriod = value;
                    _showRankDatePicker = false;
                  });
                  _loadRankScoreStatistics();
                }),
                _buildPeriodButton('8시간', '8h', _rankPeriod, (value) {
                  setState(() {
                    _rankPeriod = value;
                    _showRankDatePicker = false;
                  });
                  _loadRankScoreStatistics();
                }),
                _buildPeriodButton('12시간', '12h', _rankPeriod, (value) {
                  setState(() {
                    _rankPeriod = value;
                    _showRankDatePicker = false;
                  });
                  _loadRankScoreStatistics();
                }),
                _buildPeriodButton('24시간', '24h', _rankPeriod, (value) {
                  setState(() {
                    _rankPeriod = value;
                    _showRankDatePicker = false;
                  });
                  _loadRankScoreStatistics();
                }),
                _buildPeriodButton('기간 선택', 'custom', _rankPeriod, (value) {
                  setState(() {
                    _rankPeriod = value;
                    _showRankDatePicker = true;
                  });
                }),
              ],
            ),
            
            if (_showRankDatePicker) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _rankStartDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setState(() {
                            _rankStartDate = date;
                          });
                        }
                      },
                      child: Text(_rankStartDate != null 
                        ? '${_rankStartDate!.year}-${_rankStartDate!.month.toString().padLeft(2, "0")}-${_rankStartDate!.day.toString().padLeft(2, "0")}'
                        : '시작일'),
                    ),
                  ),
                  const Text('~'),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _rankEndDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setState(() {
                            _rankEndDate = date;
                          });
                        }
                      },
                      child: Text(_rankEndDate != null 
                        ? '${_rankEndDate!.year}-${_rankEndDate!.month.toString().padLeft(2, "0")}-${_rankEndDate!.day.toString().padLeft(2, "0")}'
                        : '종료일'),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: (_rankStartDate != null && _rankEndDate != null) ? () {
                      _loadRankScoreStatistics();
                    } : null,
                    child: const Text('적용'),
                  ),
                ],
              ),
            ],
            
            
            // 차트 (순위와 점수 두 라인, 좌우 Y축)
            if (_rankScoreData != null && _rankScoreData!['hourly_data'] != null) ...[
              // 디버깅 정보 표시 (DEBUG 빌드만)
              if (kDebugMode)
                Container(
                  padding: const EdgeInsets.all(8.0),
                  color: Colors.black87,
                  child: Builder(
                    builder: (context) {
                      final hourlyData = _rankScoreData!['hourly_data'] as List;
                      // ✅ 0과 텍스트 필터링
                      final validData = hourlyData.where((e) {
                        final rankValue = e['rank'];
                        final scoreValue = e['score'];
                        if (rankValue == null || scoreValue == null) return false;
                        try {
                          final rank = (rankValue is String) ? double.parse(rankValue) : (rankValue as num).toDouble();
                          final score = (scoreValue is String) ? double.parse(scoreValue) : (scoreValue as num).toDouble();
                          return rank > 0 && score > 0;
                        } catch (e) {
                          return false;
                        }
                      }).toList();
                      
                      final rankList = validData.map((e) {
                        final val = e['rank'];
                        return (val is String) ? double.parse(val) : (val as num).toDouble();
                      }).toList();
                      
                      final scoreList = validData.map((e) {
                        final val = e['score'];
                        return (val is String) ? double.parse(val) : (val as num).toDouble();
                      }).toList();
                      
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('🔍 디버깅 정보 (DEBUG 빌드만)', style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)),
                          Text('전체: ${hourlyData.length}, 유효: ${validData.length}', style: TextStyle(color: Colors.white, fontSize: 12)),
                          Text('첫 번째 데이터: ${validData.isNotEmpty ? validData[0] : "없음"}', style: TextStyle(color: Colors.white, fontSize: 12)),
                          Text('rankList: ${rankList.take(5).toList()}...', style: TextStyle(color: Colors.amber, fontSize: 12)),
                          Text('scoreList: ${scoreList.take(5).toList()}...', style: TextStyle(color: Colors.blue, fontSize: 12)),
                        ],
                      );
                    }
                  ),
                ),
              Container(
                height: 370,
                padding: const EdgeInsets.only(right: 50, top: 90, bottom: 8, left: 8),
                child: Builder(
                  builder: (context) {
                    final hourlyData = _rankScoreData!['hourly_data'] as List;
                    
                    // ✅ 데이터 필터링: rank>0, score>0, 문자열 파싱
                    final validData = hourlyData.where((e) {
                      final rankValue = e['rank'];
                      final scoreValue = e['score'];
                      if (rankValue == null || scoreValue == null) return false;
                      try {
                        final rank = (rankValue is String) ? double.parse(rankValue) : (rankValue as num).toDouble();
                        final score = (scoreValue is String) ? double.parse(scoreValue) : (scoreValue as num).toDouble();
                        return rank > 0 && score > 0;
                      } catch (e) {
                        return false;
                      }
                    }).toList();
                    
                    if (validData.isEmpty) {
                      return Center(child: Text('유효한 데이터가 없습니다', style: TextStyle(color: Colors.white)));
                    }
                    
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: validData.length * 70.0 > 300 ? validData.length * 70.0 : 300,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            print('🔍 그래프 디버깅 시작');
                            print('데이터 개수: ${validData.length}');
                            
                            final rankList = validData.map((e) {
                              final val = e['rank'];
                              return (val is String) ? double.parse(val) : (val as num).toDouble();
                            }).toList();
                            
                            final scoreList = validData.map((e) {
                              final val = e['score'];
                              return (val is String) ? double.parse(val) : (val as num).toDouble();
                            }).toList();
                            
                            print('rankList: $rankList');
                            print('scoreList: $scoreList');
                            
                            final minRank = rankList.reduce((a, b) => a < b ? a : b);
                            final maxRank = rankList.reduce((a, b) => a > b ? a : b);
                            final minScore = scoreList.reduce((a, b) => a < b ? a : b);
                            final maxScore = scoreList.reduce((a, b) => a > b ? a : b);
                            
                            print('minRank: $minRank, maxRank: $maxRank');
                            print('minScore: $minScore, maxScore: $maxScore');
                            
                            final rankRange = maxRank - minRank;
                            final scoreRange = maxScore - minScore;
                            
                            print('rankRange: $rankRange, scoreRange: $scoreRange');
                            
                            final safeRankRange = rankRange > 0 ? rankRange : 1.0;
                            final safeScoreRange = scoreRange > 0 ? scoreRange : 100.0;
                            
                            print('safeRankRange: $safeRankRange, safeScoreRange: $safeScoreRange');
                            
                            final chartWidth = constraints.maxWidth;
                            final chartHeight = constraints.maxHeight;
                            final leftPadding = 50.0;
                            final bottomPadding = 32.0;
                            final topPadding = 20.0;
                            final rightPadding = 55.0;
                            
                            final plotWidth = chartWidth - leftPadding - rightPadding;
                            final plotHeight = chartHeight - topPadding - bottomPadding;
                            
                            return Stack(
                              children: [
                                LineChart(
                          LineChartData(
                            gridData: FlGridData(show: true),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true, 
                                  reservedSize: 50,
                                  interval: (safeRankRange / 5).ceilToDouble(),
                                  getTitlesWidget: (value, meta) {
                                    // 맨 위 라벨은 잘리므로 숨김
                                    if (value == meta.max) {
                                      return const SizedBox.shrink();
                                    }
                                    // Y축이 정상이므로 value를 역변환하여 실제 순위 표시
                                    final actualRank = maxRank + minRank - value;
                                    return Text(
                                      '${actualRank.toInt()}위',
                                      style: const TextStyle(fontSize: 9, color: Colors.amber),
                                    );
                                  },
                                ),
                              ),
                              rightTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 60,
                                  interval: (safeRankRange / 5).ceilToDouble(),
                                  getTitlesWidget: (value, meta) {
                                    // 맨 위 라벨은 좌측과 겹치므로 숨김
                                    if (value == meta.max) {
                                      return const SizedBox.shrink();
                                    }
                                    // scaledScore = minRank + (score - minScore)/safeScoreRange * safeRankRange 를 역변환
                                    // value = minRank + (score - minScore)/safeScoreRange * safeRankRange
                                    // score = minScore + (value - minRank) * safeScoreRange / safeRankRange
                                    final actualScore = minScore + (value - minRank) * safeScoreRange / safeRankRange;
                                    return Text(
                                      '${actualScore.toInt()}점',
                                      style: const TextStyle(fontSize: 9, color: Colors.blue),
                                    );
                                  },
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 32,
                                  interval: validData.length > 10 ? (validData.length / 10).ceilToDouble() : 1,
                                  getTitlesWidget: (value, meta) {
                                    final index = value.toInt();
                                    if (index >= 0 && index < validData.length) {
                                      String time = validData[index]['time'] ?? '';
                                      // "09-28 23시" -> "9-28 23시"
                                      if (time.contains('-') && time.contains('시')) {
                                        final parts = time.split(' ');
                                        if (parts.length >= 2) {
                                          final datePart = parts[0];
                                          final timePart = parts[1];
                                          final dateParts = datePart.split('-');
                                          if (dateParts.length == 2) {
                                            final month = int.tryParse(dateParts[0]) ?? 0;
                                            final day = int.tryParse(dateParts[1]) ?? 0;
                                            time = '$month-$day $timePart';
                                          }
                                        }
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 8.0),
                                        child: Text(
                                          time,
                                          style: const TextStyle(fontSize: 9),
                                        ),
                                      );
                                    }
                                    return const Text('');
                                  },
                                ),
                              ),
                              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            borderData: FlBorderData(show: true),
                            minY: minRank - (safeRankRange * 0.1),
                            maxY: maxRank + (safeRankRange * 0.1),
                            lineBarsData: [
                              // ✅ 순위 라인 - 데이터를 반전시켜서 작은 순위가 위에 오도록
                              LineChartBarData(
                                spots: validData.asMap().entries.map((entry) {
                                  final val = entry.value['rank'];
                                  final rank = (val is String) ? double.parse(val) : (val as num).toDouble();
                                  // 작은 순위가 위로: 반전
                                  final invertedRank = maxRank + minRank - rank;
                                  return FlSpot(entry.key.toDouble(), invertedRank);
                                }).toList(),
                                isCurved: true,
                                color: Colors.amber,
                                barWidth: 2,
                                dotData: FlDotData(
                                  show: true,
                                  getDotPainter: (spot, percent, barData, index) {
                                    return FlDotCirclePainter(
                                      radius: 4,
                                      color: Colors.amber,
                                      strokeWidth: 1,
                                      strokeColor: Colors.white,
                                    );
                                  },
                                ),
                                show: true,
                              ),
                              // ✅ 점수 라인 - 반전된 Y축에 맞춰 변환
                              LineChartBarData(
                                spots: validData.asMap().entries.map((entry) {
                                  final val = entry.value['score'];
                                  final score = (val is String) ? double.parse(val) : (val as num).toDouble();
                                  // 점수를 순위 범위로 선형 변환
                                  // (minScore -> minRank, maxScore -> maxRank)
                                  final scaledScore = minRank + (score - minScore) / safeScoreRange * safeRankRange;
                                  return FlSpot(entry.key.toDouble(), scaledScore);
                                }).toList(),
                                isCurved: true,
                                color: Colors.blue,
                                barWidth: 2,
                                dotData: FlDotData(
                                  show: true,
                                  getDotPainter: (spot, percent, barData, index) {
                                    return FlDotCirclePainter(
                                      radius: 4,
                                      color: Colors.blue,
                                      strokeWidth: 1,
                                      strokeColor: Colors.white,
                                    );
                                  },
                                ),
                              ),
                            ],
                            extraLinesData: ExtraLinesData(
                              horizontalLines: [
                                // 20위 슈퍼챔피언스 기준선 (Y축 범위 안에 있을 때만 표시)
                                if (minRank <= 20 && maxRank >= 20)
                                  HorizontalLine(
                                    y: 20,
                                    color: Colors.amber.withOpacity(0.8),
                                    strokeWidth: 2,
                                    dashArray: [8, 4],
                                    label: HorizontalLineLabel(
                                      show: true,
                                      alignment: Alignment.topRight,
                                      padding: const EdgeInsets.only(right: 5, bottom: 5),
                                      style: const TextStyle(
                                        color: Colors.amber,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                      labelResolver: (line) => '슈챔 20위',
                                    ),
                                  ),
                                // 200위 주차 기준선 (Y축 범위 안에 있을 때만 표시)
                                if (minRank <= 200 && maxRank >= 200)
                                  HorizontalLine(
                                    y: 200,
                                    color: Colors.redAccent.withOpacity(0.7),
                                    strokeWidth: 2,
                                    dashArray: [8, 4],
                                    label: HorizontalLineLabel(
                                      show: true,
                                      alignment: Alignment.topRight,
                                      padding: const EdgeInsets.only(right: 5, bottom: 5),
                                      style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                      labelResolver: (line) => '주차 200위',
                                    ),
                                  ),
                              ],
                              verticalLines: [],
                            ),
                            lineTouchData: LineTouchData(
                              enabled: true,
                              touchTooltipData: LineTouchTooltipData(
                                getTooltipItems: (touchedSpots) {
                                  return touchedSpots.map((spot) {
                                    final dataIndex = spot.x.toInt();
                                    if (dataIndex >= 0 && dataIndex < validData.length) {
                                      if (spot.barIndex == 0) {
                                        // 순위 툴팁
                                        final val = validData[dataIndex]['rank'];
                                        final rank = (val is String) ? int.parse(val) : (val as num).toInt();
                                        return LineTooltipItem(
                                          '${rank}위',
                                          const TextStyle(
                                            color: Colors.amber, 
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        );
                                      } else {
                                        // 점수 툴팁
                                        final val = validData[dataIndex]['score'];
                                        final score = (val is String) ? int.parse(val) : (val as num).toInt();
                                        return LineTooltipItem(
                                          '$score점',
                                          const TextStyle(
                                            color: Colors.blue, 
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        );
                                      }
                                    }
                                    return null;
                                  }).toList();
                                },
                              ),
                            ),
                          ),
                        ),
                        // ✅ 각 데이터 포인트 위에 항상 보이는 라벨
                        ...validData.asMap().entries.map((entry) {
                          final index = entry.key;
                          final data = entry.value;
                          
                          final val = data['rank'];
                          final rank = (val is String) ? double.parse(val) : (val as num).toDouble();
                          final invertedRank = maxRank + minRank - rank;
                          
                          final scoreVal = data['score'];
                          final score = (scoreVal is String) ? double.parse(scoreVal) : (scoreVal as num).toDouble();
                          // 점수를 순위 범위로 선형 변환 (minScore->minRank, maxScore->maxRank)
                          final scaledScore = minRank + (score - minScore) / safeScoreRange * safeRankRange;
                          
                          // Y축 범위 계산
                          final pad = safeRankRange * 0.1;
                          final yMin = minRank - pad;
                          final yMax = maxRank + pad;
                          final yRange = yMax - yMin;
                          
                          // X, Y 좌표 계산
                          final xPos = leftPadding + (plotWidth / (validData.length - 1)) * index;
                          
                          // 순위 Y 좌표: invertedRank가 클수록 위로 (작은 순위가 위)
                          final rankYPos = topPadding + plotHeight * (1 - (invertedRank - yMin) / yRange);
                          
                          // 점수 Y 좌표: scaledScore가 클수록 위로
                          final scoreYPos = topPadding + plotHeight * (1 - (scaledScore - yMin) / yRange);
                          
                          return Stack(
                            children: [
                              // 순위 라벨 (amber) - 점 위에
                              Positioned(
                                left: xPos - 15,
                                top: rankYPos - 18,
                                child: Text(
                                  '${rank.toInt()}',
                                  style: const TextStyle(
                                    color: Colors.amber,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              // 점수 라벨 (blue) - 점 아래
                              Positioned(
                                left: xPos - 15,
                                top: scoreYPos + 8,
                                child: Text(
                                  '${score.toInt()}',
                                  style: const TextStyle(
                                    color: Colors.blue,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                              ],
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(width: 16, height: 3, color: Colors.amber),
                  const SizedBox(width: 4),
                  const Text('순위 (좌)', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 16),
                  Container(width: 16, height: 3, color: Colors.blue),
                  const SizedBox(width: 4),
                  const Text('점수 (우)', style: TextStyle(fontSize: 12)),
                ],
              ),
            ] else
              const Center(child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('데이터가 없습니다'),
              )),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchCountChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('경기수', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            
            // 필터 버튼
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildPeriodButton('7일', '7', _matchPeriod, (value) {
                  setState(() {
                    _matchPeriod = value;
                    _showMatchDatePicker = false;
                  });
                  _loadMatchCountStatistics();
                }),
                _buildPeriodButton('30일', '30', _matchPeriod, (value) {
                  setState(() {
                    _matchPeriod = value;
                    _showMatchDatePicker = false;
                  });
                  _loadMatchCountStatistics();
                }),
                _buildPeriodButton('기간 선택', 'custom', _matchPeriod, (value) {
                  setState(() {
                    _matchPeriod = value;
                    _showMatchDatePicker = true;
                  });
                }),
              ],
            ),
            
            if (_showMatchDatePicker) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _matchStartDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setState(() {
                            _matchStartDate = date;
                          });
                        }
                      },
                      child: Text(_matchStartDate != null 
                        ? '${_matchStartDate!.year}-${_matchStartDate!.month.toString().padLeft(2, "0")}-${_matchStartDate!.day.toString().padLeft(2, "0")}'
                        : '시작일'),
                    ),
                  ),
                  const Text('~'),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _matchEndDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setState(() {
                            _matchEndDate = date;
                          });
                        }
                      },
                      child: Text(_matchEndDate != null 
                        ? '${_matchEndDate!.year}-${_matchEndDate!.month.toString().padLeft(2, "0")}-${_matchEndDate!.day.toString().padLeft(2, "0")}'
                        : '종료일'),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: (_matchStartDate != null && _matchEndDate != null) ? () {
                      _loadMatchCountStatistics();
                    } : null,
                    child: const Text('적용'),
                  ),
                ],
              ),
            ],
            
            
            // 차트 (바 차트)
            if (_matchCountData != null && _matchCountData!['daily_data'] != null && (_matchCountData!['daily_data'] as List).isNotEmpty) ...[
              Container(
                height: 350,
                padding: const EdgeInsets.only(right: 16, top: 50, bottom: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: (_matchCountData!['daily_data'] as List).length * 70.0 > 300
                      ? (_matchCountData!['daily_data'] as List).length * 70.0
                      : 300,
                    child: Stack(
                      children: [
                        BarChart(
                          BarChartData(
                            gridData: FlGridData(show: true),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 45,
                                  interval: null,
                                  getTitlesWidget: (value, meta) {
                                    // maxY는 눈금선 없는데 레이블 표시되어 잘림 - 제외
                                    if (value == meta.max) {
                                      return const SizedBox.shrink();
                                    }
                                    return Text(
                                      value.toInt().toString(),
                                      style: const TextStyle(fontSize: 9),
                                    );
                                  },
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 32,
                                  interval: 1,
                                  getTitlesWidget: (value, meta) {
                                    final data = _matchCountData!['daily_data'] as List;
                                    final index = value.toInt();
                                    if (index >= 0 && index < data.length) {
                                      String date = data[index]['date'] ?? '';
                                      if (date.length >= 10) {
                                        date = date.substring(5);
                                      }
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 8.0),
                                        child: Text(
                                          date,
                                          style: const TextStyle(fontSize: 9),
                                        ),
                                      );
                                    }
                                    return const Text('');
                                  },
                                ),
                              ),
                              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            borderData: FlBorderData(show: true),
                            barGroups: (_matchCountData!['daily_data'] as List).asMap().entries.map((entry) {
                              final matchCount = (entry.value['match_count'] ?? 0).toDouble();
                              return BarChartGroupData(
                                x: entry.key,
                                barRods: [
                                  BarChartRodData(
                                    toY: matchCount,
                                    color: Theme.of(context).primaryColor,
                                    width: 28,
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                  ),
                                ],
                              );
                            }).toList(),
                            barTouchData: BarTouchData(
                              enabled: true,
                              touchTooltipData: BarTouchTooltipData(
                                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                  return BarTooltipItem(
                                    rod.toY.toInt().toString(),
                                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  );
                                },
                              ),
                            ),
                            minY: 0,
                            maxY: (() {
                              final maxValue = (_matchCountData!['daily_data'] as List)
                                  .map((e) => (e['match_count'] ?? 0) as num)
                                  .reduce((a, b) => a > b ? a : b)
                                  .toDouble();
                              return maxValue * 1.3;
                            })(),
                          ),
                        ),
                        // 막대 중앙에 텍스트 표시
                        ...(_matchCountData!['daily_data'] as List).asMap().entries.map((entry) {
                          final matchCount = entry.value['match_count'] ?? 0;
                          final maxValue = (_matchCountData!['daily_data'] as List)
                              .map((e) => (e['match_count'] ?? 0) as num)
                              .reduce((a, b) => a > b ? a : b)
                              .toDouble();
                          // 차트 실제 영역: height(350) - top(50) - bottom(8) - bottomTitles(32) = 260
                          final chartHeight = 260.0;
                          final barHeight = (matchCount / (maxValue * 1.3)) * chartHeight;
                          final yPos = 50 + (chartHeight - barHeight);
                          // X 위치: leftTitles(45) + 인덱스별 막대 중앙
                          final dataCount = (_matchCountData!['daily_data'] as List).length;
                          final chartWidth = dataCount * 70.0 > 300 ? dataCount * 70.0 : 300.0;
                          final barSpacing = (chartWidth - 45 - 16) / dataCount;
                          final xPos = 45 + (entry.key * barSpacing) + (barSpacing / 2);

                          return Positioned(
                            left: xPos - 10,
                            top: yPos + barHeight / 2 - 7,
                            child: Text(
                              matchCount.toString(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ),
              ),
            ] else
              const Center(child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('데이터가 없습니다'),
              )),
          ],
        ),
      ),
    );
  }  // _buildStatisticsTab 끝

  // ===== 시간대별 승률 히트맵 (2026-07-25, 웹 대시보드 카드 이식) =====

  static const double _hwClamp = 10.0; // 색 스케일 상한 ±10%p (이상은 포화)

  // 웹(static/user/hourly_winrate.js)과 동일한 발산형 팔레트 (라이트/다크)
  Map<String, Color> _hwPalette() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? {
            'pos': const Color(0xFF5B9BD5), // 평균 이상 (파랑)
            'neg': const Color(0xFFE0685C), // 평균 이하 (빨강)
            'mid': const Color(0xFF3A3F47), // 편차 0 근처
            'empty': const Color(0xFF25282E), // 경기 없음
            'muted': const Color(0xFFADB5BD),
            'ink': const Color(0xFFE9ECEF),
            'outline': const Color(0xFFE9ECEF),
          }
        : {
            'pos': const Color(0xFF2A78D6),
            'neg': const Color(0xFFE34948),
            'mid': const Color(0xFFF0EFEC),
            'empty': const Color(0xFFE1E0D9),
            'muted': const Color(0xFF6C757D),
            'ink': const Color(0xFF212529),
            'outline': const Color(0xFF333333),
          };
  }

  // 편차(dev)를 ±10%p에서 포화시켜 mid↔pos/neg 선형 보간
  Color _hwDivColor(double dev, Map<String, Color> pal) {
    final t = (dev.abs() / _hwClamp).clamp(0.0, 1.0);
    return Color.lerp(pal['mid'], dev >= 0 ? pal['pos'] : pal['neg'], t)!;
  }

  // 셀 배경 명도에 따라 글자색 자동 대비 (웹과 동일 공식)
  Color _hwInkFor(Color bg) {
    final l = (0.299 * bg.red + 0.587 * bg.green + 0.114 * bg.blue) / 255;
    return l > 0.55 ? const Color(0xFF0B0B0B) : Colors.white;
  }

  String _hwFmtPick(dynamic c) {
    if (c == null) return '—';
    final dev = (c['dev'] as num?)?.toDouble() ?? 0.0;
    return "${c['h']}시 ${c['wr']}% (${dev > 0 ? '+' : ''}$dev%p)";
  }

  Widget _buildHourlyWinrateCard() {
    final resp = _hourlyWinrateData;
    final data = (resp != null && resp['success'] == true) ? resp['data'] : null;
    final pal = _hwPalette();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('시간대별 승률', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                if (data != null)
                  Text('${data['d_min']} ~ ${data['d_max']}',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
              ],
            ),
            const SizedBox(height: 12),
            if (resp == null)
              const Center(child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('불러오는 중...'),
              ))
            else if (resp['success'] != true)
              Center(child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(resp['error']?.toString() ?? '조회에 실패했습니다'),
              ))
            else if (data == null)
              const Center(child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('아직 집계할 경기 기록이 없습니다'),
              ))
            else ...[
              // 구간별 요약 (경기수·평균·최고/최저 시간)
              ...(data['windows'] as List).map((w) => _buildHwSummaryLine(w)),
              const SizedBox(height: 10),
              // 히트맵 (24시간 × 3구간, 가로 스크롤)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _buildHwHeatmap(data, pal),
              ),
              const SizedBox(height: 8),
              _buildHwSelectedDetail(data),
              const SizedBox(height: 8),
              _buildHwLegend(data, pal),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHwSummaryLine(dynamic w) {
    final label = w['label']?.toString() ?? '';
    if (w['empty'] == true) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text('$label: 해당 기간 경기 없음',
            style: TextStyle(fontSize: 11.5, color: Theme.of(context).hintColor)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$label: ${w['n']}경기 · 평균 ${w['avg']}% · 최고 ${_hwFmtPick(w['best'])} · 최저 ${_hwFmtPick(w['worst'])}',
        style: const TextStyle(fontSize: 11.5),
      ),
    );
  }

  Widget _buildHwHeatmap(Map<String, dynamic> data, Map<String, Color> pal) {
    final windows = data['windows'] as List;
    final minN = (data['min_pick_n'] as num?)?.toInt() ?? 10;
    const cellW = 34.0, cellH = 28.0, labelW = 70.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 시간 라벨 행
        Row(
          children: [
            const SizedBox(width: labelW),
            ...List.generate(24, (h) => SizedBox(
                  width: cellW,
                  child: Text('$h시',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 9, color: pal['muted'])),
                )),
          ],
        ),
        const SizedBox(height: 2),
        // 구간별 행
        ...windows.asMap().entries.map((entry) {
          final wi = entry.key;
          final w = entry.value;
          final hours = (w['empty'] == true) ? null : (w['hours'] as List?);
          return Row(
            children: [
              SizedBox(
                width: labelW,
                child: Text(w['label']?.toString() ?? '',
                    style: TextStyle(fontSize: 10, color: pal['ink']),
                    overflow: TextOverflow.ellipsis),
              ),
              ...List.generate(24, (h) {
                final c = (hours != null && h < hours.length) ? hours[h] : null;
                return _buildHwCell(wi, h, c, minN, w['best'], w['worst'], pal, cellW, cellH);
              }),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildHwCell(int wi, int h, dynamic c, int minN, dynamic best, dynamic worst,
      Map<String, Color> pal, double cellW, double cellH) {
    final n = (c?['n'] as num?)?.toInt() ?? 0;
    if (c == null || n == 0) {
      return Padding(
        padding: const EdgeInsets.all(1),
        child: Container(
          width: cellW - 2,
          height: cellH - 2,
          decoration: BoxDecoration(
            color: pal['empty'],
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      );
    }
    final dev = (c['dev'] as num?)?.toDouble() ?? 0.0;
    final low = n < minN;
    final bg = _hwDivColor(dev, pal);
    final isBest = best != null && best['h'] == h;
    final isWorst = worst != null && worst['h'] == h;
    final selected = _hwSelectedWindow == wi && _hwSelectedHour == h;

    Widget inner = Container(
      width: cellW - 2,
      height: cellH - 2,
      decoration: BoxDecoration(
        color: low ? bg.withOpacity(0.45) : bg,
        borderRadius: BorderRadius.circular(3),
        // 최고 시간=실선 테두리, 탭 선택=강조색 테두리 (최저는 아래 점선 페인터)
        border: (selected || isBest)
            ? Border.all(color: selected ? pal['pos']! : pal['outline']!, width: 2)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        '${dev > 0 ? '+' : ''}${dev.toStringAsFixed(1)}',
        style: TextStyle(fontSize: 8.5, color: low ? pal['muted'] : _hwInkFor(bg)),
      ),
    );
    if (isWorst && !isBest && !selected) {
      inner = CustomPaint(
        foregroundPainter: _HwDashedRectPainter(pal['outline']!),
        child: inner,
      );
    }
    return Padding(
      padding: const EdgeInsets.all(1),
      child: GestureDetector(
        onTap: () => setState(() {
          _hwSelectedWindow = wi;
          _hwSelectedHour = h;
        }),
        child: inner,
      ),
    );
  }

  Widget _buildHwSelectedDetail(Map<String, dynamic> data) {
    final wi = _hwSelectedWindow;
    final h = _hwSelectedHour;
    if (wi == null || h == null) {
      return Text('셀을 누르면 상세 정보가 표시됩니다',
          style: TextStyle(fontSize: 10.5, color: Theme.of(context).hintColor));
    }
    final windows = data['windows'] as List;
    if (wi >= windows.length) return const SizedBox.shrink();
    final w = windows[wi];
    final hours = (w['empty'] == true) ? null : (w['hours'] as List?);
    final c = (hours != null && h < hours.length) ? hours[h] : null;
    if (c == null || ((c['n'] as num?)?.toInt() ?? 0) == 0) return const SizedBox.shrink();
    final minN = (data['min_pick_n'] as num?)?.toInt() ?? 10;
    final dev = (c['dev'] as num?)?.toDouble() ?? 0.0;
    final lowNote = (c['n'] as num).toInt() < minN ? ' · 표본 $minN경기 미만(참고만)' : '';
    return Text(
      '${w['label']} · ${c['h']}시 — 승률 ${c['wr']}% (${c['n']}경기) · 구간 평균 ${w['avg']}% 대비 ${dev > 0 ? '+' : ''}$dev%p$lowNote',
      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
    );
  }

  Widget _buildHwLegend(Map<String, dynamic> data, Map<String, Color> pal) {
    final minN = (data['min_pick_n'] as num?)?.toInt() ?? 10;
    final style = TextStyle(fontSize: 9.5, color: Theme.of(context).hintColor);
    Widget sw(Color c, {BoxBorder? border, double opacity = 1}) => Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: c.withOpacity(opacity),
            border: border,
            borderRadius: BorderRadius.circular(2),
          ),
        );
    Widget item(Widget swatch, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [swatch, const SizedBox(width: 3), Text(label, style: style)],
        );
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('구간 평균 대비:', style: style),
        for (final v in [-10.0, -5.0, 0.0, 5.0, 10.0])
          item(sw(_hwDivColor(v, pal)), '${v > 0 ? '+' : ''}${v.toInt()}%p'),
        item(sw(_hwDivColor(-5, pal), opacity: 0.45), '흐림=$minN경기 미만'),
        item(sw(pal['empty']!), '경기 없음'),
        item(sw(Colors.transparent, border: Border.all(color: pal['outline']!, width: 2)), '최고 시간'),
        item(
          SizedBox(
            width: 12,
            height: 12,
            child: CustomPaint(painter: _HwDashedRectPainter(pal['outline']!)),
          ),
          '최저 시간',
        ),
      ],
    );
  }

  Widget _buildMatchHistoryTab() {
    return RefreshIndicator(
      onRefresh: _loadMatchHistory,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAccountDropdown(),
              // 모드 필터
              const Text('모드', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildFilterButton('감독모드', 'manager_mode', _matchMode, (value) {
                    setState(() {
                      _matchMode = value;
                      _matchSeason = 'all';  // 모드별 시즌 체계가 다르므로 초기화
                    });
                    _loadMatchHistory();
                  }),
                  _buildFilterButton('공식경기', 'official_mode', _matchMode, (value) {
                    setState(() {
                      _matchMode = value;
                      _matchSeason = 'all';
                    });
                    _loadMatchHistory();
                  }),
                  _buildFilterButton('클래식1on1', 'classic_1on1', _matchMode, (value) {
                    setState(() {
                      _matchMode = value;
                      _matchSeason = 'all';
                    });
                    _loadMatchHistory();
                  }),
                ],
              ),
              const SizedBox(height: 16),

              // 시즌 필터 (2026-09-05) — 1단계 필터: 아래 결과·기간·상대 검색은 선택 시즌 안에서 적용
              const Text('시즌', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildFilterButton('전체', 'all', _matchSeason, (value) {
                    setState(() {
                      _matchSeason = value;
                    });
                    _loadMatchHistory();
                  }),
                  ..._matchSeasons.map((s) {
                    final key = _seasonKey(s['season_id']);
                    final label = s['season_id'] == null ? '시즌 정보 없음' : '${s['season_id']}';
                    final count = s['count'] ?? 0;
                    return _buildFilterButton('$label ($count)', key, _matchSeason, (value) {
                      setState(() {
                        _matchSeason = value;
                      });
                      _loadMatchHistory();
                    });
                  }),
                ],
              ),
              const SizedBox(height: 16),

              // 결과 필터
              const Text('결과', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildFilterButton('전체', 'all', _matchResult, (value) {
                    setState(() {
                      _matchResult = value;
                    });
                    _loadMatchHistory();
                  }),
                  _buildFilterButton('승', 'win', _matchResult, (value) {
                    setState(() {
                      _matchResult = value;
                    });
                    _loadMatchHistory();
                  }),
                  _buildFilterButton('무', 'draw', _matchResult, (value) {
                    setState(() {
                      _matchResult = value;
                    });
                    _loadMatchHistory();
                  }),
                  _buildFilterButton('패', 'lose', _matchResult, (value) {
                    setState(() {
                      _matchResult = value;
                    });
                    _loadMatchHistory();
                  }),
                  _buildFilterButton('오류', 'error', _matchResult, (value) {
                    setState(() {
                      _matchResult = value;
                    });
                    _loadMatchHistory();
                  }),
                ],
              ),
              const SizedBox(height: 16),
              
              // 기간 필터
              const Text('기간', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildPeriodButton('전체', 'all', _matchHistoryPeriod, (value) {
                    setState(() {
                      _matchHistoryPeriod = value;
                      _showMatchHistoryDatePicker = false;
                    });
                    _loadMatchHistory();
                  }),
                  _buildPeriodButton('6시간', '6h', _matchHistoryPeriod, (value) {
                    setState(() {
                      _matchHistoryPeriod = value;
                      _showMatchHistoryDatePicker = false;
                    });
                    _loadMatchHistory();
                  }),
                  _buildPeriodButton('12시간', '12h', _matchHistoryPeriod, (value) {
                    setState(() {
                      _matchHistoryPeriod = value;
                      _showMatchHistoryDatePicker = false;
                    });
                    _loadMatchHistory();
                  }),
                  _buildPeriodButton('오늘', 'today', _matchHistoryPeriod, (value) {
                    setState(() {
                      _matchHistoryPeriod = value;
                      _showMatchHistoryDatePicker = false;
                    });
                    _loadMatchHistory();
                  }),
                  _buildPeriodButton('일주일', 'week', _matchHistoryPeriod, (value) {
                    setState(() {
                      _matchHistoryPeriod = value;
                      _showMatchHistoryDatePicker = false;
                    });
                    _loadMatchHistory();
                  }),
                  _buildPeriodButton('1달', 'month', _matchHistoryPeriod, (value) {
                    setState(() {
                      _matchHistoryPeriod = value;
                      _showMatchHistoryDatePicker = false;
                    });
                    _loadMatchHistory();
                  }),
                  _buildPeriodButton('직접선택', 'custom', _matchHistoryPeriod, (value) {
                    setState(() {
                      _matchHistoryPeriod = value;
                      _showMatchHistoryDatePicker = true;
                    });
                  }),
                ],
              ),
              
              if (_showMatchHistoryDatePicker) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _matchHistoryStartDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (date != null) {
                            setState(() { _matchHistoryStartDate = date; });
                          }
                        },
                        child: Text(_matchHistoryStartDate != null
                          ? '${_matchHistoryStartDate!.year}-${_matchHistoryStartDate!.month.toString().padLeft(2, "0")}-${_matchHistoryStartDate!.day.toString().padLeft(2, "0")}'
                          : '시작일'),
                      ),
                    ),
                    const Text('~'),
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _matchHistoryEndDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (date != null) {
                            setState(() { _matchHistoryEndDate = date; });
                          }
                        },
                        child: Text(_matchHistoryEndDate != null
                          ? '${_matchHistoryEndDate!.year}-${_matchHistoryEndDate!.month.toString().padLeft(2, "0")}-${_matchHistoryEndDate!.day.toString().padLeft(2, "0")}'
                          : '종료일'),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: (_matchHistoryStartDate != null && _matchHistoryEndDate != null) ? () {
                        _loadMatchHistory();
                      } : null,
                      child: const Text('적용'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              
              // 상대팀 검색
              const Text('상대팀 검색', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  hintText: '상대 감독명 입력...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                ),
                onSubmitted: (value) {
                  setState(() {
                    _opponentSearch = value.trim();
                  });
                },
                onChanged: (value) {
                  if (value.isEmpty && _opponentSearch.isNotEmpty) {
                    setState(() {
                      _opponentSearch = '';
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              
              // 통계 요약
              if (_matchStats.isNotEmpty) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        // 승무패 색 통일 (상태탭 A안 규칙 — 2026-08-19)
                        _buildStatItem('승', _matchStats['wins'] ?? 0, _wdlWin(context)),
                        _buildStatItem('무', _matchStats['draws'] ?? 0, _wdlDraw(context)),
                        _buildStatItem('패', _matchStats['losses'] ?? 0, _wdlLose(context)),
                        _buildStatItem('승률', _matchStats['win_rate'] ?? 0, _wdlWin(context), isRate: true),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // 매치 리스트
              if (_matchHistoryLoading)
                const Center(child: CircularProgressIndicator())
              else if (_matchHistory.isEmpty)
                const Center(child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text('전적이 없습니다'),
                ))
              else
                Column(
                  children: [
                    Builder(
                      builder: (context) {
                        // 상대팀 검색 필터링
                        final filteredMatches = _matchHistory.where((m) {
                          if (_opponentSearch.isNotEmpty) {
                            final opponent = (m['opponent'] ?? '').toString().toLowerCase();
                            if (!opponent.contains(_opponentSearch.toLowerCase())) {
                              return false;
                            }
                          }
                          return true;
                        }).toList();
                        
                        // 페이지네이션 적용 (처음 _displayedMatchCount개만 표시)
                        final displayMatches = filteredMatches.take(_displayedMatchCount).toList();
                        
                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: displayMatches.length,
                          itemBuilder: (context, index) {
                            final match = displayMatches[index];
                            return _buildMatchCard(match);
                          },
                        );
                      },
                    ),
                    // 더보기 버튼
                    if (_matchHistory.where((m) {
                      if (_opponentSearch.isNotEmpty) {
                        final opponent = (m['opponent'] ?? '').toString().toLowerCase();
                        return opponent.contains(_opponentSearch.toLowerCase());
                      }
                      return true;
                    }).length > _displayedMatchCount)
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _displayedMatchCount += _matchesPerPage;
                            });
                          },
                          icon: const Icon(Icons.expand_more),
                          label: Text('$_matchesPerPage경기 더 보기'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 시즌 번호 → 필터 값 문자열 (null이면 'none')
  String _seasonKey(dynamic seasonId) => seasonId == null ? 'none' : '$seasonId';

  Widget _buildFilterButton(String label, String value, String currentValue, Function(String) onPressed) {
    final isActive = currentValue == value;
    return OutlinedButton(
      onPressed: () => onPressed(value),
      style: OutlinedButton.styleFrom(
        backgroundColor: isActive ? Theme.of(context).primaryColor : null,
        foregroundColor: isActive ? Colors.white : null,
      ),
      child: Text(label),
    );
  }

  Widget _buildStatItem(String label, num value, Color color, {bool isRate = false}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          isRate ? '${value.toStringAsFixed(1)}%' : value.toString(),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildMatchCard(Map<String, dynamic> match) {
    final result = match['result'] ?? '';
    // 승무패 색 통일 (상태탭 A안 규칙 — 2026-08-19)
    Color resultColor = _wdlDraw(context);
    if (result.contains('승')) resultColor = _wdlWin(context);
    else if (result.contains('패')) resultColor = _wdlLose(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        // 경기 탭 → 경기별 분석 (요약/스쿼드/선수 — 공개 검색 탭과 동일 화면)
        onTap: match['matchId'] == null
            ? null
            : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MatchDetailScreen(
                      matchId: match['matchId'].toString(),
                      myName: match['manager_name']?.toString() ??
                          widget.username,
                      mode: _matchMode == 'manager_mode' ? 'manager' : '1vs1',
                    ),
                  ),
                );
              },
        leading: CircleAvatar(
          backgroundColor: resultColor,
          child: Text(
            result.length > 2 ? result.substring(0, 2) : result,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          match['opponent'] ?? '알 수 없음',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          match['matchDate'] ?? '',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              match['score'] ?? '',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            // 승부차기 표기: "2:2" + "승부차기 1:4" (사용자 지정 형식)
            if (match['penalty_score'] != null)
              Text(
                '승부차기 ${match['penalty_score']}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  String _formatNumber(String num) {
    if (num == '-' || num.isEmpty) return '-';
    try {
      final number = int.parse(num);
      return number.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      );
    } catch (e) {
      return num;
    }
  }

  // ===== WebSocket 연결 (알림 시스템) =====
  Future<void> _connectWebSocket() async {
    try {
      final token = _apiService.token;
      if (token != null && token.isNotEmpty) {
  await SocketService().connect(token, ApiService.baseUrl);
        print('[Dashboard] WebSocket 연결 성공');
      }
    } catch (e) {
      print('[Dashboard] WebSocket 연결 오류: $e');
    }
  }

}

/// 최근 경기 도트 위젯 — 자유 스크롤, 보이는 20개 기준 승무패 집계
class _RecentGamesDots extends StatefulWidget {
  final List<String> results;
  const _RecentGamesDots({required this.results});

  @override
  State<_RecentGamesDots> createState() => _RecentGamesDotsState();
}

class _RecentGamesDotsState extends State<_RecentGamesDots> {
  final ScrollController _scrollController = ScrollController();
  int _leftIndex = 0;   // 현재 보이는 가장 왼쪽 도트의 인덱스 (0=가장 오래된)
  double _dotWidth = 14.0;
  bool _scrollInitialized = false;
  static const int _visibleCount = 20;

  @override
  void initState() {
    super.initState();
    // 최신 20개가 먼저 보이도록 초기 위치 설정
    final total = widget.results.length;
    _leftIndex = (total - _visibleCount).clamp(0, total);
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _dotWidth <= 0) return;
    final total = widget.results.length;
    final maxLeft = (total - _visibleCount).clamp(0, total);
    final newLeft = (_scrollController.offset / _dotWidth).round().clamp(0, maxLeft);
    if (newLeft != _leftIndex) {
      setState(() => _leftIndex = newLeft);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.results.length;
    if (total == 0) return const SizedBox.shrink();

    final end = (_leftIndex + _visibleCount).clamp(0, total);
    final visibleDots = widget.results.sublist(_leftIndex, end);
    final wins   = visibleDots.where((r) => r == 'WIN').length;
    final draws  = visibleDots.where((r) => r == 'DRAW').length;
    final losses = visibleDots.where((r) => r == 'LOSE').length;
    // 최신 기준 번호: 가장 오른쪽 도트가 1번째(최신)
    final rangeEnd   = total - _leftIndex;
    final rangeStart = (rangeEnd - visibleDots.length + 1).clamp(1, total);
    final canLeft  = _leftIndex > 0;
    final canRight = _leftIndex < total - _visibleCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('◀',
              style: TextStyle(
                fontSize: 11,
                color: canLeft ? Colors.grey[500] : Colors.grey[300],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _dotWidth = constraints.maxWidth / _visibleCount;
                  // 첫 렌더링 시 최신 위치로 스크롤 이동
                  if (!_scrollInitialized && total > _visibleCount) {
                    _scrollInitialized = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_scrollController.hasClients) {
                        _scrollController.jumpTo(
                          (_leftIndex * _dotWidth).clamp(
                            0.0, _scrollController.position.maxScrollExtent,
                          ),
                        );
                      }
                    });
                  }
                  return SizedBox(
                    height: 22,
                    child: NotificationListener<ScrollEndNotification>(
                      // 스크롤 끝나면 도트 경계에 스냅
                      onNotification: (_) {
                        if (_scrollController.hasClients) {
                          final snapped = (_leftIndex * _dotWidth).clamp(
                            0.0, _scrollController.position.maxScrollExtent,
                          );
                          if ((_scrollController.offset - snapped).abs() > 0.5) {
                            _scrollController.animateTo(
                              snapped,
                              duration: const Duration(milliseconds: 80),
                              curve: Curves.easeOut,
                            );
                          }
                        }
                        return false;
                      },
                      child: ListView.builder(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        itemCount: total,
                        itemExtent: _dotWidth,
                        physics: const BouncingScrollPhysics(),
                        itemBuilder: (context, index) {
                          final r = widget.results[index];
                          // 인게임 스타일 사각 타일 — 색상 프리셋 (승 승리색 / 무 중립 회색 / 패 패배색)
                          final tokens = PanenkaTokens.of(context);
                          final bg = r == 'WIN'
                              ? tokens.win
                              : r == 'DRAW'
                                  ? const Color(0xFF8B87A0)
                                  : tokens.lose;
                          final fg = r == 'WIN' ? tokens.onWin : Colors.white;
                          final ch = r == 'WIN' ? '승' : r == 'DRAW' ? '무' : '패';
                          return Center(
                            child: Container(
                              width: (_dotWidth - 2).clamp(8.0, 16.0),
                              height: 19,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: bg,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Text(
                                ch,
                                style: TextStyle(
                                  color: fg,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 4),
            Text('▶',
              style: TextStyle(
                fontSize: 11,
                color: canRight ? Colors.grey[500] : Colors.grey[300],
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '최근 $rangeStart~$rangeEnd번째',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            const SizedBox(width: 8),
            // 색상 프리셋 (승 승리색 / 무 중립 회색 / 패 패배색)
            _badge('승 $wins', PanenkaTokens.of(context).win,
                PanenkaTokens.of(context).onWin),
            const SizedBox(width: 4),
            _badge('무 $draws', const Color(0xFF8B87A0), Colors.white),
            const SizedBox(width: 4),
            _badge('패 $losses', PanenkaTokens.of(context).lose, Colors.white),
          ],
        ),
      ],
    );
  }

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: fg,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}





/// 시간대별 승률 히트맵의 '최저 시간' 점선 테두리 페인터 (웹 stroke-dasharray 대응)
class _HwDashedRectPainter extends CustomPainter {
  final Color color;
  _HwDashedRectPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const dash = 4.0, gap = 3.0;
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, const Radius.circular(3));
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HwDashedRectPainter oldDelegate) =>
      oldDelegate.color != color;
}
