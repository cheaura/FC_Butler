import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

/// 신규특성 캐시 — 시즌 카드(spid) 단위, 앱 전역 공유 (웹 squad.js traitsCache 이식).
/// 같은 선수라도 시즌 카드마다 특성이 다르므로 spid 단위로 조회·캐시한다.
class TraitStore {
  static final Map<String, List<Map<String, dynamic>>> _cache = {};
  static final Map<String, Future<void>> _pending = {};

  /// 캐시된 신규특성 목록 (미조회면 null, 조회 후 없으면 빈 목록)
  static List<Map<String, dynamic>>? cached(num? spid) =>
      spid == null ? null : _cache['${spid.toInt()}'];

  /// 조회 보장 — 완료 시 Future 완료 (위젯에서 then(setState)로 반영)
  static Future<void> ensure(num? spid) {
    if (spid == null) return Future.value();
    final key = '${spid.toInt()}';
    if (_cache.containsKey(key)) return Future.value();
    return _pending.putIfAbsent(key, () async {
      try {
        final r = await http
            .get(Uri.parse(
                '${ApiService.baseUrl}/api/user/squad/traits?spid=$key'))
            .timeout(const Duration(seconds: 20));
        final d = json.decode(r.body);
        _cache[key] = (d['success'] == true)
            ? (d['traits'] as List? ?? [])
                .where((t) => t is Map && t['is_new'] == true)
                .map((t) => Map<String, dynamic>.from(t as Map))
                .toList()
            : <Map<String, dynamic>>[];
      } catch (_) {
        // 실패 시 캐시하지 않음 — 다음 진입 때 재시도
      } finally {
        _pending.remove(key);
      }
    });
  }
}
