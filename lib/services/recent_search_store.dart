import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 최근 검색 저장소 (홈 탭 타일·검색 화면 공용).
/// 검색 성공 당시의 티어·티어 로고를 함께 보존한다 (사용자 요구).
class RecentSearchStore {
  static const _key = 'recent_searches_v1';
  static const _max = 10;

  static Future<List<Map<String, dynamic>>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      return (json.decode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      print('[RecentSearchStore] 로드 실패: $e');
      return [];
    }
  }

  static Future<void> _save(List<Map<String, dynamic>> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, json.encode(list));
    } catch (e) {
      print('[RecentSearchStore] 저장 실패: $e');
    }
  }

  /// 검색 성공 시 호출 — 같은 이름+모드는 최신 검색(당시 티어)으로 교체
  static Future<List<Map<String, dynamic>>> add(
      String name, String mode, Map<String, dynamic> data) async {
    final list = await load();
    list.removeWhere((r) => r['name'] == name && r['mode'] == mode);
    list.insert(0, {
      'name': name,
      'mode': mode,
      'tier': data['tier']?.toString() ?? '',
      'tier_icon': data['tier_icon']?.toString() ?? '',
      'rank': data['rank']?.toString() ?? '',
    });
    final trimmed = list.length > _max ? list.sublist(0, _max) : list;
    await _save(trimmed);
    return trimmed;
  }

  static Future<List<Map<String, dynamic>>> removeAt(int index) async {
    final list = await load();
    if (index >= 0 && index < list.length) list.removeAt(index);
    await _save(list);
    return list;
  }
}
