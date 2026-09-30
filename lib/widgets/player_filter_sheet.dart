import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/player_query.dart';
import '../providers/theme_provider.dart';
import '../services/player_api.dart';
import 'player_card_controls.dart';

/// 선수 검색 조건 시트 (2026-09-30 시안 확정). 닫을 때 고른 조건을 돌려준다(취소하면 null).
///
/// 묶음: 시즌 / 포지션 / 강화·OVR·급여·선수 가치 / 특성(신규특성 먼저) / 소속 / 세부 능력 / 신체 / 기타.
/// 조건 목록(시즌·리그·클럽·국적·특성)은 서버가 넥슨 데이터센터에서 읽어 준 것을 쓴다.
Future<PlayerQuery?> showPlayerFilterSheet(BuildContext context, PlayerQuery current) {
  return showModalBottomSheet<PlayerQuery>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => FractionallySizedBox(heightFactor: 0.94, child: PlayerFilterSheet(current: current)),
  );
}

class PlayerFilterSheet extends StatefulWidget {
  const PlayerFilterSheet({super.key, required this.current});

  final PlayerQuery current;

  @override
  State<PlayerFilterSheet> createState() => _PlayerFilterSheetState();
}

class _PlayerFilterSheetState extends State<PlayerFilterSheet> {
  static const _posRows = [
    ['FW', 'ST', 'CF', 'LW', 'RW'],
    ['MF', 'CAM', 'CM', 'CDM', 'LM', 'RM'],
    ['DF', 'CB', 'LB', 'RB', 'LWB', 'RWB'],
    ['GK', 'GK'],
  ];
  static const _bodyLabels = {'thin': '마름', 'normal': '보통', 'heavy': '건장'};
  static const _reputations = {5: '레전더리', 4: '월드클래스', 3: '탑클래스', 2: '유명선수', 1: '일반선수'};
  static const _seasonPreview = 24;

  late PlayerQuery _q;
  Map<String, dynamic>? _opt;
  bool _loading = true;
  final Set<String> _open = {'season', 'position', 'range', 'trait'};
  String _seasonFilter = '';
  bool _seasonAll = false;
  bool _traitAll = false;
  int _resetSeq = 0; // 초기화 때 입력칸을 새로 만들기 위한 번호

  @override
  void initState() {
    super.initState();
    _q = widget.current.copy();
    // 값이 들어 있는 묶음은 펼쳐 둔다
    if (_q.leagueId != null || _q.teamId != null || _q.nationId != null || _q.teamcolorId != null) _open.add('club');
    if (_q.abilities.isNotEmpty) _open.add('ability');
    if (_q.heightMin != null || _q.heightMax != null || _q.weightMin != null || _q.weightMax != null ||
        _q.bodyTypes.isNotEmpty || _q.mainFoot.isNotEmpty || _q.weakFoot != null || _q.skillMove != null) {
      _open.add('body');
    }
    if (_q.birthMin != null || _q.birthMax != null || _q.reputation != null) _open.add('etc');
    PlayerApi.options().then((o) {
      if (mounted) {
        setState(() {
          _opt = o;
          _loading = false;
        });
      }
    });
  }

  List<Map<String, dynamic>> _list(String key) =>
      [for (final e in (_opt?[key] as List? ?? const [])) if (e is Map) Map<String, dynamic>.from(e)];

