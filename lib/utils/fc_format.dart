/// 5줄 포메이션("4-1-2-3-0")을 넥슨 표기("4-1-2-3")로 — 0인 줄 생략 (2026-09-07 공용화).
/// 서버 랭커 스냅샷 키·유저 스쿼드 formation5는 5줄 원형이라 표시 시점에만 정규화한다.
/// 필터 값(서버 키)은 원형을 유지해야 하므로 이 함수는 표시에만 쓸 것.
String fmtFormation(dynamic form) {
  if (form == null) return '';
  return form.toString().split('-').where((x) => x.isNotEmpty && x != '0').join('-');
}

/// 천 단위 쉼표 (FC 채굴량 등 정수 표기, 2026-09-20). 숫자가 아니면 원문 그대로.
String fmtThousands(dynamic v) {
  final n = v is num ? v.round() : int.tryParse('${v ?? ''}');
  if (n == null) return '${v ?? '-'}';
  final s = n.abs().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  return n < 0 ? '-$s' : s;
}

/// FC온라인 BP 금액 표기 (경/조/억 단위 축약)
String formatBp(num? v) {
  if (v == null) return '-';
  final n = v.toInt();
  if (n >= 10000000000000000) {
    final gyeong = n ~/ 10000000000000000;
    final jo = (n % 10000000000000000) ~/ 1000000000000;
    return jo > 0 ? '$gyeong경 ${jo}조' : '$gyeong경';
  }
  if (n >= 1000000000000) {
    final jo = n ~/ 1000000000000;
    final eok = (n % 1000000000000) ~/ 100000000;
    return eok > 0 ? '$jo조 ${eok}억' : '$jo조';
  }
  // 2026-08-20 BP 1억:1 축소 이후 시세가 수천만~수억 단위라 억 아래 만 단위까지 표기
  if (n >= 100000000) {
    final eok = n ~/ 100000000;
    final man = (n % 100000000) ~/ 10000;
    return man > 0 ? '$eok억 ${man}만' : '$eok억';
  }
  if (n >= 10000) return '${n ~/ 10000}만';
  return '$n';
}
