import 'dart:convert';
import 'package:http/http.dart' as http;

/// 시즌 메타 (넥슨 seasonid.json) — 시즌 이미지·이름. 앱 세션당 1회 로드.
/// 시즌은 텍스트보다 이미지 표기가 효과적 (사용자 지정) — 앱 전반 공용.
class SeasonMeta {
  static Map<int, String>? _imgs;
  static Map<int, String>? _names;
  static Future<void>? _loading;

  static Future<void> ensure() {
    if (_imgs != null) return Future.value();
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    try {
      final response = await http
          .get(Uri.parse(
              'https://open.api.nexon.com/static/fconline/meta/seasonid.json'))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final list = json.decode(utf8.decode(response.bodyBytes)) as List;
        _imgs = {
          for (final e in list)
            (e['seasonId'] as num).toInt(): (e['seasonImg'] ?? '') as String
        };
        _names = {
          for (final e in list)
            (e['seasonId'] as num).toInt():
                ((e['className'] ?? '') as String).split(' (').first
        };
      }
    } catch (e) {
      print('[SeasonMeta] 로드 실패: $e');
      _loading = null; // 다음 기회에 재시도
    }
  }

  static String? imgForSpid(num? spid) {
    if (spid == null) return null;
    final url = _imgs?[spid.toInt() ~/ 1000000];
    return (url == null || url.isEmpty) ? null : url;
  }

  static String? nameForSpid(num? spid) {
    if (spid == null) return null;
    return _names?[spid.toInt() ~/ 1000000];
  }
}
