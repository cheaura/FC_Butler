import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/error_reporter.dart';

/// 버그 제보·건의 — Panenka 1.0.4 (2026-08-22). 글만 보냄(사진 없음), 기기·버전·화면·계정은 자동 첨부.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  String _kind = 'bug';
  final _ctrl = TextEditingController();
  bool _sending = false;

  static const _kinds = [
    ('bug', '버그'),
    ('idea', '건의'),
    ('etc', '기타'),
  ];

  @override
  void initState() {
    super.initState();
    ErrorReporter.currentScreen = '버그 제보';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final msg = _ctrl.text.trim();
    if (msg.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('내용을 조금 더 적어주세요 (5자 이상).')));
      return;
    }
    setState(() => _sending = true);
    final ok = await ErrorReporter.sendFeedback(kind: _kind, message: msg);
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('접수됐습니다. 감사합니다.')));
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('전송에 실패했습니다. 잠시 후 다시 시도해주세요.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = Colors.grey.shade500;
    final username = ApiService().username;
    final auto = [
      'Panenka ${ErrorReporter.appVersion}${ErrorReporter.build.isNotEmpty ? ' (${ErrorReporter.build})' : ''}',
      if (ErrorReporter.device.isNotEmpty) ErrorReporter.device,
      if (ErrorReporter.os.isNotEmpty) ErrorReporter.os,
      '계정: ${username ?? '비로그인'}',
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(title: const Text('버그 제보·건의')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final k in _kinds)
                ChoiceChip(
                  label: Text(k.$2),
                  selected: _kind == k.$1,
                  onSelected: (_) => setState(() => _kind = k.$1),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            maxLines: 8,
            maxLength: 2000,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: '어떤 화면에서 무엇을 했을 때 어떻게 됐는지 적어주세요.\n예) 스쿼드 탭에서 유저 스쿼드 불러오기 하면 두 명이 비어요',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Text('자동으로 함께 보내는 정보', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: muted)),
          const SizedBox(height: 2),
          Text(auto, style: TextStyle(fontSize: 12, color: muted)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _sending ? null : _send,
            style:
                FilledButton.styleFrom(backgroundColor: cs.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: _sending
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('보내기', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 10),
          Text('답장은 드리지 않지만 모두 읽고 다음 업데이트에 반영합니다. 사진은 받지 않습니다.', style: TextStyle(fontSize: 11.5, color: muted)),
        ],
      ),
    );
  }
}
