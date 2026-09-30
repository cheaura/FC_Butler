import 'package:flutter/material.dart';

import '../providers/theme_provider.dart';
import '../services/ovr_formula.dart';
import '../services/player_api.dart';
import '../services/player_calc.dart';
import '../utils/fc_format.dart';
import 'badges.dart';
import 'face_image.dart';
import 'pill_tabs.dart';
import 'player_card_controls.dart';
import 'player_list_row.dart';

/// 두 선수 비교 팝업 (2026-09-30 시안 확정).
///
/// 목록에서 비교 버튼으로 고른 두 카드를 나란히 보여준다. 선수마다 강화·적응도·팀컬러를 따로 조절하고,
/// 세부 능력은 높은 쪽에 차이 숫자를 붙인다. 같은 선수의 다른 시즌 카드끼리도 비교된다(카드 단위).
Future<void> showPlayerCompareSheet(
  BuildContext context, {
  required Map<String, dynamic> first,
  required Map<String, dynamic> second,
  int grade = 1,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => FractionallySizedBox(
      heightFactor: 0.95,
      child: PlayerCompareSheet(first: first, second: second, grade: grade),
    ),
  );
}

class PlayerCompareSheet extends StatefulWidget {
  const PlayerCompareSheet({super.key, required this.first, required this.second, this.grade = 1});

  /// 검색 결과 줄 (spid·name·positions 등)
  final Map<String, dynamic> first;
  final Map<String, dynamic> second;

  /// 목록에서 보고 있던 강화 기준 — 두 선수의 시작 강화 단계
  final int grade;

  @override
  State<PlayerCompareSheet> createState() => _PlayerCompareSheetState();
}

