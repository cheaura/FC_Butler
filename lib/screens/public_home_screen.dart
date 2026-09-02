import 'training_calc_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../widgets/home_tab.dart';
import '../widgets/market_tab.dart';
import '../widgets/pill_nav_bar.dart';
import '../widgets/more_tab.dart';
import '../widgets/ranking_tab.dart';
import '../widgets/search_tab.dart';
import '../widgets/squad_tab.dart';
import 'dashboard_screen.dart';

/// 앱 탭 셸 (사용자 확정 구조):
/// - 게스트·일반 회원: 홈 / 검색 / 랭킹 / 스쿼드 / 집훈 / 이적시장 / 더보기 (7탭)
/// - 매크로 연동 계정: + 모니터 탭 (8탭, 로그인 직후 모니터 탭에서 시작)
/// 홈은 허브 — 타일을 누르면 해당 탭으로 이동. 모니터 탭(구 '매크로', 2026-09-03
/// 스크린샷 유출 대비 명칭·아이콘 중립화 + 맨 우측 이동)은 기존 DashboardScreen을
/// 그대로 임베드 — 기능·표현 전부 유지, 색만 테마 적용.
class PublicHomeScreen extends StatefulWidget {
  /// 시작 탭 인덱스 (매크로 계정 자동로그인 시 모니터 탭)
  final int? initialIndex;
  const PublicHomeScreen({Key? key, this.initialIndex}) : super(key: key);

  /// 모니터(매크로) 탭 인덱스 (main.dart·login_screen 라우팅에서 사용)
  static const int macroTabIndex = 7; // 2026-09-03: 맨 우측(더보기 뒤)으로 이동

  @override
  _PublicHomeScreenState createState() => _PublicHomeScreenState();
}

class _PublicHomeScreenState extends State<PublicHomeScreen> {
  final _apiService = ApiService();
  final _searchRequest = ValueNotifier<SearchRequest?>(null);
  late final PageController _pageController;
  int _tabIndex = 0;
  DateTime? _lastBackPressed; // 뒤로가기 2회 종료 판정

  bool get _isMacro => _apiService.isLoggedIn && _apiService.isMacroAccount;
  int get _maxIndex => _isMacro ? 7 : 6;

  @override
  void initState() {
    super.initState();
    _tabIndex = (widget.initialIndex ?? 0).clamp(0, _maxIndex);
    _pageController = PageController(initialPage: _tabIndex);
  }

  void _selectTab(int index) {
    setState(() => _tabIndex = index);
    _pageController.animateToPage(index,
        duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  void _goTab(String dest) {
    switch (dest) {
      case 'search':
        _selectTab(1);
        break;
      case 'ranking':
        _selectTab(2);
        break;
      case 'squad':
        _selectTab(3);
        break;
      case 'training':
        _selectTab(4);
        break;
      case 'market':
        _selectTab(5);
        break;
      case 'more':
        _selectTab(6); // 더보기 고정 인덱스 (모니터 탭이 맨 우측이라 _maxIndex 아님)
        break;
    }
  }

  // 홈 최근 감독 탭 → 검색 탭으로 이동 + 즉시 검색
  void _requestSearch(String name, String mode) {
    _selectTab(1);
    _searchRequest.value = SearchRequest(name, mode);
  }

  // 로그인/로그아웃/탈퇴로 계정 유형이 바뀌면 탭 구성이 달라짐 (6탭 ↔ 7탭)
  void _onAccountChanged() {
    setState(() {
      if (_tabIndex > _maxIndex) _tabIndex = _maxIndex;
      // 매크로 계정 로그인 직후에는 매크로 탭으로
      if (_isMacro) _tabIndex = PublicHomeScreen.macroTabIndex;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_tabIndex);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMacro = _isMacro;
    final children = <Widget>[
      HomeTab(onNavigate: _goTab, onSearch: _requestSearch),
      SearchTab(requestNotifier: _searchRequest),
      const RankingTab(),
      const SquadTab(),
      const TrainingCalcScreen(asTab: true), // 1.0.4 집훈 계산기 (공개 탭)
      const MarketTab(),
      MoreTab(onAccountChanged: _onAccountChanged),
      // 모니터(매크로) 탭 — 맨 우측 (2026-09-03: 스크린샷 유출 대비 명칭·아이콘 중립화)
      if (isMacro)
        DashboardScreen(
          username: _apiService.username ?? '',
          apiService: _apiService,
        ),
    ];
    final items = <PillBarItem>[
      const PillBarItem(Icons.grid_view_rounded, '홈'),
      const PillBarItem(Icons.search, '검색'),
      const PillBarItem(Icons.leaderboard, '랭킹'),
      const PillBarItem(Icons.groups, '스쿼드'),
      const PillBarItem(Icons.fitness_center, '집훈'),
      const PillBarItem(Icons.storefront, '이적시장'),
      const PillBarItem(Icons.more_horiz, '더보기'),
      if (isMacro) const PillBarItem(Icons.query_stats, '모니터'),
    ];
    final index = _tabIndex.clamp(0, children.length - 1);

    // 안드로이드 뒤로가기: 다른 탭이면 홈으로, 홈에서는 2초 내 2회 누르면 종료
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_tabIndex != 0) {
          _selectTab(0);
          return;
        }
        final now = DateTime.now();
        if (_lastBackPressed == null ||
            now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
          _lastBackPressed = now;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('뒤로 버튼을 한 번 더 누르면 앱이 종료됩니다.'),
              duration: Duration(seconds: 2)));
          return;
        }
        SystemNavigator.pop();
      },
      child: Scaffold(
      // SafeArea: 상단 상태바(시계·배터리) 침범 방지 (사용자 지적)
      body: SafeArea(
        bottom: false,
        child: PageView(
          controller: _pageController,
          onPageChanged: (i) => setState(() => _tabIndex = i),
          children: [
            // 스와이프 중에도 각 탭 상태 유지
            for (final child in children) _KeepAlivePage(child: child),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: PanenkaPillBar(
          items: items,
          selectedIndex: index,
          onSelected: _selectTab,
        ),
      ),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchRequest.dispose();
    super.dispose();
  }
}

/// PageView 안에서 탭 상태(스크롤·입력·매크로 화면 소켓 등)를 유지하는 래퍼
class _KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _KeepAlivePage({Key? key, required this.child}) : super(key: key);

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