  // ── 공용 부품 ──
  Widget _section(String id, String title, String summary, List<Widget> children) {
    final tokens = PanenkaTokens.of(context);
    final open = _open.contains(id);
    final has = summary.isNotEmpty;
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: tokens.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => open ? _open.remove(id) : _open.add(id)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  Expanded(child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
                  Flexible(
                    child: Text(has ? summary : '선택 없음',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 11, color: has ? tokens.accentInk : tokens.mute)),
                  ),
                  const SizedBox(width: 4),
                  Icon(open ? Icons.expand_more : Icons.chevron_right, size: 18, color: tokens.mute),
                ],
              ),
            ),
          ),
          if (open) Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)),
        ],
      ),
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap, {double? width}) {
    final tokens = PanenkaTokens.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: width,
        height: 40,
        alignment: Alignment.center,
        padding: width == null ? const EdgeInsets.symmetric(horizontal: 12) : null,
        decoration: BoxDecoration(
          color: on ? tokens.accentSoft : tokens.soft,
          border: Border.all(color: on ? tokens.accentInk.withOpacity(.7) : Colors.transparent),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: on ? FontWeight.w800 : FontWeight.w500, color: on ? tokens.accentInk : null)),
      ),
    );
  }

  Widget _num(String id, int? value, String hint, ValueChanged<int?> onChanged) {
    final tokens = PanenkaTokens.of(context);
    return Expanded(
      child: SizedBox(
        height: 40,
        child: TextFormField(
          key: ValueKey('$id-$_resetSeq'),
          initialValue: value?.toString() ?? '',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(fontSize: 12, color: tokens.mute, fontWeight: FontWeight.w400),
            filled: true,
            fillColor: tokens.soft,
            contentPadding: const EdgeInsets.symmetric(vertical: 11),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
          onChanged: (v) => setState(() => onChanged(int.tryParse(v))),
        ),
      ),
    );
  }

  Widget _range(String id, String label, int? min, int? max, ValueChanged<int?> onMin, ValueChanged<int?> onMax) {
    final tokens = PanenkaTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 82, child: Text(label, style: TextStyle(fontSize: 12, color: tokens.mute))),
          _num('$id-min', min, '최소', onMin),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text('~', style: TextStyle(color: tokens.mute))),
          _num('$id-max', max, '최대', onMax),
        ],
      ),
    );
  }

  Widget _pickField(String label, String value, VoidCallback onTap, {VoidCallback? onClear}) {
    final tokens = PanenkaTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 42,
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(color: tokens.soft, borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              SizedBox(width: 62, child: Text(label, style: TextStyle(fontSize: 12, color: tokens.mute))),
              Expanded(
                child: Text(value.isEmpty ? '전체' : value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: value.isEmpty ? FontWeight.w400 : FontWeight.w700)),
              ),
              if (value.isNotEmpty && onClear != null)
                IconButton(
                    tooltip: '$label 조건 지우기',
                    visualDensity: VisualDensity.compact,
                    onPressed: onClear,
                    icon: Icon(Icons.close, size: 16, color: tokens.mute))
              else
                Padding(padding: const EdgeInsets.only(right: 8), child: Icon(Icons.expand_more, size: 16, color: tokens.mute)),
            ],
          ),
        ),
      ),
    );
  }

  /// 검색 가능한 목록에서 하나 고르기 (리그·클럽·국적·팀컬러·세부 능력)
  Future<Map<String, dynamic>?> _pick(String title, List<Map<String, dynamic>> items) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        var filter = '';
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final rows = filter.isEmpty
                ? items
                : items.where((e) => '${e['name']}'.toLowerCase().contains(filter.toLowerCase())).toList();
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .75),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: TextField(
                          onChanged: (v) => setSheet(() => filter = v.trim()),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '검색어를 입력하세요',
                            prefixIcon: const Icon(Icons.search, size: 18),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(999)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: rows.length,
                          itemBuilder: (_, i) => ListTile(
                            dense: true,
                            title: Text('${rows[i]['name']}'),
                            onTap: () => Navigator.pop(ctx, rows[i]),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── 특성: 누를 때마다 없음 → 보유 → 제외 → 없음 ──
  void _cycleTrait(String name) {
    setState(() {
      if (_q.traits.contains(name)) {
        _q.traits.remove(name);
        if (_q.traitsNot.length < PlayerQuery.maxTraits) _q.traitsNot.add(name);
      } else if (_q.traitsNot.contains(name)) {
        _q.traitsNot.remove(name);
      } else if (_q.traits.length < PlayerQuery.maxTraits) {
        _q.traits.add(name);
      } else if (_q.traitsNot.length < PlayerQuery.maxTraits) {
        _q.traitsNot.add(name);
      } else {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('보유 3개, 제외 3개까지 고를 수 있습니다.')));
      }
    });
  }

  String _rangeText(String label, int? a, int? b) {
    if (a == null && b == null) return '';
    if (a != null && b != null) return '$label $a~$b';
    return a != null ? '$label $a 이상' : '$label $b 이하';
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
              const Expanded(child: Text('검색 조건', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              TextButton.icon(
                onPressed: () => setState(() {
                  _q.clearConditions();
                  _resetSeq++;
                }),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('초기화'),
              ),
              IconButton(tooltip: '닫기', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    if (_opt == null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Text('검색 조건을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.',
                            style: TextStyle(fontSize: 12, color: tokens.loseInk)),
                      ),
                    _seasonSection(tokens),
                    _positionSection(tokens),
                    _rangeSection(tokens),
                    _traitSection(tokens),
                    _clubSection(tokens),
                    _abilitySection(tokens),
                    _bodySection(tokens),
                    _etcSection(tokens),
                  ],
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: tokens.line))),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _q),
              child: Text(_q.conditionCount == 0 ? '조건 없이 검색' : '조건 ${_q.conditionCount}개로 검색',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _seasonSection(PanenkaTokens tokens) {
    final all = _list('seasons');
    final f = _seasonFilter.toLowerCase();
    var shown = f.isEmpty ? all : all.where((s) => '${s['name']}'.toLowerCase().contains(f)).toList();
    final more = f.isEmpty && !_seasonAll && shown.length > _seasonPreview;
    if (more) {
      // 고른 시즌은 접힌 상태에서도 보이게 앞에 둔다
      final picked = shown.where((s) => _q.seasons.contains((s['id'] as num).toInt())).toList();
      final rest = shown.where((s) => !_q.seasons.contains((s['id'] as num).toInt())).toList();
      shown = [...picked, ...rest].take(_seasonPreview > picked.length ? _seasonPreview : picked.length).toList();
    }
    return _section('season', '시즌', _q.seasons.isEmpty ? '' : '${_q.seasons.length}개 선택', [
      SizedBox(
        height: 38,
        child: TextField(
          onChanged: (v) => setState(() => _seasonFilter = v.trim()),
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            hintText: '시즌 이름으로 찾기',
            prefixIcon: const Icon(Icons.search, size: 16),
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(999)),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final s in shown)
            Builder(builder: (_) {
              final id = (s['id'] as num).toInt();
              final on = _q.seasons.contains(id);
              return Tooltip(
                message: '${s['name']}',
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => on ? _q.seasons.remove(id) : _q.seasons.add(id)),
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: on ? tokens.accentSoft : tokens.soft,
                      border: Border.all(color: on ? tokens.accentInk.withOpacity(.75) : Colors.transparent),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Image.network('${s['img']}',
                        height: 18,
                        errorBuilder: (c, e, st) => Center(
                            widthFactor: 1,
                            child: Text('${s['name']}', style: const TextStyle(fontSize: 10)))),
                  ),
                ),
              );
            }),
        ],
      ),
      if (more)
        TextButton(
          onPressed: () => setState(() => _seasonAll = true),
          child: Text('시즌 ${all.length}개 전체 보기'),
        ),
    ]);
  }

  Widget _positionSection(PanenkaTokens tokens) {
    return _section('position', '포지션', _q.positions.join(' · '), [
      for (final r in _posRows)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              SizedBox(
                  width: 28,
                  child: Text(r[0], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: tokens.subInk))),
              for (final p in r.skip(1))
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _chip(p, _q.positions.contains(p),
                      () => setState(() => _q.positions.contains(p) ? _q.positions.remove(p) : _q.positions.add(p)),
                      width: 48),
                ),
            ],
          ),
        ),
    ]);
  }

  Widget _rangeSection(PanenkaTokens tokens) {
    final parts = [
      _rangeText('OVR', _q.ovrMin, _q.ovrMax),
      _rangeText('급여', _q.payMin, _q.payMax),
      if (_q.priceMin != null || _q.priceMax != null) '선수 가치',
    ].where((s) => s.isNotEmpty).join(' · ');
    return _section('range', '강화 · OVR · 급여 · 선수 가치', parts, [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(width: 82, child: Text('강화 기준', style: TextStyle(fontSize: 12, color: tokens.mute))),
            Expanded(
                child: StepperField(
                    label: '', value: _q.grade, min: 1, max: 13, suffix: '강', onChanged: (v) => setState(() => _q.grade = v))),
          ],
        ),
      ),
      _range('ovr', 'OVR', _q.ovrMin, _q.ovrMax, (v) => _q.ovrMin = v, (v) => _q.ovrMax = v),
      _range('pay', '급여', _q.payMin, _q.payMax, (v) => _q.payMin = v, (v) => _q.payMax = v),
      // 선수 가치는 만 BP 단위로 입력받아 BP로 바꿔 보낸다
      _range('price', '선수 가치(만)', _q.priceMin == null ? null : _q.priceMin! ~/ 10000,
          _q.priceMax == null ? null : _q.priceMax! ~/ 10000,
          (v) => _q.priceMin = v == null ? null : v * 10000, (v) => _q.priceMax = v == null ? null : v * 10000),
      Text('OVR과 선수 가치는 위 강화 기준으로 찾습니다', style: TextStyle(fontSize: 11, color: tokens.mute)),
    ]);
  }

  Widget _traitSection(PanenkaTokens tokens) {
    final traits = _list('traits');
    final news = traits.where((t) => t['is_new'] == true).toList();
    final normal = traits.where((t) => t['is_new'] != true).toList();
    final summary = [
      if (_q.traits.isNotEmpty) _q.traits.join(', '),
      if (_q.traitsNot.isNotEmpty) '제외 ${_q.traitsNot.join(', ')}',
    ].join(' · ');

    Widget grid(List<Map<String, dynamic>> items) => GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1.2,
          children: [
            for (final t in items)
              TraitTile(
                name: '${t['name']}',
                icon: t['icon']?.toString(),
                iconSize: 24,
                fontSize: 10,
                selected: _q.traits.contains(t['name']),
                excluded: _q.traitsNot.contains(t['name']),
                onTap: () => _cycleTrait('${t['name']}'),
              ),
          ],
        );

    return _section('trait', '특성', summary, [
      Text('한 번 누르면 보유, 한 번 더 누르면 제외 · 각각 3개까지', style: TextStyle(fontSize: 11, color: tokens.mute)),
      const SizedBox(height: 8),
      Text('신규특성 ${news.length}종',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFE8C66A))),
      const SizedBox(height: 6),
      grid(news),
      const SizedBox(height: 8),
      if (_traitAll || normal.any((t) => _q.traits.contains(t['name']) || _q.traitsNot.contains(t['name']))) ...[
        Text('일반 특성', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tokens.mute)),
        const SizedBox(height: 6),
        grid(normal),
      ] else
        TextButton(
          onPressed: () => setState(() => _traitAll = true),
          child: Text('일반 특성 ${normal.length}종 전체 보기'),
        ),
    ]);
  }

  Widget _clubSection(PanenkaTokens tokens) {
    final summary = [_q.leagueName, _q.teamName, _q.nationName, _q.teamcolorName].where((s) => s.isNotEmpty).join(' · ');
    return _section('club', '소속 (리그 · 클럽 · 국적 · 팀컬러)', summary, [
      _pickField('리그', _q.leagueName, () async {
        final r = await _pick('리그', _list('leagues'));
        if (r == null) return;
        setState(() {
          _q.leagueId = (r['id'] as num).toInt();
          _q.leagueName = '${r['name']}';
          // 리그를 바꾸면 그 리그 소속이 아닌 클럽 조건은 지운다
          _q.teamId = null;
          _q.teamName = '';
        });
      }, onClear: () => setState(() {
            _q.leagueId = null;
            _q.leagueName = '';
          })),
      _pickField('클럽', _q.teamName, () async {
        final teams = _list('teams');
        final r = await _pick('클럽',
            _q.leagueId == null ? teams : teams.where((t) => (t['league'] as num?)?.toInt() == _q.leagueId).toList());
        if (r == null) return;
        setState(() {
          _q.teamId = (r['id'] as num).toInt();
          _q.teamName = '${r['name']}';
        });
      }, onClear: () => setState(() {
            _q.teamId = null;
            _q.teamName = '';
          })),
      if (_q.teamId != null)
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('클럽 경력 포함', style: TextStyle(fontSize: 12.5)),
          subtitle: Text('끄면 현재 소속 선수만 찾습니다', style: TextStyle(fontSize: 11, color: tokens.mute)),
          value: _q.clubHistory,
          onChanged: (v) => setState(() => _q.clubHistory = v),
        ),
      _pickField('국적', _q.nationName, () async {
        final r = await _pick('국적', _list('nations'));
        if (r == null) return;
        setState(() {
          _q.nationId = (r['id'] as num).toInt();
          _q.nationName = '${r['name']}';
        });
      }, onClear: () => setState(() {
            _q.nationId = null;
            _q.nationName = '';
          })),
      _pickField('팀컬러', _q.teamcolorName, () async {
        final list = await PlayerApi.teamcolors();
        if (!mounted) return;
        final r = await _pick('팀컬러', list);
        if (r == null) return;
        setState(() {
          _q.teamcolorId = (r['id'] as num).toInt();
          _q.teamcolorName = '${r['name']}';
        });
      }, onClear: () => setState(() {
            _q.teamcolorId = null;
            _q.teamcolorName = '';
          })),
    ]);
  }

  Widget _abilitySection(PanenkaTokens tokens) {
    final abilities = [for (final a in _list('abilities')) {'id': a['key'], 'name': a['name']}];
    String nameOf(String key) =>
        '${abilities.firstWhere((a) => a['id'] == key, orElse: () => {'name': key})['name']}';
    return _section(
        'ability',
        '세부 능력 (3개까지)',
        _q.abilities.map((a) => '${nameOf(a.key)}${a.min != null ? ' ${a.min} 이상' : ''}').join(' · '),
        [
          for (var i = 0; i < _q.abilities.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                      width: 96,
                      child: Text(nameOf(_q.abilities[i].key),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
                  _num('ab-$i-${_q.abilities[i].key}-min', _q.abilities[i].min, '최소',
                      (v) => _q.abilities[i] = AbilityCond(_q.abilities[i].key, min: v, max: _q.abilities[i].max)),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text('~', style: TextStyle(color: tokens.mute))),
                  _num('ab-$i-${_q.abilities[i].key}-max', _q.abilities[i].max, '최대',
                      (v) => _q.abilities[i] = AbilityCond(_q.abilities[i].key, min: _q.abilities[i].min, max: v)),
                  IconButton(
                      tooltip: '이 능력 조건 지우기',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _q.abilities.removeAt(i)),
                      icon: Icon(Icons.close, size: 16, color: tokens.mute)),
                ],
              ),
            ),
          if (_q.abilities.length < PlayerQuery.maxAbilities)
            OutlinedButton.icon(
              onPressed: () async {
                final used = _q.abilities.map((a) => a.key).toSet();
                final r = await _pick('세부 능력', abilities.where((a) => !used.contains(a['id'])).toList());
                if (r == null) return;
                setState(() => _q.abilities.add(AbilityCond('${r['id']}')));
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('능력 추가'),
            ),
          if (_q.abilities.any((a) => a.min == null && a.max == null))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('최소나 최대 값을 넣어야 조건으로 적용됩니다', style: TextStyle(fontSize: 11, color: tokens.mute)),
            ),
        ]);
  }

  Widget _bodySection(PanenkaTokens tokens) {
    final summary = [
      _rangeText('키', _q.heightMin, _q.heightMax),
      _rangeText('몸무게', _q.weightMin, _q.weightMax),
      _q.bodyTypes.map((b) => _bodyLabels[b] ?? b).join('/'),
      if (_q.mainFoot.isNotEmpty) _q.mainFoot == 'L' ? '왼발' : '오른발',
      if (_q.weakFoot != null) '약발 ${_q.weakFoot}',
      if (_q.skillMove != null) '개인기 ${_q.skillMove}성',
    ].where((s) => s.isNotEmpty).join(' · ');

    Widget label(String t) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Text(t, style: TextStyle(fontSize: 12, color: tokens.mute)));

    return _section('body', '신체 (키 · 몸무게 · 체격 · 주발 · 약발 · 개인기)', summary, [
      _range('height', '키', _q.heightMin, _q.heightMax, (v) => _q.heightMin = v, (v) => _q.heightMax = v),
      _range('weight', '몸무게', _q.weightMin, _q.weightMax, (v) => _q.weightMin = v, (v) => _q.weightMax = v),
      label('체격'),
      Wrap(spacing: 6, children: [
        for (final e in _bodyLabels.entries)
          _chip(e.value, _q.bodyTypes.contains(e.key),
              () => setState(() => _q.bodyTypes.contains(e.key) ? _q.bodyTypes.remove(e.key) : _q.bodyTypes.add(e.key))),
      ]),
      label('주발'),
      Wrap(spacing: 6, children: [
        _chip('왼발', _q.mainFoot == 'L', () => setState(() => _q.mainFoot = _q.mainFoot == 'L' ? '' : 'L')),
        _chip('오른발', _q.mainFoot == 'R', () => setState(() => _q.mainFoot = _q.mainFoot == 'R' ? '' : 'R')),
      ]),
      label('약발'),
      Wrap(spacing: 6, children: [
        for (var i = 1; i <= 5; i++)
          _chip('$i', _q.weakFoot == i, () => setState(() => _q.weakFoot = _q.weakFoot == i ? null : i), width: 44),
      ]),
      label('개인기'),
      Wrap(spacing: 6, children: [
        for (var i = 1; i <= 6; i++)
          _chip('$i성', _q.skillMove == i, () => setState(() => _q.skillMove = _q.skillMove == i ? null : i), width: 48),
      ]),
    ]);
  }

  Widget _etcSection(PanenkaTokens tokens) {
    final summary = [
      _rangeText('출생', _q.birthMin, _q.birthMax),
      if (_q.reputation != null) _reputations[_q.reputation] ?? '',
    ].where((s) => s.isNotEmpty).join(' · ');
    return _section('etc', '기타 (출생년도 · 명성)', summary, [
      _range('birth', '출생년도', _q.birthMin, _q.birthMax, (v) => _q.birthMin = v, (v) => _q.birthMax = v),
      Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Text('명성', style: TextStyle(fontSize: 12, color: tokens.mute))),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final e in _reputations.entries)
          _chip(e.value, _q.reputation == e.key,
              () => setState(() => _q.reputation = _q.reputation == e.key ? null : e.key)),
      ]),
    ]);
  }
}
