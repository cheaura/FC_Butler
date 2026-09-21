/// 선수 카드의 양발 스탯 (2026-09-21).
///
/// 서버 `player-bulk`·스쿼드 동봉 메타의 `foot` 객체 `{pref: 'L'|'R', left: n, right: n}`.
/// 주발은 항상 5, 약발은 1~5. 표기는 축약 `L5 R4`(사용자 선택, 주발 쪽 굵게).
class FootStat {
  const FootStat({required this.prefIsLeft, required this.left, required this.right});

  /// 주발이 왼발이면 true
  final bool prefIsLeft;
  final int left;
  final int right;

  /// 서버 foot 객체 → FootStat. 형식이 어긋나면 null (표시 안 함).
  static FootStat? fromJson(dynamic j) {
    if (j is! Map) return null;
    final pref = j['pref']?.toString();
    final l = _toInt(j['left']);
    final r = _toInt(j['right']);
    if ((pref != 'L' && pref != 'R') || l == null || r == null) return null;
    if (l < 1 || l > 5 || r < 1 || r > 5) return null;
    return FootStat(prefIsLeft: pref == 'L', left: l, right: r);
  }

  static int? _toInt(dynamic v) => v is int ? v : int.tryParse('$v');

  /// 왼발 표기 (예: L5)
  String get leftLabel => 'L$left';

  /// 오른발 표기 (예: R4)
  String get rightLabel => 'R$right';

  /// 축약 표기 한 줄 (예: 'L5 R4') — 강조 없는 순수 문자열
  String get label => '$leftLabel $rightLabel';

  /// 길게 누르기 안내 문구
  String get description => '양발: 왼발 $left · 오른발 $right (주발 ${prefIsLeft ? '왼발' : '오른발'})';
}
