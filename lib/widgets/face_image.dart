import 'package:flutter/material.dart';

/// 선수 얼굴 이미지 — 대체 주소 순차 시도 (2026-09-07, 1.0.12)
///
/// 넥슨 CDN에는 카드(spid)별 액션 이미지가 없는 경우가 있어(예: 848 매디슨·852 쿨루셉스키 → 403)
/// 서버가 내려준 주소를 우선 쓰고, 실패하면 spid·pid 규칙 주소를 차례로 시도한다.
/// 전부 실패하면 [fallback]을 표시한다.
class FaceImage extends StatefulWidget {
  final String? url; // 서버가 내려준 face_url (없으면 null)
  final num? spid;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget fallback;

  const FaceImage({
    Key? key,
    this.url,
    this.spid,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.fallback = const SizedBox.shrink(),
  }) : super(key: key);

  static const _base =
      'https://fco.dn.nexoncdn.co.kr/live/externalAssets/common';

  /// 시도 순서: 서버 주소 → playersAction/spid → players/spid → playersAction/pid → players/pid
  static List<String> candidates(String? url, num? spid) {
    final out = <String>[];
    void add(String? u) {
      if (u != null && u.isNotEmpty && !out.contains(u)) out.add(u);
    }

    add(url);
    if (spid != null) {
      final s = spid.toInt();
      final pid = s % 1000000;
      add('$_base/playersAction/p$s.png');
      add('$_base/players/p$s.png');
      add('$_base/playersAction/p$pid.png');
      add('$_base/players/p$pid.png');
    }
    return out;
  }

  @override
  State<FaceImage> createState() => _FaceImageState();
}

class _FaceImageState extends State<FaceImage> {
  late List<String> _urls;
  int _idx = 0;
  // 후보 전환 예약 여부. Flutter의 Image 위젯은 오류 상태에서 부모가 다시 그릴 때마다 errorBuilder를
  // 다시 호출하므로(image.dart build: _lastException != null), 호출마다 _idx를 올리면 살아 있는 후보를
  // 건너뛰어 사람 아이콘으로 굳는다 (산체스 등 — 2026-09-11). 후보 1개당 전환은 정확히 1회만.
  bool _advanceScheduled = false;

  @override
  void initState() {
    super.initState();
    _urls = FaceImage.candidates(widget.url, widget.spid);
  }

  @override
  void didUpdateWidget(FaceImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.spid != widget.spid) {
      _urls = FaceImage.candidates(widget.url, widget.spid);
      _idx = 0;
      _advanceScheduled = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_idx >= _urls.length) return widget.fallback;
    return Image.network(
      _urls[_idx],
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: (c, e, s) {
        // 다음 후보로 넘어감 (빌드 중 setState 금지 → 다음 프레임). 같은 후보에 대해 한 번만 예약.
        if (!_advanceScheduled) {
          _advanceScheduled = true;
          final failed = _idx;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _advanceScheduled = false;
            if (_idx == failed && _idx < _urls.length) setState(() => _idx++);
          });
        }
        return widget.fallback;
      },
    );
  }
}
