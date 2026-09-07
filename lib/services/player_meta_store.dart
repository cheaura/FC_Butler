import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'api_service.dart';

/// 선수 카드(spid) 메타·특성 기기 영구 캐시 — 스쿼드 B안 5단계 (2026-08-22).
///
/// 원칙: spid(시즌+선수)는 불변 → 한 번 받으면 재조회 없음(90일 안전망).
/// 서버 `/api/user/squad/player-bulk?spids=`(최대 60) 한 번으로 메타+특성+팀컬러 배지를 받아
/// sqflite에 저장한다. 시세(each_price)는 변동값이라 받은 시각 기준 30분만 신뢰한다.
///
/// 실패 응답(success:false·네트워크 오류)은 절대 캐시하지 않는다 (구 TraitStore 버그 재발 방지).
class PlayerMetaStore {
  PlayerMetaStore._();

  static const _maxAge = Duration(days: 90);
  static const _priceMaxAge = Duration(minutes: 30);

  static Database? _db;
  static final Map<int, Map<String, dynamic>> _mem = {}; // 프로세스 메모리 캐시
  static final Map<int, DateTime> _memAt = {};
  static final Map<int, Future<void>> _pending = {};

  static Future<Database> _open() async {
    if (_db != null) return _db!;
    final path = '${await getDatabasesPath()}/player_meta_v1.db';
    _db = await openDatabase(path, version: 1, onCreate: (db, v) async {
      await db.execute('''
        CREATE TABLE player_meta (
          spid INTEGER PRIMARY KEY,
          json TEXT NOT NULL,
          fetched_at INTEGER NOT NULL
        )''');
    });
    return _db!;
  }

  /// 메모리 캐시에 있는 메타 (없으면 null). 위젯 build에서 동기 접근용.
  static Map<String, dynamic>? cached(num? spid) => spid == null ? null : _mem[spid.toInt()];

  /// 캐시된 신규특성 목록 (is_new만). 미조회면 null, 조회 후 없으면 빈 목록.
  static List<Map<String, dynamic>>? cachedNewTraits(num? spid) {
    final m = cached(spid);
    if (m == null) return null;
    final traits = m['traits'];
    if (traits is! List) return null; // 특성 미확보(서버 상세 실패) → 재시도 대상
    return traits
        .where((t) => t is Map && t['is_new'] == true)
        .map((t) => Map<String, dynamic>.from(t as Map))
        .toList();
  }

  /// 시세 문자열(강화별 '|' 구분). 마지막으로 받은 값을 그대로 돌려준다 (만료 여부는 [priceAt]/[priceStale]로 판단).
  /// 2026-09-07: 30분 지난 값을 버리던 규칙 폐지 — 넥슨 재조회 실패 시 총액이 0으로 무너지지 않도록 마지막 값 유지.
  static String? cachedPrice(num? spid) {
    final m = cached(spid);
    if (m == null) return null;
    final p = m['each_price']?.toString() ?? '';
    return p.isEmpty ? null : p;
  }

