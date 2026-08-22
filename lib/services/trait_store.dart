import 'player_meta_store.dart';

/// 신규특성 캐시 — 시즌 카드(spid) 단위, 앱 전역 공유.
///
/// 2026-08-22 (스쿼드 B안): 실제 저장소는 [PlayerMetaStore](sqflite 영구 캐시 + 서버 묶음 API).
/// 구 구현은 `success:false`를 빈 특성으로 영구 캐시해 레이트리밋 초과 시 신규특성이
/// 사라지는 버그가 있었다 — 이제 실패 응답은 캐시하지 않고 다음 진입 때 재시도한다.
/// 기존 호출부(squad_tab·search_tab·match_detail·player_field_card) 호환을 위해 API 유지.
class TraitStore {
  /// 캐시된 신규특성 목록 (미조회면 null, 조회 후 없으면 빈 목록)
  static List<Map<String, dynamic>>? cached(num? spid) =>
      PlayerMetaStore.cachedNewTraits(spid);

  /// 조회 보장 — 완료 시 Future 완료 (위젯에서 then(setState)로 반영)
  static Future<void> ensure(num? spid) => PlayerMetaStore.ensure(spid);

  /// 여러 카드를 한 번에 (스쿼드·라인업 11명 → 서버 호출 1회)
  static Future<void> ensureAll(Iterable<num?> spids) =>
      PlayerMetaStore.ensureAll(spids);
}
