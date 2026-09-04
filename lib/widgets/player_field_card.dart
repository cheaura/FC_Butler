import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';
import '../constants/positions.dart';
import '../services/trait_store.dart';
import '../services/player_meta_store.dart';
import 'badges.dart';

/// 필드 선수 카드 — 3화면(스쿼드 탭·검색 스쿼드 세그·경기 상세) 공용.
///
/// 코너 배치 (2026-08-19 사용자 재확정 — 대시보드 라인업과 동일 규칙):
///   좌상 = 포지션, 그 아래 = 신규특성
///   우상 = 오버롤, 그 아래 = 급여(육각)
///   좌하 = 시즌 · 우하 = 강화
/// 선수명 아래: 경기 분석=평점 알약([rating] 전달 시 자동), 스쿼드 탭=시세([footerLines]).
/// 평점 최고 = 금색+★, 최저 = 로즈+▽ (배지 색이 아이콘 역할 — 기존 확정 유지).
class PlayerFieldCard extends StatefulWidget {
  final double cardW;
  final int spPos;
  final num? spid;
  final String? faceUrl;
  final String name;
  final int? grade; // null이면 강화 배지 숨김
  final int? ovr; // 우상 오버롤 (스쿼드 탭 등 보유 화면만)
  final Object? pay; // 급여 (우상 아래 육각 배지, 보유 화면만)
  final String? seasonFallback; // 시즌 이미지 없을 때 텍스트 폴백
  final num? rating; // 경기 분석 화면 전용 — 선수명 아래 알약
  final bool isBestRating;
  final bool isWorstRating;
  final List<Widget> footerLines; // 이름 아래 화면별 부가 정보 (시세 등)
  final bool empty; // 빈 슬롯 (스쿼드 탭 전용 — '+' 표시)
  final VoidCallback? onTap;

  const PlayerFieldCard({
    Key? key,
    required this.cardW,
    required this.spPos,
    this.spid,
    this.faceUrl,
    this.name = '',
    this.grade,
    this.ovr,
    this.pay,
    this.seasonFallback,
    this.rating,
    this.isBestRating = false,
    this.isWorstRating = false,
    this.footerLines = const [],
    this.empty = false,
    this.onTap,
  }) : super(key: key);

  @override
  State<PlayerFieldCard> createState() => _PlayerFieldCardState();
}

class _PlayerFieldCardState extends State<PlayerFieldCard> {
  @override
  void initState() {
    super.initState();
    _ensureTraits();
  }

  @override
  void didUpdateWidget(covariant PlayerFieldCard old) {
    super.didUpdateWidget(old);
    if (old.spid != widget.spid) _ensureTraits();
  }

