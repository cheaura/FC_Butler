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
