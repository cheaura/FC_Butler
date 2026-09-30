/// 선수 검색 조건 (2026-09-30, '선수(집훈)' 탭).
///
/// 서버 `/api/user/player/search`의 요청 인자와 1:1로 대응한다 (utils/player_search.py query_from_args).
/// 목록 값은 쉼표 구분, 세부 능력은 `키:최소:최대`.
class AbilityCond {
  const AbilityCond(this.key, {this.min, this.max});

  final String key;
  final int? min;
  final int? max;

  Map<String, dynamic> toJson() => {'key': key, 'min': min, 'max': max};

  static AbilityCond? fromJson(dynamic j) {
    if (j is! Map || j['key'] == null) return null;
    return AbilityCond('${j['key']}', min: (j['min'] as num?)?.toInt(), max: (j['max'] as num?)?.toInt());
  }
}

class PlayerQuery {
  PlayerQuery({this.name = ''});

  /// 쉼표로 한 번에 검색할 수 있는 이름 수 (서버 MAX_NAMES와 같음)
  static const maxNames = 10;
  static const maxTraits = 3;
  static const maxAbilities = 3;

  String name;
  Set<int> seasons = {};
  Set<String> positions = {};

  /// 강화 기준 — 목록에 표시하는 OVR·시세와 OVR·선수 가치 조건에 적용
  int grade = 1;
  int? ovrMin, ovrMax, payMin, payMax, priceMin, priceMax;
  int? leagueId, teamId, nationId, teamcolorId;

  /// 조건 표시용 이름 (서버로 보내지 않음)
  String leagueName = '', teamName = '', nationName = '', teamcolorName = '';
  bool clubHistory = true;
  List<String> traits = [];
  List<String> traitsNot = [];
  List<AbilityCond> abilities = [];
  int? birthMin, birthMax, heightMin, heightMax, weightMin, weightMax;
  Set<String> bodyTypes = {};
  String mainFoot = '';
  int? weakFoot, skillMove, reputation;
  String sort = 'ovr';
  bool desc = true;

  /// '손흥민, 메시' → ['손흥민', '메시'] (빈 값·중복 제거, [maxNames]개까지). 전각 쉼표도 받는다.
  static List<String> parseNames(String? text) {
    final out = <String>[];
    for (final part in (text ?? '').split(RegExp('[,，、]'))) {
      final n = part.trim();
      if (n.isNotEmpty && !out.contains(n)) out.add(n);
      if (out.length >= maxNames) break;
    }
    return out;
  }

  List<String> get names => parseNames(name);

  /// 이름을 뺀 조건 묶음 수 (조건 버튼의 숫자)
  int get conditionCount {
    var n = 0;
    if (seasons.isNotEmpty) n++;
    if (positions.isNotEmpty) n++;
    if (ovrMin != null || ovrMax != null) n++;
    if (payMin != null || payMax != null) n++;
    if (priceMin != null || priceMax != null) n++;
    if (leagueId != null) n++;
    if (teamId != null) n++;
    if (nationId != null) n++;
    if (teamcolorId != null) n++;
    if (traits.isNotEmpty) n++;
    if (traitsNot.isNotEmpty) n++;
    n += abilities.length;
    if (birthMin != null || birthMax != null) n++;
    if (heightMin != null || heightMax != null) n++;
    if (weightMin != null || weightMax != null) n++;
    if (bodyTypes.isNotEmpty) n++;
    if (mainFoot.isNotEmpty) n++;
    if (weakFoot != null) n++;
    if (skillMove != null) n++;
    if (reputation != null) n++;
    return n;
  }

  /// 이름도 조건도 없는 검색
  bool get isEmpty => names.isEmpty && conditionCount == 0;

  /// 서버 요청 인자
  Map<String, String> toParams() {
    final p = <String, String>{};
    void put(String k, Object? v) {
      if (v != null && '$v'.isNotEmpty) p[k] = '$v';
    }

    put('name', names.join(','));
    put('seasons', seasons.join(','));
    put('positions', positions.join(','));
    if (grade != 1) p['grade'] = '$grade';
    put('ovr_min', ovrMin);
    put('ovr_max', ovrMax);
    put('pay_min', payMin);
    put('pay_max', payMax);
    put('price_min', priceMin);
    put('price_max', priceMax);
    put('league', leagueId);
    put('team', teamId);
    put('nation', nationId);
    if (teamId != null && !clubHistory) p['history'] = '0';
    put('teamcolor', teamcolorId);
    put('traits', traits.take(maxTraits).join(','));
    put('traits_not', traitsNot.take(maxTraits).join(','));
    put('abilities',
        abilities.take(maxAbilities).map((a) => '${a.key}:${a.min ?? ''}:${a.max ?? ''}').join(','));
    put('birth_min', birthMin);
    put('birth_max', birthMax);
    put('height_min', heightMin);
    put('height_max', heightMax);
    put('weight_min', weightMin);
    put('weight_max', weightMax);
    put('body', bodyTypes.join(','));
    put('main_foot', mainFoot);
    put('weak_foot', weakFoot);
    put('skill_move', skillMove);
    put('reputation', reputation);
    if (sort != 'ovr') p['sort'] = sort;
    if (!desc) p['desc'] = '0';
    return p;
  }