  /// 시세를 받은 시각 (서버 price_at 우선). 시세가 없으면 null.
  static DateTime? priceAt(num? spid) {
    final m = cached(spid);
    final ms = m?['_price_at'];
    if (m == null || ms is! int || (m['each_price']?.toString() ?? '').isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// 시세가 30분을 넘었으면 true (없어도 true).
  static bool priceStale(num? spid) {
    final at = priceAt(spid);
    return at == null || DateTime.now().difference(at) > _priceMaxAge;
  }

  /// 서버 응답의 시세 시각(epoch 초) → ms. 없으면 지금.
  static int _priceAtMsOf(Map<String, dynamic> m, DateTime now) {
    final pa = m['price_at'];
    return pa is num ? (pa * 1000).toInt() : now.millisecondsSinceEpoch;
  }

  static bool _complete(Map<String, dynamic> m) => (m['each_ovr']?.toString() ?? '').isNotEmpty && m['traits'] is List;

  /// 여러 spid를 한 번에 확보 (DB → 서버 묶음). 완료 후 cached()로 접근.
  /// [freshPrice]면 30분 지난 시세를 서버에 다시 요청한다.
  static Future<void> ensureAll(Iterable<num?> spids, {bool freshPrice = false}) async {
    final ids = spids.whereType<num>().map((e) => e.toInt()).toSet().toList();
    if (ids.isEmpty) return;
    await _loadFromDb(ids);
    final now = DateTime.now();
    final need = <int>[];
    for (final id in ids) {
      final m = _mem[id];
      final at = _memAt[id];
      // 시세 신선도는 '메타 받은 시각'이 아니라 '시세 받은 시각'(_price_at) 기준 (2026-09-07 수정):
      // user-squad 동봉 메타를 흡수하면 메타 시각은 방금인데 시세는 없거나 오래돼 재요청이 건너뛰어지던 결함.
      final stale = m == null ||
          at == null ||
          now.difference(at) > _maxAge ||
          !_complete(m) ||
          (freshPrice && priceStale(id));
      if (stale) need.add(id);
    }
    if (need.isEmpty) return;
    // 같은 spid의 동시 요청은 하나로 합침
    final futures = <Future<void>>[];
    final batch = <int>[];
    for (final id in need) {
      final p = _pending[id];
      if (p != null) {
        futures.add(p);
      } else {
        batch.add(id);
      }
    }
    for (var i = 0; i < batch.length; i += 60) {
      final chunk = batch.sublist(i, (i + 60).clamp(0, batch.length));
      final f = _fetchBulk(chunk, freshPrice: freshPrice);
      for (final id in chunk) {
        _pending[id] = f;
      }
      futures.add(f.whenComplete(() {
        for (final id in chunk) {
          if (identical(_pending[id], f)) _pending.remove(id);
        }
      }));
    }
    await Future.wait(futures);
  }

  // 단건 요청 미세 배치: 카드 위젯 11개가 build에서 각각 ensure()를 불러도 50ms 안에 모아 1회로 보냄
  static final Set<int> _queue = {};
  static Completer<void>? _queueDone;
  static Timer? _queueTimer;

  /// 단일 spid 확보 (TraitStore 호환). 같은 프레임의 요청은 하나의 묶음 호출로 합쳐진다.
  static Future<void> ensure(num? spid) {
    if (spid == null) return Future.value();
    final id = spid.toInt();
    if (_mem[id] != null && _complete(_mem[id]!)) return Future.value();
    _queue.add(id);
    _queueDone ??= Completer<void>();
    final done = _queueDone!;
    _queueTimer ??= Timer(const Duration(milliseconds: 50), () {
      final ids = _queue.toList();
      _queue.clear();
      _queueTimer = null;
      _queueDone = null;
      ensureAll(ids).whenComplete(() {
        if (!done.isCompleted) done.complete();
      });
    });
    return done.future;
  }

  static Future<void> _loadFromDb(List<int> ids) async {
    final missing = ids.where((id) => !_mem.containsKey(id)).toList();
    if (missing.isEmpty) return;
    try {
      final db = await _open();
      for (var i = 0; i < missing.length; i += 500) {
        final chunk = missing.sublist(i, (i + 500).clamp(0, missing.length));
        final rows = await db.query('player_meta',
            where: 'spid IN (${List.filled(chunk.length, '?').join(',')})', whereArgs: chunk);
        for (final r in rows) {
          try {
            _mem[r['spid'] as int] = Map<String, dynamic>.from(json.decode(r['json'] as String));
            _memAt[r['spid'] as int] = DateTime.fromMillisecondsSinceEpoch(r['fetched_at'] as int);
          } catch (_) {}
        }
      }
    } catch (e) {
      print('[PlayerMetaStore] DB 읽기 실패: $e');
    }
  }

  static Future<void> _fetchBulk(List<int> ids, {bool freshPrice = false}) async {
    try {
      final r = await http
          .get(Uri.parse('${ApiService.baseUrl}/api/user/squad/player-bulk'
              '?spids=${ids.join(',')}${freshPrice ? '&price=1' : ''}'))
          .timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) return;
      final d = json.decode(r.body);
      if (d['success'] != true) return; // 실패 응답은 캐시하지 않음
      final players = d['players'] as Map? ?? {};
      final now = DateTime.now();
      final db = await _open();
      final batch = db.batch();
      players.forEach((k, v) {
        if (v is! Map) return;
        final m = Map<String, dynamic>.from(v);
        final spid = int.tryParse('$k');
        if (spid == null || (m['each_ovr']?.toString() ?? '').isEmpty) return;
        // 기존에 시세가 있었고 이번 응답에 없으면 과거 시세 유지 — 시각은 갱신하지 않음
        final prev = _mem[spid];
        if ((m['each_price']?.toString() ?? '').isEmpty && prev?['each_price'] != null) {
          m['each_price'] = prev!['each_price'];
          m['_price_at'] = prev['_price_at'] ?? _memAt[spid]?.millisecondsSinceEpoch;
        } else if ((m['each_price']?.toString() ?? '').isNotEmpty) {
          // 서버가 만료 시세(price_stale)를 기준 시각(price_at)과 함께 내려주면 그 시각을 그대로 기록
          m['_price_at'] = _priceAtMsOf(m, now);
        }
        _mem[spid] = m;
        _memAt[spid] = now;
        batch.insert('player_meta', {'spid': spid, 'json': json.encode(m), 'fetched_at': now.millisecondsSinceEpoch},
            conflictAlgorithm: ConflictAlgorithm.replace);
      });
      await batch.commit(noResult: true);
    } catch (e) {
      print('[PlayerMetaStore] 묶음 조회 실패(${ids.length}건): $e');
    }
  }

  /// 스쿼드성 응답(user-squad·ranker-squad)에 동봉된 메타를 바로 캐시에 반영한다.
  /// (서버가 DB에 있는 카드만 동봉하므로 each_ovr가 있는 항목만 신뢰)
  static Future<void> absorb(Iterable<Map<String, dynamic>> players) async {
    final now = DateTime.now();
    Batch? batch;
    try {
      final db = await _open();
      batch = db.batch();
    } catch (_) {}
    for (final p in players) {
      final spid = (p['spid'] as num?)?.toInt();
      if (spid == null) continue;
      if ((p['each_ovr']?.toString() ?? '').isEmpty || p['traits'] is! List) continue;
      final m = <String, dynamic>{
        'spid': spid,
        'name': p['name'],
        'pay': p['pay'],
        'each_ovr': p['each_ovr'],
        if (p['each_price'] != null) 'each_price': p['each_price'],
        if (p['each_price'] != null) '_price_at': _priceAtMsOf(p, now),
        'season_img': p['season_img'],
        'face_url': p['face_url'],
        'position': p['position'],
        'traits': p['traits'],
        'teamcolors': p['teamcolors'] ?? [],
      };
      _mem[spid] = m;
      _memAt[spid] = now;
      batch?.insert('player_meta', {'spid': spid, 'json': json.encode(m), 'fetched_at': now.millisecondsSinceEpoch},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    try {
      await batch?.commit(noResult: true);
    } catch (_) {}
  }
}
