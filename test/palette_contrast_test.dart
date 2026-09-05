import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fc_macro_app/providers/theme_provider.dart';

/// 색상 프리셋 7종 × 다크/라이트 + 직접 만들기 전체 조합(띠 12 × 강조 12 × 승패 6 × 2모드)
/// — "글자가 안 보이는 조합이 절대 없어야" 조건 자동 검사.
/// 글자용 색은 바탕 대비 4.5:1(WCAG AA), 큰 요소·테두리는 3:1 이상이어야 통과.
void checkTokens(String name, PanenkaTokens t) {
  void textOn(String what, Color ink, Color bg, [double min = 4.5]) {
    final c = panenkaContrast(ink, bg);
    expect(c, greaterThanOrEqualTo(min),
        reason:
            '$name / $what: ${ink.value.toRadixString(16)} on ${bg.value.toRadixString(16)} = ${c.toStringAsFixed(2)}');
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
}

void main() {
  test('프리셋은 7종이고 id가 겹치지 않는다', () {
    expect(kPanenkaPresets.length, 7);
    expect(kPanenkaPresets.map((p) => p.id).toSet().length, 7);
    expect(kPanenkaPresets.any((p) => p.id == 'custom'), isFalse);
  });

  for (final p in kPanenkaPresets) {
    for (final mode in ['dark', 'light']) {
      final t = mode == 'dark' ? PanenkaTokens.dark(p) : PanenkaTokens.light(p);
      test('${p.name} / $mode 대비 검사', () => checkTokens('${p.name}/$mode', t));
    }
  }

  // 직접 만들기: 칩으로 만들 수 있는 모든 조합 (12 × 12 × 6 = 864) × 다크/라이트
  for (final band in kPanenkaHueChips) {
    for (final accent in kPanenkaHueChips) {
      test('직접 만들기 띠 $band° · 강조 $accent° (승패 6짝 × 2모드)', () {
        for (var i = 0; i < kPanenkaWinLosePairs.length; i++) {
          final spec = PanenkaCustomSpec(
              bandHue: band, accentHue: accent, pairIndex: i);
          final p = spec.toPreset();
          expect(p.id, 'custom');
          checkTokens('custom b$band a$accent p$i/dark', PanenkaTokens.dark(p));
          checkTokens('custom b$band a$accent p$i/light', PanenkaTokens.light(p));
        }
      });
    }
  }

  test('직접 만들기 저장값 왕복·깨진 값 처리', () {
    const spec = PanenkaCustomSpec(bandHue: 210, accentHue: 30, pairIndex: 3);
    final back = PanenkaCustomSpec.fromJson(spec.toJson());
    expect(back, isNotNull);
    expect(back!.bandHue, 210);
    expect(back.accentHue, 30);
    expect(back.pairIndex, 3);
    // 칩에 없는 색조는 가장 가까운 칩으로, 범위 밖 짝 번호는 마지막 짝으로
    final snapped =
        PanenkaCustomSpec.fromJson({'band': 217.0, 'accent': 359.0, 'pair': 99});
    expect(snapped!.bandHue, 210);
    expect(snapped.accentHue, 0);
    expect(snapped.pairIndex, kPanenkaWinLosePairs.length - 1);
    expect(PanenkaCustomSpec.fromJson('garbage'), isNull);
    expect(PanenkaCustomSpec.fromJson({'band': 'x'}), isNull);
  });

  test('프리셋에서 직접 만들기 시작값은 가장 가까운 칩', () {
    final purple = kPanenkaPresets.first;
    final spec = PanenkaCustomSpec.fromPreset(purple);
    expect(kPanenkaHueChips.contains(spec.bandHue), isTrue);
    expect(kPanenkaHueChips.contains(spec.accentHue), isTrue);
    expect(spec.pairIndex, inInclusiveRange(0, kPanenkaWinLosePairs.length - 1));
  });
}
