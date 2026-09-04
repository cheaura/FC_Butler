import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';
import '../constants/legal_texts.dart';
import '../services/api_service.dart';
import 'public_home_screen.dart';

/// 공개 회원가입 화면 — 즉시 활성(승인 불필요), 조회 계정(public).
/// 스토어 정책 준수: 개인정보 수집·이용 동의 필수, 인앱 계정 삭제 제공(공개 홈 계정 메뉴).
class SignupScreen extends StatefulWidget {
  const SignupScreen({Key? key}) : super(key: key);

  @override
  _SignupScreenState createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _password2Controller = TextEditingController();
  final _apiService = ApiService();
  bool _isLoading = false;
  bool _agreeTerms = false;
  bool _obscurePassword = true;
  String? _errorMessage;


  String? _validate() {
    final username = _usernameController.text.trim();
    final pw = _passwordController.text;
    final usernameRe = RegExp(r'^[A-Za-z0-9가-힣_]{2,20}$');
    if (!usernameRe.hasMatch(username)) {
      return '아이디는 한글/영문/숫자/밑줄 2~20자로 입력해주세요.';
    }
    if (pw.length < 8 || pw.length > 64) {
      return '비밀번호는 8~64자여야 합니다.';
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(pw) || !RegExp(r'[0-9]').hasMatch(pw)) {
      return '비밀번호는 영문과 숫자를 각각 1자 이상 포함해야 합니다.';
    }
    if (pw != _password2Controller.text) {
      return '비밀번호 확인이 일치하지 않습니다.';
    }
    if (!_agreeTerms) {
      return '이용약관 및 개인정보 수집·이용에 동의해주세요.';
    }
    return null;
  }

  Future<void> _signup() async {
    final err = _validate();
    if (err != null) {
      setState(() => _errorMessage = err);
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _apiService.register(
      _usernameController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const PublicHomeScreen()),
        (route) => false,
      );
    } else {
      setState(() => _errorMessage = result['message']);
    }
  }

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

  InputDecoration _fieldDecoration(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: Icon(icon, color: Colors.white70),
      suffixIcon: suffix,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white30),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white),
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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_add, size: 64, color: Colors.white),
                  const SizedBox(height: 24),
                  const Text(
                    '회원가입',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '가입하면 즐겨찾는 감독 조회 기록 등\n맞춤 기능을 사용할 수 있습니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _usernameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: _fieldDecoration('아이디 (2~20자)', Icons.person),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: const TextStyle(color: Colors.white),
                    decoration: _fieldDecoration(
                      '비밀번호 (8자 이상, 영문+숫자)',
                      Icons.lock,
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.white70,
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _password2Controller,
                    obscureText: _obscurePassword,
                    style: const TextStyle(color: Colors.white),
                    decoration: _fieldDecoration('비밀번호 확인', Icons.lock_outline),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: _agreeTerms,
                        onChanged: (v) =>
                            setState(() => _agreeTerms = v ?? false),
                        fillColor: MaterialStateProperty.resolveWith((states) {
                          if (states.contains(MaterialState.selected)) {
                            return Colors.white;
                          }
                          return Colors.white30;
                        }),
                        checkColor: Colors.blue,
                      ),
                      const Expanded(
                        child: Text(
                          '이용약관 및 개인정보 수집·이용에 동의합니다. (필수)',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () =>
                            _showDocument('이용약관', kTermsOfService),
                        child: const Text('이용약관 보기',
                            style:
                                TextStyle(color: Colors.white, fontSize: 13)),
                      ),
                      const Text('·',
                          style: TextStyle(color: Colors.white38)),
                      TextButton(
                        onPressed: () =>
                            _showDocument('개인정보처리방침', kPrivacyPolicy),
                        child: const Text('개인정보처리방침 보기',
                            style:
                                TextStyle(color: Colors.white, fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red),
                      ),
                      child: Text(_errorMessage!,
                          style: const TextStyle(color: Colors.white)),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _signup,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator()
                          : Text(
                              '가입하기',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: PanenkaTokens.of(context).accentInk),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('돌아가기',
                        style: TextStyle(color: Colors.white70)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _password2Controller.dispose();
    super.dispose();
  }
}
