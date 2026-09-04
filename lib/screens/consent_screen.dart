import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/legal_texts.dart';
import '../widgets/panenka_logo.dart';

/// 최초 실행 시 이용약관·개인정보처리방침 동의 화면.
/// 약관은 회원가입 여부와 무관하게 모든 이용자에게 적용되므로(약관 제2조)
/// 게스트 포함 최초 1회 동의를 받는다. 동의 후 [next] 화면으로 교체 이동.
class ConsentScreen extends StatefulWidget {
  final Widget next;
  const ConsentScreen({Key? key, required this.next}) : super(key: key);

  /// 동의 저장 키 — 약관 개정으로 재동의가 필요하면 버전 숫자를 올릴 것
  static const String prefsKey = 'legal_consent_v1';

  static Future<bool> isAgreed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(prefsKey) ?? false;
    } catch (e) {
      // 저장소 오류 시 동의 화면을 다시 보여주는 쪽이 안전
      return false;
    }
  }

  @override
  _ConsentScreenState createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _isSaving = false;

  void _showDocument(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(content, style: const TextStyle(fontSize: 13)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Future<void> _agree() async {
    setState(() => _isSaving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(ConsentScreen.prefsKey, true);
    } catch (e) {
      print('[ConsentScreen] 동의 저장 실패: $e');
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => widget.next),
    );
  }

  Widget _docTile(String title, String content) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: ListTile(
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        trailing:
            const Icon(Icons.chevron_right, color: Colors.white70, size: 20),
        onTap: () => _showDocument(title, content),
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
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                const Spacer(),
                const PanenkaLogo(size: 64),
                const SizedBox(height: 16),
                const Text(
                  'Panenka 서비스 이용 동의',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 8),
                const Text(
                  '서비스를 이용하려면 아래 약관과 방침에 동의가 필요합니다.\n각 항목을 눌러 전문을 확인할 수 있습니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 28),
                _docTile('이용약관', kTermsOfService),
                _docTile('개인정보처리방침', kPrivacyPolicy),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _agree,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator()
                        : Text(
                            '모두 동의하고 시작하기',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: PanenkaTokens.of(context).accentInk),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