  PlayerQuery copy() => PlayerQuery.fromJson(toJson());

  /// 조건만 비운다 (이름·강화 기준·정렬은 유지)
  void clearConditions() {
    seasons = {};
    positions = {};
    ovrMin = ovrMax = payMin = payMax = priceMin = priceMax = null;
    leagueId = teamId = nationId = teamcolorId = null;
    leagueName = teamName = nationName = teamcolorName = '';
    clubHistory = true;
    traits = [];
    traitsNot = [];
    abilities = [];
    birthMin = birthMax = heightMin = heightMax = weightMin = weightMax = null;
    bodyTypes = {};
    mainFoot = '';
    weakFoot = skillMove = reputation = null;
  }

  /// 최근 검색 저장용
  Map<String, dynamic> toJson() => {
        'name': name,
        'seasons': seasons.toList(),
        'positions': positions.toList(),
        'grade': grade,
        'ovr_min': ovrMin,
        'ovr_max': ovrMax,
        'pay_min': payMin,
        'pay_max': payMax,
        'price_min': priceMin,
        'price_max': priceMax,
        'league': leagueId,
        'team': teamId,
        'nation': nationId,
        'teamcolor': teamcolorId,
        'league_name': leagueName,
        'team_name': teamName,
        'nation_name': nationName,
        'teamcolor_name': teamcolorName,
        'history': clubHistory,
        'traits': traits,
        'traits_not': traitsNot,
        'abilities': abilities.map((a) => a.toJson()).toList(),
        'birth_min': birthMin,
        'birth_max': birthMax,
        'height_min': heightMin,
        'height_max': heightMax,
        'weight_min': weightMin,
        'weight_max': weightMax,
        'body': bodyTypes.toList(),
        'main_foot': mainFoot,
        'weak_foot': weakFoot,
        'skill_move': skillMove,
        'reputation': reputation,
        'sort': sort,
        'desc': desc,
      };

  static PlayerQuery fromJson(dynamic j) {
    final q = PlayerQuery();
    if (j is! Map) return q;
    int? i(String k) => (j[k] as num?)?.toInt();
    q.name = '${j['name'] ?? ''}';
    q.seasons = {for (final s in (j['seasons'] as List? ?? const [])) (s as num).toInt()};
    q.positions = {for (final s in (j['positions'] as List? ?? const [])) '$s'};
    q.grade = i('grade') ?? 1;
    q.ovrMin = i('ovr_min');
    q.ovrMax = i('ovr_max');
    q.payMin = i('pay_min');
    q.payMax = i('pay_max');
    q.priceMin = i('price_min');
    q.priceMax = i('price_max');
    q.leagueId = i('league');
    q.teamId = i('team');
    q.nationId = i('nation');
    q.teamcolorId = i('teamcolor');
    q.leagueName = '${j['league_name'] ?? ''}';
    q.teamName = '${j['team_name'] ?? ''}';
    q.nationName = '${j['nation_name'] ?? ''}';
    q.teamcolorName = '${j['teamcolor_name'] ?? ''}';
    q.clubHistory = j['history'] != false;
    q.traits = [for (final t in (j['traits'] as List? ?? const [])) '$t'];
    q.traitsNot = [for (final t in (j['traits_not'] as List? ?? const [])) '$t'];
    q.abilities = [
      for (final a in (j['abilities'] as List? ?? const []))
        if (AbilityCond.fromJson(a) != null) AbilityCond.fromJson(a)!
    ];
    q.birthMin = i('birth_min');
    q.birthMax = i('birth_max');
    q.heightMin = i('height_min');
    q.heightMax = i('height_max');
    q.weightMin = i('weight_min');
    q.weightMax = i('weight_max');
    q.bodyTypes = {for (final s in (j['body'] as List? ?? const [])) '$s'};
    q.mainFoot = '${j['main_foot'] ?? ''}';
    q.weakFoot = i('weak_foot');
    q.skillMove = i('skill_move');
    q.reputation = i('reputation');
    q.sort = '${j['sort'] ?? 'ovr'}';
    q.desc = j['desc'] != false;
    return q;
  }

  /// 같은 검색인지 판정하는 키 (최근 검색 중복 제거·결과 보관)
  String get key {
    final p = toParams();
    final keys = p.keys.toList()..sort();
    return keys.map((k) => '$k=${p[k]}').join('&');
  }
}
