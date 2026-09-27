/// 선수 카드의 공격/수비 참여도 (2026-09-28).
///
/// 서버 `player-bulk`·스쿼드 동봉 메타의 `workrate` 객체 `{att: 1~3, def: 1~3}` (높음 3·중간 2·낮음 1).
/// 출처는 fifaaddict 수집분 — 아직 수집·짝짓기 안 된 카드는 서버가 키를 생략한다.
class WorkRate {
  const WorkRate({required this.att, required this.def});

  final int att;
  final int def;

  static WorkRate? fromJson(dynamic j) {
    if (j is! Map) return null;
    final a = _toInt(j['att']);
    final d = _toInt(j['def']);
    if (a == null || d == null || a < 1 || a > 3 || d < 1 || d > 3) return null;
    return WorkRate(att: a, def: d);
  }

  static int? _toInt(dynamic v) => v is int ? v : int.tryParse('$v');

  static const _labels = {3: '높음', 2: '중간', 1: '낮음'};

  /// 길게 누르기 안내 문구
  String get description => '공격 참여도 ${_labels[att]} · 수비 참여도 ${_labels[def]}';
}