  void _ensureTraits() {
    if (widget.empty || widget.spid == null) return;
    if (TraitStore.cached(widget.spid) == null) {
      TraitStore.ensure(widget.spid).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  /// 급여 육각 배지 — 웹 squad-slot-payhex 이식 (흰 테두리 육각 + 반투명 암녹 판)
  Widget _payHex() {
    return ClipPath(
      clipper: _HexClipper(),
      child: Container(
        width: 15,
        height: 17,
        color: const Color(0xD9FFFFFF),
        alignment: Alignment.center,
        child: ClipPath(
          clipper: _HexClipper(),
          child: Container(
            width: 13,
            height: 15,
            color: const Color(0x8C0F1E0F),
            alignment: Alignment.center,
            child: Text('${widget.pay}',
                style: const TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
        ),
      ),
    );
  }

  /// 평점 알약 (선수명 아래) — 색 체계는 기존 확정안 유지
  Widget _ratingPill() {
    final Color bg;
    final Color fg;
    final String prefix;
    if (widget.isBestRating) {
      bg = const Color(0xFFF2C14E);
      fg = const Color(0xFF4A3305);
      prefix = '★ ';
    } else if (widget.isWorstRating) {
      bg = const Color(0xFF4A2438);
      fg = const Color(0xFFEB8FA9);
      prefix = '▽ ';
    } else {
      bg = const Color(0xFF2B2740);
      fg = const Color(0xFFCFC9E8);
      prefix = '';
    }
    return Container(
      margin: const EdgeInsets.only(top: 1.5),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 2)],
      ),
      child: Text('$prefix${widget.rating!.toStringAsFixed(1)}',
          style: TextStyle(
              fontSize: 7.5, fontWeight: FontWeight.w800, color: fg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatarSize = widget.cardW * 0.60;
    final traits =
        widget.empty ? null : TraitStore.cached(widget.spid);
    // 팀컬러 개수 점 (1.0.4, 2-A): 카드 하단 중앙. 내용은 카드를 눌렀을 때 시트에서.
    final tcList = widget.empty ? null : PlayerMetaStore.cached(widget.spid)?['teamcolors'];
    final tcCount = tcList is List ? tcList.length : 0;

    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: widget.cardW,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black26,
                    border: Border.all(color: Colors.white70, width: 1.4),
                  ),
                  child: ClipOval(
                    child: widget.empty
                        ? const Icon(Icons.add,
                            color: Colors.white54, size: 20)
                        : Image.network(
                            widget.faceUrl ?? '',
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => const Icon(
                                Icons.person,
                                color: Colors.white70,
                                size: 18),
                          ),
                  ),
                ),
                // 좌상: 포지션
                Positioned(
                  top: -5,
                  left: -7,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 3.5, vertical: 1),
                    decoration: BoxDecoration(
                      color: posColor(widget.spPos),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                        kSpposRole[widget.spPos]?.toUpperCase() ?? '',
                        style: const TextStyle(
                            fontSize: 7.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                ),
                // 좌상 아래: 신규특성 (넥슨 아이콘, 최대 2개)
                if (traits != null && traits.isNotEmpty)
                  Positioned(
                    top: 9,
                    left: -7,
                    child: Container(
                      padding: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xE61F3A5C),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final t in traits.take(2))
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 0.5),
                              child: Image.network(
                                '${t['icon'] ?? ''}',
                                width: 10,
                                height: 10,
                                errorBuilder: (c, e, s) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                // 우상: 오버롤
                if (!widget.empty && widget.ovr != null)
                  Positioned(
                    top: -5,
                    right: -7,
                    child: Text('${widget.ovr}',
                        style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFFFE082),
                            shadows: [
                              Shadow(color: Colors.black87, blurRadius: 3)
                            ])),
                  ),
                // 우상 아래: 급여 (육각 배지)
                if (!widget.empty && widget.pay != null)
                  Positioned(top: 9, right: -7, child: _payHex()),
                // 좌하: 시즌
                if (!widget.empty)
                  Positioned(
                    bottom: -4,
                    left: -7,
                    child: SeasonBadge(
                        spid: widget.spid,
                        height: 10,
                        fallbackText: widget.seasonFallback),
                  ),
                // 우하: 강화
                if (!widget.empty && widget.grade != null)
                  Positioned(
                    bottom: -4,
                    right: -7,
                    child:
                        GradeBadge(grade: widget.grade!, fontSize: 7.5),
                  ),
                // 하단 중앙: 팀컬러 개수 (1.0.4)
                if (tcCount > 0)
                  Positioned(
                    bottom: -7,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                        decoration: BoxDecoration(
                          color: PanenkaTokens.of(context).accentBand,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.black54, width: 0.8),
                        ),
                        child: Text('$tcCount',
                            style: TextStyle(
                                fontSize: 7,
                                fontWeight: FontWeight.w800,
                                color: panenkaOnFill(PanenkaTokens.of(context).accentBand),
                                height: 1.2)),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.empty ? '비어 있음' : widget.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 3)]),
            ),
            // 경기 분석: 평점 알약 (선수명 아래 — 사용자 확정)
            if (!widget.empty && widget.rating != null) _ratingPill(),
            ...widget.footerLines,
          ],
        ),
      ),
    );
  }
}

/// 뾰족 육각형 클리퍼 — 웹 payhex clip-path 좌표 이식
class _HexClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w, h * 0.25)
      ..lineTo(w, h * 0.75)
      ..lineTo(w * 0.5, h)
      ..lineTo(0, h * 0.75)
      ..lineTo(0, h * 0.25)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
