import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_service.dart';
import '../providers/theme_provider.dart';
import '../services/socket_service.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'login_screen.dart';

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

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  Timer? _timer;
  List<Map<String, dynamic>> _accounts = [];
  bool _isLoading = true;
  bool _isInputting = false;  // 사용자 입력 중 플래그
  bool _statisticsLoading = false;  // 통계 로딩 플래그
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
  
  // 전적 필터 상태
  String _matchMode = 'manager_mode';  // manager_mode, official_mode, classic_1on1
  String _matchResult = 'all';  // all, win, draw, lose, error
  String _matchHistoryPeriod = 'all';  // all, 6h, 12h, today, week, month, custom
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
  String _rankingMode = 'manager';
  List<Map<String, dynamic>> _top40Rankings = [];
  List<Map<String, dynamic>> _bottom11Rankings = [];
  Map<String, dynamic>? _cutlines;
  bool _rankingLoading = false;
  String _rankingDateInfo = '';

  @override
  void initState() {
    super.initState();
    _selectedAccount = widget.username;
    _tabController = TabController(length: 4, vsync: this);
    
    // 탭 전환 리스너 추가
    _tabController.addListener(() {
      setState(() {}); // AppBar 조건부 버튼 업데이트
      if (_tabController.index == 1 && _selectedAccount != null && _selectedAccount!.isNotEmpty) {
        // 통계 탭으로 전환 시 데이터 로드
        _loadFCStatistics();
        _loadRankScoreStatistics();
        _loadMatchCountStatistics();
      } else if (_tabController.index == 2 && _selectedAccount != null && _selectedAccount!.isNotEmpty) {
        // 전적 탭으로 전환 시 데이터 로드
        _loadMatchHistory();
      } else if (_tabController.index == 3) {
        // 랭킹 탭으로 전환 시 데이터 로드
        _loadRankingData();
      }
    });
    
    _loadStatus();
    _timer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (!_isInputting) {  // 입력 중이 아닐 때만 새로고침
        _loadStatus();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tabController.dispose();
    SocketService().disconnect();  // WebSocket 연결 해제
    super.dispose();
  }

// API 호출 함수들
  Future<void> _loadFCStatistics() async {
    if (_selectedAccount == null || _selectedAccount!.isEmpty) return;
    
    setState(() {
      _statisticsLoading = true;
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
        _statisticsLoading = false;
      });
    } catch (e) {
      setState(() {
        _statisticsLoading = false;
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
      _statisticsLoading = true;
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
        _statisticsLoading = false;
      });
    } catch (e) {
      setState(() {
        _statisticsLoading = false;
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
      _statisticsLoading = true;
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
        _statisticsLoading = false;
      });
    } catch (e) {
      setState(() {
        _statisticsLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('경기수 로드 실패: $e')),
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
      );

      setState(() {
        if (data['success'] == true) {
          _matchHistory = List<Map<String, dynamic>>.from(data['matches'] ?? []);
          _matchStats = Map<String, int>.from(data['statistics'] ?? {});
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
    if (result['success']) {
      setState(() {
        _accounts = List<Map<String, dynamic>>.from(result['accounts'] ?? []);
        _isLoading = false;
      });
    }
  }

  Future<void> _startMacro(String username, String mode, bool clubDonation, Map<String, dynamic>? parkingConditions) async {
    final result = await widget.apiService.startMacro(
      username, 
      mode,
      clubDonation: clubDonation,
      parkingConditions: parkingConditions,
    );
    
    if (result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$username: 매크로 시작 명령 전송됨'), backgroundColor: Colors.green),
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
        SnackBar(content: Text('$username: 매크로 중지 명령 전송됨'), backgroundColor: Colors.orange),
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
        title: Row(
          children: [
            const Icon(Icons.sports_soccer, size: 24),
            const SizedBox(width: 8),
            const Text('FC Online 4 매크로'),
          ],
        ),
        backgroundColor: const Color(0xFF1a237e),
        actions: [
          // 통계 탭 새로고침 버튼 (index 1)
          if (_tabController.index == 1)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _loadFCStatistics();
                _loadRankScoreStatistics();
                _loadMatchCountStatistics();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('통계 데이터 새로고침'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              tooltip: '통계 새로고침',
            ),
          // 전적 탭 새로고침 버튼 (index 2)
          if (_tabController.index == 2)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _loadMatchHistory();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('전적 데이터 새로고침'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              tooltip: '전적 새로고침',
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
            icon: const Icon(Icons.refresh),
            onPressed: _loadStatus,
            tooltip: '상태 새로고침',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await widget.apiService.logout();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
            tooltip: '로그아웃',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,  // ✅ 다크/라이트 모두 흰색으로 통일
          unselectedLabelColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.white60
              : Colors.white70,  // ✅ 라이트 모드에서도 약간 투명한 흰색
          indicatorColor: Theme.of(context).primaryColor,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: '상태'),
            Tab(icon: Icon(Icons.bar_chart), text: '통계'),
            Tab(icon: Icon(Icons.list), text: '전적'),
            Tab(icon: Icon(Icons.emoji_events), text: '랭킹'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStatusTab(),
          _buildStatisticsTab(),
          _buildMatchHistoryTab(),
          _buildRankingTab(),
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
    final record = account['record'] ?? '0-0-0';
    final fcTotal = account['fc_total']?.toString() ?? '0';
    final highestScore = account['highest_score']?.toString() ?? '0';
    final highestScoreTime = account['highest_score_time'] ?? '';
    final timeAgo = account['time_ago'] ?? '알 수 없음';

    final isOnline = status == 'online';
    final isRunning = isOnline && mode.isNotEmpty && mode != 'stopped' && mode != '정지';

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
                    Icon(Icons.person, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 8),
                    Text(
                      username,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    if (isPrimary) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          '주 계정',
                          style: TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ),
                    ],
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isOnline ? Colors.green : Colors.grey,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 10, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        isOnline ? '온라인' : '오프라인',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
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
                _buildInfoItem(Icons.poll, '전적', record),
                _buildInfoItem(Icons.monetization_on, 'FC', '$fcTotal FC'),
                _buildInfoItem(Icons.workspace_premium, '최고점수', _formatNumber(highestScore)),
              ],
            ),
            if (highestScoreTime.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '  최고점수 달성: $highestScoreTime',
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
            ],
            const Divider(height: 24),
            _buildControlSection(username, isOnline, isRunning, mode),
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

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.blue[700]),
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
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControlSection(String username, bool isOnline, bool isRunning, String currentMode) {
    String selectedMode = 'coach';
    bool clubDonation = false;
    bool showParkingConditions = false;
    
    // 주차모드 조건 상태
    bool tierEnabled = false;
    String selectedTier = '슈퍼챔피언스감독';
    bool rankEnabled = false;
    int? rankValue;
    String rankCondition = '이하';
    bool scoreEnabled = false;
    int? scoreValue;
    String scoreCondition = '이상';

    return StatefulBuilder(
      builder: (context, setState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isRunning) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _stopMacro(username),
                  icon: const Icon(Icons.stop),
                  label: const Text('중지'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
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
                              const SnackBar(
                                content: Text('주차모드 조건을 최소 1개 이상 선택해주세요.'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }
                        }
                        
                        _startMacro(username, selectedMode, clubDonation, parkingConditions);
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('시작'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1a237e),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              // 주차모드 조건 입력
              if (showParkingConditions) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[850]
                        : Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[700]!
                          : Colors.blue[200]!,
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
              
              CheckboxListTile(
                value: clubDonation,
                onChanged: (value) {
                  setState(() {
                    clubDonation = value!;
                  });
                },
                title: const Text(' 클럽 기부 (5경기마다)', style: TextStyle(fontSize: 14)),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
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

  Widget _buildStatisticsTab() {
    if (_statisticsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // FC 채굴량 차트
          _buildFCMiningChart(),
          const SizedBox(height: 24),
          
          // 순위/점수 차트
          _buildRankScoreChart(),
          const SizedBox(height: 24),
          
          // 경기수 차트
          _buildMatchCountChart(),
        ],
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
            if (_fcMiningData != null && _fcMiningData!['daily_data'] != null) ...[
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
            if (_matchCountData != null && _matchCountData!['daily_data'] != null) ...[
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
                    });
                    _loadMatchHistory();
                  }),
                  _buildFilterButton('공식경기', 'official_mode', _matchMode, (value) {
                    setState(() {
                      _matchMode = value;
                    });
                    _loadMatchHistory();
                  }),
                  _buildFilterButton('클래식1on1', 'classic_1on1', _matchMode, (value) {
                    setState(() {
                      _matchMode = value;
                    });
                    _loadMatchHistory();
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
                        _buildStatItem('승', _matchStats['wins'] ?? 0, Colors.green),
                        _buildStatItem('무', _matchStats['draws'] ?? 0, Colors.grey),
                        _buildStatItem('패', _matchStats['losses'] ?? 0, Colors.red),
                        _buildStatItem('승률', _matchStats['win_rate'] ?? 0, Colors.blue, isRate: true),
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
    Color resultColor = Colors.grey;
    if (result.contains('승')) resultColor = Colors.green;
    else if (result.contains('패')) resultColor = Colors.red;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
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
        trailing: Text(
          match['penalty_score'] != null
            ? '${match['score']} (${match['penalty_score']})'
            : match['score'] ?? '',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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

  // ===== 랭킹 데이터 로드 (Nexon 웹 크롤링) =====
  Future<void> _loadRankingData() async {
    setState(() {
      _rankingLoading = true;
    });

    try {
      // 감독모드만 고정
      const rtMode = 'manager';
      
      final headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
      };

      // 1-20위 (페이지 1)
      final url1 = 'https://fconline.nexon.com/datacenter/rank_inner?rt=$rtMode&n4pageno=1';
      final response1 = await http.get(Uri.parse(url1), headers: headers).timeout(Duration(seconds: 15));
      
      // 21-40위 (페이지 2)
      final url2 = 'https://fconline.nexon.com/datacenter/rank_inner?rt=$rtMode&n4pageno=2';
      final response2 = await http.get(Uri.parse(url2), headers: headers).timeout(Duration(seconds: 15));
      
      // 190-200위 (페이지 10)
      final url10 = 'https://fconline.nexon.com/datacenter/rank_inner?rt=$rtMode&n4pageno=10';
      final response10 = await http.get(Uri.parse(url10), headers: headers).timeout(Duration(seconds: 15));

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
          
          // 각 시즌의 20위, 200위 점수 가져오기 (재시도 로직 포함)
          for (var season in seasons) {
            // 슈챔컷: 20위 점수 (최대 3회 재시도)
            bool superSuccess = false;
            for (int attempt = 0; attempt < 3 && !superSuccess; attempt++) {
              if (attempt > 0) {
                print('[슈챔컷 재시도] ${season['name']} - 시도 ${attempt + 1}/3');
                await Future.delayed(Duration(seconds: 2)); // 재시도 전 2초 대기
              }
              
              final superUrl = 'https://fconline.nexon.com/datacenter/rank_inner?rt=$rtMode&n4seasonno=${season['no']}';
              try {
                final superResp = await http.get(Uri.parse(superUrl), headers: headers).timeout(Duration(seconds: 30));
                if (superResp.statusCode == 200) {
                  final superDoc = html_parser.parse(superResp.body);
                  final rows = superDoc.querySelectorAll('.tbody .tr');
                  
                  // 데이터 검증: 20위 데이터가 실제로 있는지 확인
                  for (var row in rows) {
                    final rankElem = row.querySelector('.rank_no');
                    if (rankElem != null && rankElem.text.trim() == '20') {
                      final scoreElem = row.querySelector('.rank_r_win_point');
                      if (scoreElem != null) {
                        final score = scoreElem.text.trim();
                        if (score.isNotEmpty && score != '-') {
                          superChampHistory.add({'name': season['name']!, 'score': score});
                          superSuccess = true;
                          print('[슈챔컷 성공] ${season['name']}: $score');
                          break;
                        }
                      }
                    }
                  }
                }
              } catch (e) {
                print('[슈챔컷 이전 시즌 오류] ${season['name']} 시도 ${attempt + 1}: $e');
              }
            }
            
            if (!superSuccess) {
              print('[슈챔컷 최종 실패] ${season['name']} - 3회 시도 후 실패');
            }
            
            // 요청 사이 2초 대기
            await Future.delayed(Duration(seconds: 2));
            
            // 주차컷: 200위 점수 (최대 3회 재시도)
            bool parkingSuccess = false;
            for (int attempt = 0; attempt < 3 && !parkingSuccess; attempt++) {
              if (attempt > 0) {
                print('[주차컷 재시도] ${season['name']} - 시도 ${attempt + 1}/3');
                await Future.delayed(Duration(seconds: 2)); // 재시도 전 2초 대기
              }
              
              final parkingUrl = 'https://fconline.nexon.com/datacenter/rank_inner?rt=$rtMode&n4seasonno=${season['no']}&n4pageno=10';
              try {
                final parkingResp = await http.get(Uri.parse(parkingUrl), headers: headers).timeout(Duration(seconds: 30));
                if (parkingResp.statusCode == 200) {
                  final parkingDoc = html_parser.parse(parkingResp.body);
                  final rows = parkingDoc.querySelectorAll('.tbody .tr');
                  
                  // 데이터 검증: 200위 데이터가 실제로 있는지 확인
                  for (var row in rows) {
                    final rankElem = row.querySelector('.rank_no');
                    if (rankElem != null && rankElem.text.trim() == '200') {
                      final scoreElem = row.querySelector('.rank_r_win_point');
                      if (scoreElem != null) {
                        final score = scoreElem.text.trim();
                        if (score.isNotEmpty && score != '-') {
                          parkingHistory.add({'name': season['name']!, 'score': score});
                          parkingSuccess = true;
                          print('[주차컷 성공] ${season['name']}: $score');
                          break;
                        }
                      }
                    }
                  }
                }
              } catch (e) {
                print('[주차컷 이전 시즌 오류] ${season['name']} 시도 ${attempt + 1}: $e');
              }
            }
            
            if (!parkingSuccess) {
              print('[주차컷 최종 실패] ${season['name']} - 3회 시도 후 실패');
            }
            
            // 다음 시즌 요청 전 2초 대기
            await Future.delayed(Duration(seconds: 2));
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








