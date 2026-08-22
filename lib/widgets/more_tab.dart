import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/legal_texts.dart';
import '../providers/theme_provider.dart';
import '../screens/login_screen.dart';
import '../screens/signup_screen.dart';
import '../services/api_service.dart';

/// 더보기 탭 — 계정(로그인/로그아웃/계정삭제) · 테마 · 약관/방침 · 앱 정보 · 고지 문구.
class MoreTab extends StatefulWidget {
  /// 로그인/로그아웃으로 계정 상태가 바뀌었을 때 부모(탭 셸) 갱신용
  final VoidCallback? onAccountChanged;
  const MoreTab({Key? key, this.onAccountChanged}) : super(key: key);

  @override
  State<MoreTab> createState() => _MoreTabState();
}

class _MoreTabState extends State<MoreTab> {
  final _apiService = ApiService();
  static const String _appVersion = '1.0.2';

  Color get _accent => Theme.of(context).colorScheme.primary;
  Color get _subColor => Colors.grey.shade500;

  Future<void> _logout() async {
    await _apiService.clearAutoLogin();
    if (!mounted) return;
    setState(() {});
    widget.onAccountChanged?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('로그아웃되었습니다.')),
    );
  }

  Future<void> _openLogin() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
    if (!mounted) return;
    setState(() {});
    widget.onAccountChanged?.call();
  }

  Future<void> _confirmDeleteAccount() async {
    final passwordController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('계정 삭제'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '계정과 관련 데이터가 즉시 삭제되며 되돌릴 수 없습니다.\n'
              '계속하려면 비밀번호를 입력하세요.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '비밀번호',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await _apiService.deleteAccount(passwordController.text);
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {});
      widget.onAccountChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('계정이 삭제되었습니다.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? '계정 삭제에 실패했습니다.')),
      );
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

  Widget _menuRow(
      {required IconData icon,
      required String title,
      String? value,
      Widget? trailing,
      VoidCallback? onTap}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, size: 20, color: _accent),
        title: Text(title, style: const TextStyle(fontSize: 14)),
        trailing: trailing ??
            (value != null
                ? Text(value,
                    style: TextStyle(fontSize: 13, color: _subColor))
                : Icon(Icons.chevron_right, size: 18, color: _subColor)),
        onTap: onTap,
        dense: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final loggedIn = _apiService.isLoggedIn;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('더보기',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _accent)),
          const SizedBox(height: 14),
          // 계정 카드
          if (!loggedIn)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: const Text('로그인하고 더 많은 기능 이용하기',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                trailing:
                    Icon(Icons.chevron_right, size: 18, color: _subColor),
                onTap: _openLogin,
              ),
            )
          else
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: _accent,
                      child: Text(
                          (_apiService.username ?? '?')
                              .substring(0, 1)
                              .toUpperCase(),
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_apiService.username ?? '',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                    TextButton(
                        onPressed: _logout, child: const Text('로그아웃')),
                  ],
                ),
              ),
            ),
          if (!loggedIn)
            _menuRow(
              icon: Icons.person_add_alt,
              title: '회원가입',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SignupScreen()),
              ).then((_) {
                setState(() {});
                widget.onAccountChanged?.call();
              }),
            ),
          const SizedBox(height: 8),
          // 설정
          _menuRow(
            icon: themeProvider.isDarkMode
                ? Icons.dark_mode
                : Icons.light_mode,
            title: '테마',
            trailing: Switch(
              value: themeProvider.isDarkMode,
              onChanged: (_) => themeProvider.toggleTheme(),
            ),
          ),
          _menuRow(
            icon: Icons.description_outlined,
            title: '이용약관',
            onTap: () => _showDocument('이용약관', kTermsOfService),
          ),
          _menuRow(
            icon: Icons.privacy_tip_outlined,
            title: '개인정보처리방침',
            onTap: () => _showDocument('개인정보처리방침', kPrivacyPolicy),
          ),
          if (loggedIn)
            _menuRow(
              icon: Icons.delete_outline,
              title: '계정 삭제',
              onTap: _confirmDeleteAccount,
            ),
          _menuRow(
            icon: Icons.info_outline,
            title: '앱 버전',
            value: _appVersion,
            trailing: Text(_appVersion,
                style: TextStyle(fontSize: 13, color: _subColor)),
          ),
          const SizedBox(height: 32),
          // 하단 고지 문구 (스토어 심사·저작권 고지)
          Center(
            child: Text(
              'Panenka는 NEXON Open API를 사용하여 제작되었습니다.\n'
              'Panenka는 EA Sports 및 NEXON과 관련이 없습니다.\n'
              '앱 내 FC온라인 관련 모든 이미지의 저작권은\n'
              'EA Sports 및 NEXON에 있습니다.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: _subColor, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}
