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
  if (n >= 100000000) return '${n ~/ 100000000}억';
  if (n >= 10000) return '${n ~/ 10000}만';
  return '$n';
}
