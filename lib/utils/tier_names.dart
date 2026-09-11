/// 티어(등급) 명칭 — 넥슨 아이콘 번호(ico_rank0~20) 순서와 동일 (2026-09-11 공용화).
///
/// 서버 감독 검색 응답의 `tier` 텍스트는 과거 9칸 표 때문에 마스터 등급을 '월드클래스 N부'로 내려준 적이 있어
/// (땅화리 09-11 제보), 앱은 `tier_icon` 주소의 아이콘 번호에서 명칭을 다시 계산한다.
/// 기기에 저장된 최근 검색(옛 텍스트)도 이 함수로 표시 시점에 바로잡힌다.
const List<String> kTierOrder = [
  '슈퍼 챔피언스', '챔피언스', '슈퍼 챌린지',
  '챌린저1', '챌린저2', '챌린저3',
  '마스터1', '마스터2', '마스터3',
  '월드클래스1', '월드클래스2', '월드클래스3',
  '프로1', '프로2', '프로3',
  '세미프로1', '세미프로2', '세미프로3',
  '유망주1', '유망주2', '유망주3',
];

final RegExp _kIconIdxRe = RegExp(r'ico_rank(\d+)');

/// 티어 아이콘 URL(…/ico_rank6_m.png)에서 등급명을 구한다. 해석 불가면 null.
String? tierNameFromIconUrl(dynamic iconUrl) {
  final url = iconUrl?.toString() ?? '';
  if (url.isEmpty) return null;
  final m = _kIconIdxRe.firstMatch(url.split('/').last);
  if (m == null) return null;
  final idx = int.tryParse(m.group(1) ?? '');
  if (idx == null || idx < 0 || idx >= kTierOrder.length) return null;
  return kTierOrder[idx];
}

/// 표시용 등급명: 아이콘에서 계산한 값을 우선, 없으면 서버/저장 텍스트.
String tierLabel(dynamic tierText, dynamic iconUrl) =>
    tierNameFromIconUrl(iconUrl) ?? (tierText?.toString() ?? '');
