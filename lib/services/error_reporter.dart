import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// 앱 오류 자동 기록 + 버그 제보 전송 — Panenka 1.0.4 (2026-08-22).
///
/// - 오류: Flutter 프레임워크 오류·잡히지 않은 예외를 서버 `/api/app/error`로 전송.
///   같은 오류(종류+메시지+화면)는 이 기기에서 10분 안에 다시 보내지 않고, 네트워크가 끊기면 다음 실행 때 재전송.
///   서버가 기기당 하루 50건으로 상한을 둔다. 사용자 화면에는 아무것도 띄우지 않는다.
/// - 제보: 더보기 → 버그 제보·건의 화면에서 `/api/app/feedback`로 전송 (글만, 기기·버전·화면 자동 첨부).
/// - 알림 발송 없음 — 관리자 대시보드 '제보·오류' 탭에서만 본다.
class ErrorReporter {
  ErrorReporter._();

  static String appVersion = '';
  static String build = '';
  static String device = '';
  static String os = '';
  static String deviceId = '';
  static String currentScreen = ''; // 각 탭/화면이 진입 시 갱신

  static final Map<String, DateTime> _recent = {};
  static const _dedupeWindow = Duration(minutes: 10);
  static const _pendingKey = 'error_reports_pending_v1';
  static bool _ready = false;

  /// main()에서 runApp 전에 호출. 실패해도 앱 실행에는 영향 없음.
  static Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.version;
      build = info.buildNumber;
    } catch (_) {}
    try {
      final di = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await di.androidInfo;
        device = '${a.manufacturer} ${a.model}'.trim();
        os = 'Android ${a.version.release}';
        deviceId = a.id;
      } else if (Platform.isIOS) {
        final i = await di.iosInfo;
        device = i.utsname.machine;
        os = '${i.systemName} ${i.systemVersion}';
        deviceId = i.identifierForVendor ?? '';
      }
    } catch (_) {}
    if (deviceId.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        deviceId = prefs.getString('device_anon_id') ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36);
        await prefs.setString('device_anon_id', deviceId);
      } catch (_) {}
    }
    _ready = true;
    _flushPending();
  }

  static String get platform => Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'other');

  /// Flutter 오류 훅 설치 (FlutterError.onError + PlatformDispatcher.onError)
  static void installHandlers() {
    final prev = FlutterError.onError;
    FlutterError.onError = (details) {
      prev?.call(details);
      report(details.exception, details.stack, context: 'flutter');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, context: 'zone');
      return true;
    };
  }

  /// 오류 1건 기록 (중복·네트워크 실패 처리 포함). 어디서든 호출 가능.
  static void report(Object error, StackTrace? stack, {String context = ''}) {
    try {
      final type = error.runtimeType.toString();
      final message = _oneLine(error.toString());
      final key = '$type|${message.substring(0, message.length > 160 ? 160 : message.length)}|$currentScreen';
      final now = DateTime.now();
      final last = _recent[key];
      if (last != null && now.difference(last) < _dedupeWindow) return;
      _recent[key] = now;
      if (_recent.length > 200) _recent.remove(_recent.keys.first);
      final payload = {
        'type': type,
        'message': message,
        'stack': _trimStack(stack),
        'screen': currentScreen,
        'app_version': appVersion,
        'build': build,
        'platform': platform,
        'device': device,
        'os': os,
        'device_id': deviceId,
        'context': context,
      };
      _send(payload);
    } catch (_) {
      // 오류 기록 자체의 실패는 무시
    }
  }

  static Future<void> _send(Map<String, dynamic> payload) async {
    try {
      final r = await http
          .post(Uri.parse('${ApiService.baseUrl}/api/app/error'),
              headers: {'Content-Type': 'application/json'}, body: json.encode(payload))
          .timeout(const Duration(seconds: 8));
      if (r.statusCode >= 500) await _queue(payload);
    } catch (_) {
      await _queue(payload); // 네트워크 실패 → 다음 실행 때 재전송
    }
  }

  static Future<void> _queue(Map<String, dynamic> payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = (json.decode(prefs.getString(_pendingKey) ?? '[]') as List).cast<dynamic>();
      if (list.length >= 20) list.removeAt(0);
      list.add(payload);
      await prefs.setString(_pendingKey, json.encode(list));
    } catch (_) {}
  }

  static Future<void> _flushPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingKey);
      if (raw == null) return;
      await prefs.remove(_pendingKey);
      for (final p in (json.decode(raw) as List)) {
        if (p is Map) await _send(Map<String, dynamic>.from(p));
      }
    } catch (_) {}
  }

  /// 버그 제보·건의 전송. 성공 시 true.
  static Future<bool> sendFeedback({required String kind, required String message}) async {
    if (!_ready) await init();
    final token = ApiService().token;
    try {
      final r = await http
          .post(Uri.parse('${ApiService.baseUrl}/api/app/feedback'),
              headers: {
                'Content-Type': 'application/json',
                if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
              },
              body: json.encode({
                'kind': kind,
                'message': message,
                'app_version': appVersion,
                'build': build,
                'platform': platform,
                'device': device,
                'os': os,
                'screen': currentScreen,
              }))
          .timeout(const Duration(seconds: 15));
      final d = json.decode(r.body);
      return d['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static String _oneLine(String s) => s.replaceAll('\n', ' ').trim();
  static String _trimStack(StackTrace? s) {
    if (s == null) return '';
    final lines = s.toString().split('\n').where((l) => l.trim().isNotEmpty).take(25).join('\n');
    return lines.length > 3500 ? lines.substring(0, 3500) : lines;
  }
}
