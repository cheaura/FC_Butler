import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/player_query.dart';

/// 관심선수 저장소 (2026-09-30) — 기기에 저장, 최대 20명 (사용자 확정).
///
/// 검색 목록 줄의 정보(이름·시즌·포지션별 OVR·급여·양발·참여도·시세·신규특성)를 그대로 보관해
/// 검색 없이 목록을 그린다. 세부 능력은 상세를 열 때 서버에서 받는다.
class FavoritePlayerStore {
  FavoritePlayerStore._();

  static const max = 20;
  static const _key = 'favorite_players_v1';

  /// 화면 갱신용 — 목록이 바뀌면 값이 바뀐다 (최근 등록이 앞)
  static final ValueNotifier<List<Map<String, dynamic>>> players = ValueNotifier(const []);
  static bool _loaded = false;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        players.value = (json.decode(raw) as List).map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      print('[FavoritePlayerStore] 로드 실패: $e');
    }
  }

  static Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, json.encode(players.value));
    } catch (e) {
      print('[FavoritePlayerStore] 저장 실패: $e');
    }
  }

  static bool contains(num? spid) => spid != null && players.value.any((p) => '${p['spid']}' == '${spid.toInt()}');

  static bool get isFull => players.value.length >= max;

  /// 등록. 가득 차 있으면 false (목록은 그대로).
  static Future<bool> add(Map<String, dynamic> row) async {
    await ensureLoaded();
    if (contains(row['spid'] as num?)) return true;
    if (isFull) return false;
    players.value = [Map<String, dynamic>.from(row), ...players.value];
    await _save();
    return true;
  }

  static Future<void> remove(num? spid) async {
    await ensureLoaded();
    if (spid == null) return;
    players.value = players.value.where((p) => '${p['spid']}' != '${spid.toInt()}').toList();
    await _save();
  }

  /// 시험용 초기화
  @visibleForTesting
  static void resetForTest() {
    _loaded = false;
    players.value = const [];
  }
}

/// 선수 최근 검색 저장소 — 기기에 저장, 최대 8건. 같은 검색은 최신으로 교체.
class PlayerRecentStore {
  PlayerRecentStore._();

  static const max = 8;
  static const _key = 'player_recent_queries_v1';

  static Future<List<PlayerQuery>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      return (json.decode(raw) as List).map(PlayerQuery.fromJson).toList();
    } catch (e) {
      print('[PlayerRecentStore] 로드 실패: $e');
      return [];
    }
  }

  static Future<List<PlayerQuery>> add(PlayerQuery q) async {
    final list = await load();
    list.removeWhere((r) => r.key == q.key);
    list.insert(0, q.copy());
    final trimmed = list.length > max ? list.sublist(0, max) : list;
    await _save(trimmed);
    return trimmed;
  }

  static Future<List<PlayerQuery>> clear() async {
    await _save(const []);
    return [];
  }

  static Future<void> _save(List<PlayerQuery> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, json.encode(list.map((q) => q.toJson()).toList()));
    } catch (e) {
      print('[PlayerRecentStore] 저장 실패: $e');
    }
  }
}
