import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_service.dart';
import '../providers/theme_provider.dart';

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
  String _matchMode = 'all';  // all, manager_mode, league, promotion
  String _matchResult = 'all';  // all, win, draw, lose, error
  String _matchHistoryPeriod = '7';  // 7, 30, custom
  DateTime? _matchHistoryStartDate, _matchHistoryEndDate;
  bool _showMatchHistoryDatePicker = false;
  
  // 전적 데이터
  List<Map<String, dynamic>> _matchHistory = [];
  bool _matchHistoryLoading = false;
  Map<String, int> _matchStats = {};

  @override
  void initState() {
    super.initState();
    _selectedAccount = widget.username;
    _tabController = TabController(length: 3, vsync: this);
    
    // 탭 전환 리스너 추가
    _tabController.addListener(() {
      if (_tabController.index == 1 && _selectedAccount != null && _selectedAccount!.isNotEmpty) {
        // 통계 탭으로 전환 시 데이터 로드
        _loadFCStatistics();
        _loadRankScoreStatistics();
        _loadMatchCountStatistics();
      } else if (_tabController.index == 2 && _selectedAccount != null && _selectedAccount!.isNotEmpty) {
        // 전적 탭으로 전환 시 데이터 로드
        _loadMatchHistory();
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
    });

    try {
      String? startDate;
      String? endDate;
      
      if (_matchHistoryPeriod == 'custom' && _matchHistoryStartDate != null && _matchHistoryEndDate != null) {
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
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              widget.apiService.logout();
              Navigator.of(context).pushReplacementNamed('/');
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).brightness == Brightness.dark 
              ? Colors.white 
              : Theme.of(context).primaryColor,
          unselectedLabelColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.white60
              : Colors.grey,
          indicatorColor: Theme.of(context).primaryColor,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: '상태'),
            Tab(icon: Icon(Icons.bar_chart), text: '통계'),
            Tab(icon: Icon(Icons.list), text: '전적'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStatusTab(),
          _buildStatisticsTab(),
          _buildMatchHistoryTab(),
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
              Container(
                height: 370,
                padding: const EdgeInsets.only(right: 50, top: 50, bottom: 8, left: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: (_rankScoreData!['hourly_data'] as List).length * 70.0 > 300
                      ? (_rankScoreData!['hourly_data'] as List).length * 70.0
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
                              getTitlesWidget: (value, meta) {
                                // maxY는 눈금선 없는데 레이블 표시되어 잘림 - 제외
                                if (value == meta.max) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  '${value.toInt()}위',
                                  style: const TextStyle(fontSize: 9, color: Colors.amber),
                                );
                              },
                            ),
                          ),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 50,
                              getTitlesWidget: (value, meta) {
                                // maxY는 눈금선 없는데 레이블 표시되어 잘림 - 제외
                                if (value == meta.max) {
                                  return const SizedBox.shrink();
                                }
                                return Text(
                                  value.toInt().toString(),
                                  style: const TextStyle(fontSize: 9, color: Colors.blue),
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
                                final data = _rankScoreData!['hourly_data'] as List;
                                final index = value.toInt();
                                if (index >= 0 && index < data.length) {
                                  String time = data[index]['time'] ?? '';
                                  if (time.length > 5) {
                                    time = time.substring(time.length - 5);
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
                        lineBarsData: [
                          LineChartBarData(
                            spots: (_rankScoreData!['hourly_data'] as List).asMap().entries.map((entry) {
                              return FlSpot(
                                entry.key.toDouble(), 
                                (entry.value['rank'] ?? 0).toDouble()
                              );
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
                          ),
                          LineChartBarData(
                            spots: (_rankScoreData!['hourly_data'] as List).asMap().entries.map((entry) {
                              return FlSpot(
                                entry.key.toDouble(), 
                                (entry.value['score'] ?? 0).toDouble()
                              );
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
                        lineTouchData: LineTouchData(
                          enabled: true,
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipItems: (touchedSpots) {
                              return touchedSpots.map((spot) {
                                String label = spot.barIndex == 0 ? '${spot.y.toInt()}위' : spot.y.toInt().toString();
                                return LineTooltipItem(
                                  label,
                                  TextStyle(
                                    color: Colors.white, 
                                    fontWeight: FontWeight.bold,
                                  ),
                                );
                              }).toList();
                            },
                          ),
                        ),
                        minY: 0,
                        maxY: (() {
                          final rankMax = (_rankScoreData!['hourly_data'] as List)
                              .map((e) => (e['rank'] ?? 0) as num)
                              .reduce((a, b) => a > b ? a : b)
                              .toDouble();
                          final scoreMax = (_rankScoreData!['hourly_data'] as List)
                              .map((e) => (e['score'] ?? 0) as num)
                              .reduce((a, b) => a > b ? a : b)
                              .toDouble();
                          return (rankMax > scoreMax ? rankMax : scoreMax) * 1.3;
                        })(),
                      ),
                    ),
                    // 순위 수치 표시 (amber)
                    ...(_rankScoreData!['hourly_data'] as List).asMap().entries.map((entry) {
                      final rank = entry.value['rank'] ?? 0;
                      final maxValue = (() {
                        final rankMax = (_rankScoreData!['hourly_data'] as List)
                            .map((e) => (e['rank'] ?? 0) as num)
                            .reduce((a, b) => a > b ? a : b)
                            .toDouble();
                        final scoreMax = (_rankScoreData!['hourly_data'] as List)
                            .map((e) => (e['score'] ?? 0) as num)
                            .reduce((a, b) => a > b ? a : b)
                            .toDouble();
                        return (rankMax > scoreMax ? rankMax : scoreMax) * 1.3;
                      })();
                      final chartHeight = 280.0;
                      final yRatio = rank / maxValue;
                      final yPos = 50 + (chartHeight * (1 - yRatio));
                      final dataCount = (_rankScoreData!['hourly_data'] as List).length;
                      final chartWidth = dataCount * 70.0 > 300 ? dataCount * 70.0 : 300.0;
                      final pointSpacing = (chartWidth - 50 - 50 - 8) / (dataCount > 1 ? dataCount - 1 : 1);
                      final xPos = 50 + 8 + (entry.key * pointSpacing);
                      
                      return Positioned(
                        left: xPos - 10,
                        top: yPos - 25,
                        child: Text(
                          '$rank',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                          ),
                        ),
                      );
                    }).toList(),
                    // 점수 수치 표시 (blue)
                    ...(_rankScoreData!['hourly_data'] as List).asMap().entries.map((entry) {
                      final score = entry.value['score'] ?? 0;
                      final maxValue = (() {
                        final rankMax = (_rankScoreData!['hourly_data'] as List)
                            .map((e) => (e['rank'] ?? 0) as num)
                            .reduce((a, b) => a > b ? a : b)
                            .toDouble();
                        final scoreMax = (_rankScoreData!['hourly_data'] as List)
                            .map((e) => (e['score'] ?? 0) as num)
                            .reduce((a, b) => a > b ? a : b)
                            .toDouble();
                        return (rankMax > scoreMax ? rankMax : scoreMax) * 1.3;
                      })();
                      final chartHeight = 280.0;
                      final yRatio = score / maxValue;
                      final yPos = 50 + (chartHeight * (1 - yRatio));
                      final dataCount = (_rankScoreData!['hourly_data'] as List).length;
                      final chartWidth = dataCount * 70.0 > 300 ? dataCount * 70.0 : 300.0;
                      final pointSpacing = (chartWidth - 50 - 50 - 8) / (dataCount > 1 ? dataCount - 1 : 1);
                      final xPos = 50 + 8 + (entry.key * pointSpacing);
                      
                      return Positioned(
                        left: xPos - 10,
                        top: yPos + 4,
                        child: Text(
                          '$score',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      );
                    }).toList(),
                      ],
                    ),
                  ),
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
                  _buildFilterButton('전체', 'all', _matchMode, (value) {
                    setState(() { _matchMode = value; });
                    _loadMatchHistory();
                  }),
                  _buildFilterButton('감독모드', 'manager_mode', _matchMode, (value) {
                    setState(() { _matchMode = value; });
                    _loadMatchHistory();
                  }),
                  _buildFilterButton('리그', 'league', _matchMode, (value) {
                    setState(() { _matchMode = value; });
                    _loadMatchHistory();
                  }),
                  _buildFilterButton('승급전', 'promotion', _matchMode, (value) {
                    setState(() { _matchMode = value; });
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
                    setState(() { _matchResult = value; });
                    _loadMatchHistory();
                  }),
                  _buildFilterButton('승', 'win', _matchResult, (value) {
                    setState(() { _matchResult = value; });
                    _loadMatchHistory();
                  }),
                  _buildFilterButton('무', 'draw', _matchResult, (value) {
                    setState(() { _matchResult = value; });
                    _loadMatchHistory();
                  }),
                  _buildFilterButton('패', 'lose', _matchResult, (value) {
                    setState(() { _matchResult = value; });
                    _loadMatchHistory();
                  }),
                  _buildFilterButton('오류', 'error', _matchResult, (value) {
                    setState(() { _matchResult = value; });
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
                  _buildPeriodButton('7일', '7', _matchHistoryPeriod, (value) {
                    setState(() {
                      _matchHistoryPeriod = value;
                      _showMatchHistoryDatePicker = false;
                    });
                    _loadMatchHistory();
                  }),
                  _buildPeriodButton('30일', '30', _matchHistoryPeriod, (value) {
                    setState(() {
                      _matchHistoryPeriod = value;
                      _showMatchHistoryDatePicker = false;
                    });
                    _loadMatchHistory();
                  }),
                  _buildPeriodButton('기간 선택', 'custom', _matchHistoryPeriod, (value) {
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
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _matchHistory.length,
                  itemBuilder: (context, index) {
                    final match = _matchHistory[index];
                    return _buildMatchCard(match);
                  },
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
}
