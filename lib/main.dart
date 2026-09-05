import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'providers/theme_provider.dart';
import 'screens/consent_screen.dart';
import 'screens/public_home_screen.dart';
import 'widgets/panenka_logo.dart';
import 'services/api_service.dart';
import 'services/fcm_service.dart';
import 'services/error_reporter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 오류 자동 기록 (1.0.4): 프레임워크 오류·잡히지 않은 예외를 서버에 남김 (화면에는 표시 없음)
  ErrorReporter.installHandlers();
  await ErrorReporter.init();
  
  try {
    // Firebase 초기화
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    // FCM 초기화 — 기다리지 않는다 (2026-09-05): iOS에서 APNs 토큰 대기(최대 10s)가 runApp을 막아
    // 앱 실행이 20초 넘게 걸리던 문제. 권한 요청·리스너 등록·토큰 발급은 백그라운드에서 이어진다.
    unawaited(FCMService().initialize());
  } catch (e) {
    // Firebase 초기화 실패 시에도 앱은 계속 실행
    print('Firebase/FCM 초기화 오류: $e');
  }
  
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const FCMacroApp(),
    ),
  );
}

class FCMacroApp extends StatelessWidget {
  const FCMacroApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return MaterialApp(
      title: 'Panenka',
      debugShowCheckedModeBanner: false,
      theme: themeProvider.lightTheme,
      darkTheme: themeProvider.darkTheme,
      themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const SplashScreen(),
    );
  }
}

// ===== 스플래시 스크린 (자동로그인 체크) =====
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
  }

  Future<void> _checkAutoLogin() async {
    // 최소 1초 스플래시 표시
    await Future.delayed(Duration(seconds: 1));
    
    final result = await _apiService.checkAutoLogin();
    
    if (!mounted) return;

    Widget target;
    if (result['success'] == true && result['account_type'] == 'macro') {
      // 매크로 연동 계정 - FCM 토큰 전송 후 탭 셸(매크로 탭에서 시작)로
      // 매크로 대시보드는 셸의 매크로 탭에 그대로 임베드 (기능·표현 전부 유지)
      // (2026-09-05) 화면 전환을 막지 않는다 — FCM 토큰이 아직 없으면 발급 완료 시 백그라운드로 전송된다
      final token = _apiService.token;
      if (token != null) {
        unawaited(FCMService().sendTokenToServerWithAuth(token));
      }
      target = const PublicHomeScreen(
          initialIndex: PublicHomeScreen.macroTabIndex);
    } else {
      // 공개 계정 로그인 또는 비로그인(게스트) - 홈 탭으로
      // (조회 기능은 로그인 없이 사용 가능, 로그인/가입은 더보기 탭에서 진입)
      target = const PublicHomeScreen();
    }

    // 최초 실행 시 이용약관·개인정보처리방침 동의 (게스트 포함 전체 이용자)
    final agreed = await ConsentScreen.isAgreed();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) =>
            agreed ? target : ConsentScreen(next: target),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // 브랜드 그라데이션: 프리셋 띠색 → 바탕색 (2026-09-04 색상 프리셋)
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [PanenkaTokens.of(context).band, PanenkaTokens.of(context).bg],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              PanenkaLogo(size: 100),
              SizedBox(height: 24),
              Text(
                'Panenka',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 48),
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