class _PlayerCompareSheetState extends State<PlayerCompareSheet> {
  late final PlayerCardState _a;
  late final PlayerCardState _b;
  int _tab = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _a = PlayerCardState((widget.first['spid'] as num).toInt(), grade: widget.grade);
    _b = PlayerCardState((widget.second['spid'] as num).toInt(), grade: widget.grade);
    _load();
  }

  Future<void> _load() async {
    try {
      await OvrFormula.ensureLoaded();
      final d = await PlayerApi.detail([_a.spid, _b.spid]);
      if (!mounted) return;
      if (d[_a.spid] == null || d[_b.spid] == null) throw Exception('세부 능력치를 가져오지 못했습니다.');
      setState(() {
        _a.apply(d[_a.spid]!);
        _b.apply(d[_b.spid]!);
        _loading = false;
      });
      // 팀컬러 목록은 뒤이어 받는다 (없어도 비교는 된다)
      await Future.wait([_a.loadTcOptions(), _b.loadTcOptions()]);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  /// 표시할 포지션: 검색 결과 줄의 포지션(없으면 카드 주포지션)
  List<String> _positions(Map<String, dynamic> row, PlayerCardState s) {
    final list = [for (final p in (row['positions'] as List? ?? const [])) if (p is Map) '${p['pos']}'];
    if (list.isNotEmpty) return list;
    final main = '${s.data?['position'] ?? ''}';
    return main.isEmpty ? const [] : [main];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PanenkaTokens.of(context);
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: tokens.mute.withOpacity(.5), borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
          child: Row(
            children: [
              const Expanded(child: Text('선수 비교', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              IconButton(tooltip: '닫기', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _side(widget.first, _a)),
                const SizedBox(width: 8),
                Expanded(child: _side(widget.second, _b)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: PillTabs(
            labels: const ['능력치', '특성', '시세', '클럽 경력'],
            selectedIndex: _tab,
            onSelected: (i) => setState(() => _tab = i),
          ),
        ),
        Expanded(child: _body(tokens)),
      ],
    );
  }

  Widget _side(Map<String, dynamic> row, PlayerCardState s) {
    final tokens = PanenkaTokens.of(context);
    final positions = _positions(row, s);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipOval(
                child: Container(
                  color: tokens.soft,
                  child: FaceImage(
                      url: row['face_url']?.toString(),
                      spid: s.spid,
                      width: 40,
                      height: 40,
                      fallback: Icon(Icons.person, size: 26, color: tokens.mute)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SeasonBadge(spid: s.spid, height: 13, fallbackText: row['season_img']?.toString()),
                    const SizedBox(height: 2),
                    Text('${row['name'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (s.ready)
            PositionOvrLine(items: s.ovrsFor(positions), ovrSize: 15)
          else
            PositionOvrLine(items: PlayerCalc.shownPositions(row['positions'] as List?, s.grade), ovrSize: 15),
          const SizedBox(height: 8),
          StepperField(
              label: '강화', value: s.grade, min: 1, max: 13, onChanged: (v) => setState(() => s.grade = v)),
          const SizedBox(height: 6),
          StepperField(
              label: '적응도', value: s.adap, min: 1, max: 5, onChanged: (v) => setState(() => s.adap = v)),
          const SizedBox(height: 6),
          TcSummaryField(state: s, onChanged: () => setState(() {})),
        ],
      ),
    );
  }

  Widget _body(PanenkaTokens tokens) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: tokens.mute))));
    }
    switch (_tab) {
      case 1:
        return _traits(tokens);
      case 2:
        return _prices(tokens);
      case 3:
        return _career(tokens);
      default:
        return _stats(tokens);
    }
  }

  // ── 능력치: 총 능력치·6개 묶음·세부 34종, 높은 쪽에 차이 숫자 ──
  Widget _stats(PanenkaTokens tokens) {
    final ea = _a.eff, eb = _b.eff;
    final fa = PlayerCalc.faceStats(ea), fb = PlayerCalc.faceStats(eb);
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        _cmpRow(tokens, '총 능력치', PlayerCalc.totalStats(ea), PlayerCalc.totalStats(eb), height: 40, size: 20),
        for (final k in PlayerCalc.faceOrder) _cmpRow(tokens, k, fa[k] ?? 0, fb[k] ?? 0, height: 34, size: 18),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
          child: Text('세부 능력 · 높은 쪽에 차이 표시',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tokens.subInk)),
        ),
        for (final k in OvrFormula.statKeys)
          if (ea.containsKey(k) || eb.containsKey(k)) _cmpRow(tokens, k, ea[k] ?? 0, eb[k] ?? 0),
      ],
    );
  }

  Widget _cmpRow(PanenkaTokens tokens, String label, num a, num b, {double height = 30, double size = 16}) {
    final d = PlayerCalc.diff(a, b);
    const mono = [FontFeature.tabularFigures()];
    Widget value(num v, bool win) => Text('${v.round()}',
        style: TextStyle(
            fontSize: size, fontWeight: FontWeight.w800, fontFeatures: mono, color: win ? null : tokens.mute));
    Widget gap(int n) => n > 0
        ? Text('+$n',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, fontFeatures: mono, color: tokens.winInk))
        : const SizedBox.shrink();
    return Container(
      height: height,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tokens.line))),
      child: Row(
        children: [
          // 값+차이가 칸보다 길면(글자 크기를 키운 기기 등) 넘치지 않고 줄어들게 한다
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [gap(d.left), const SizedBox(width: 6), value(a, a >= b)],
              ),
            ),
          ),
          SizedBox(
            width: 108,
            child: Text(label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: tokens.mute)),
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [value(b, b >= a), const SizedBox(width: 6), gap(d.right)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 특성: 선수별 타일 ──
  Widget _traits(PanenkaTokens tokens) {
    Widget col(PlayerCardState s) {
      final traits = [for (final t in (s.data?['traits'] as List? ?? const [])) if (t is Map) t];
      if (traits.isEmpty) {
        return Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text('특성 없음', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: tokens.mute)));
      }
      return GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1.15,
        children: [for (final t in traits) TraitTile(name: '${t['name'] ?? ''}', icon: t['icon']?.toString())],
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: col(_a)), const SizedBox(width: 8), Expanded(child: col(_b))],
      ),
    );
  }

  // ── 시세: 강화 단계별 현재가 나란히 ──
  Widget _prices(PanenkaTokens tokens) {
    final pa = _a.data?['each_price']?.toString(), pb = _b.data?['each_price']?.toString();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        for (var g = 1; g <= 13; g++)
          Container(
            height: 32,
            decoration: BoxDecoration(
              color: (g == _a.grade || g == _b.grade) ? tokens.accentSoft : null,
              border: Border(bottom: BorderSide(color: tokens.line)),
            ),
            child: Row(
              children: [
                Expanded(child: _priceCell(PlayerCalc.priceAt(pa, g), g == _a.grade, TextAlign.right)),
                SizedBox(
                    width: 64,
                    child: Text('$g강',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: tokens.mute))),
                Expanded(child: _priceCell(PlayerCalc.priceAt(pb, g), g == _b.grade, TextAlign.left)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _priceCell(int? v, bool on, TextAlign align) => Text(v == null ? '-' : formatBp(v),
      textAlign: align,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12.5, fontWeight: on ? FontWeight.w800 : FontWeight.w600));

  // ── 클럽 경력 ──
  Widget _career(PanenkaTokens tokens) {
    Widget col(PlayerCardState s) {
      final career = [for (final c in (s.data?['career'] as List? ?? const [])) if (c is Map) c];
      if (career.isEmpty) {
        return Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text('클럽 경력 없음',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: tokens.mute)));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in career)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${c['years'] ?? ''}', style: TextStyle(fontSize: 11, color: tokens.mute)),
                  Text('${c['club'] ?? ''}${'${c['loan'] ?? ''}'.isNotEmpty ? ' (${c['loan']})' : ''}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: col(_a)), const SizedBox(width: 12), Expanded(child: col(_b))],
      ),
    );
  }
}
