import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fc_macro_app/providers/theme_provider.dart';

/// 색상 프리셋 6종 × 다크/라이트 — "글자가 안 보이는 조합이 절대 없어야" 조건 자동 검사.
/// 글자용 색은 바탕 대비 4.5:1(WCAG AA), 큰 요소·테두리는 3:1 이상이어야 통과.
void main() {
  for (final p in kPanenkaPresets) {
    for (final mode in ['dark', 'light']) {
      final t = mode == 'dark' ? PanenkaTokens.dark(p) : PanenkaTokens.light(p);
      test('${p.name} / $mode 대비 검사', () {
        void textOn(String what, Color ink, Color bg, [double min = 4.5]) {
          final c = panenkaContrast(ink, bg);
          expect(c, greaterThanOrEqualTo(min),
              reason: '$what: ${ink.value.toRadixString(16)} on ${bg.value.toRadixString(16)} = ${c.toStringAsFixed(2)}');
        }
        // 카드 위 글자
        textOn('본문 글자', t.ink, t.card);
        textOn('보조 글자', t.mute, t.card, 3.0);
        textOn('강조 글자(경기 중·상대 점수)', t.accentInk, t.card);
        textOn('승 글자', t.winInk, t.card);
        textOn('패 글자', t.loseInk, t.card);
        textOn('보조 아이콘', t.subInk, t.card, 3.0);
        textOn('경기 중 띠 글자', t.accentInk, t.liveBg, 3.0);
        // 바탕 위 글자 (카드 밖)
        textOn('본문 글자(바탕)', t.ink, t.bg);
        // 띠 위 글자
        textOn('띠 위 글자', t.bandInk, t.band);
        textOn('띠 위 강조(선택 탭)', t.accentBand, t.band, 3.0);
        textOn('일시정지 글자', t.win, t.band, 3.0);
        // 채움 위 글자
        textOn('승 배지 글자', t.onWin, t.win);
        textOn('패 배지 글자', Colors.white, t.lose, 3.0);
        textOn('시작 버튼 글자', t.onAccentInk, t.accentInk);
      });
    }
  }
}
