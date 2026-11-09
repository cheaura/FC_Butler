import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';
import '../utils/fc_format.dart';

// 일별 달력 (2026-11-09, 검색 탭 '일별' 세그 F안)
// - 7열 월 달력. 칸: 날짜 · 승-무-패 · FC (세 줄은 폰 폭에 안 들어가 승률은 선택일 상세에서)
// - 오늘 = 강조색 테두리, 선택 = 강조 연한 바탕
// - 표식 점: 노랑 = 이달 최다 채굴일, 강조색 = 이달 최고 승률일(서버 기준 5경기 이상)
// - 승·무·패 숫자는 한 가지 색 (사용자 지정: 색 구분 금지)
// 서버 응답(days[]·summary·best_fc_date·best_winrate_date)은 /api/user/lookup/daily 와
// /api/user/daily-calendar 가 같은 형태라 두 화면에서 재사용 가능

/// 최다 채굴 표식 색 (프리셋과 무관하게 고정 — 금색)
const Color kDailyBestFcColor = Color(0xFFF2C14E);

/// 하루치 집계 (서버 days[] 항목)
class DailyDay {
  final String date; // 'YYYY-MM-DD'
  final int wins;
  final int draws;
  final int losses;
  final int games;
  final double winRate;
  final int fc;

  const DailyDay({
    required this.date,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.games,
    required this.winRate,
    required this.fc,
  });

  factory DailyDay.fromJson(Map<String, dynamic> j) => DailyDay(
        date: j['date']?.toString() ?? '',
        wins: (j['wins'] as num? ?? 0).toInt(),
        draws: (j['draws'] as num? ?? 0).toInt(),
        losses: (j['losses'] as num? ?? 0).toInt(),
        games: (j['games'] as num? ?? 0).toInt(),
        winRate: (j['win_rate'] as num? ?? 0).toDouble(),
        fc: (j['fc'] as num? ?? 0).toInt(),
      );

  /// 일(day) 숫자
  int get day => int.tryParse(date.length >= 10 ? date.substring(8, 10) : '') ?? 0;
}

/// 서버 응답 전체 → 달력에 필요한 값 묶음
class DailyMonthData {
  final int year;
  final int month;
  final Map<String, DailyDay> days;
  final Map<String, dynamic> summary;
  final String? bestFcDate;
  final String? bestWinrateDate;
  final int bestMinGames;

  const DailyMonthData({
    required this.year,
    required this.month,
    required this.days,
    required this.summary,
    required this.bestFcDate,
    required this.bestWinrateDate,
    required this.bestMinGames,
  });

  factory DailyMonthData.fromJson(Map<String, dynamic> j) {
    final m = (j['month']?.toString() ?? '').split('-');
    final year = m.isNotEmpty ? int.tryParse(m[0]) ?? DateTime.now().year : DateTime.now().year;
    final month = m.length > 1 ? int.tryParse(m[1]) ?? DateTime.now().month : DateTime.now().month;
    final days = <String, DailyDay>{};
    for (final d in (j['days'] as List? ?? [])) {
      if (d is Map) {
        final dd = DailyDay.fromJson(Map<String, dynamic>.from(d));
        if (dd.date.isNotEmpty) days[dd.date] = dd;
      }
    }
    return DailyMonthData(
      year: year,
      month: month,
      days: days,
      summary: Map<String, dynamic>.from(j['summary'] as Map? ?? {}),
      bestFcDate: j['best_fc_date']?.toString(),
      bestWinrateDate: j['best_winrate_date']?.toString(),
      bestMinGames: (j['best_min_games'] as num? ?? 5).toInt(),
    );
  }
}

String _ymd(int y, int m, int d) =>
    '$y-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';

String dailyTodayKey() {
  final n = DateTime.now();
  return _ymd(n.year, n.month, n.day);
}

const List<String> _kDow = ['일', '월', '화', '수', '목', '금', '토'];

/// 월 달력 본체
class DailyCalendar extends StatelessWidget {
  final DailyMonthData data;
  final String? selected;
  final ValueChanged<String> onPick;

  const DailyCalendar({
    Key? key,
    required this.data,
    required this.selected,
    required this.onPick,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tokens = PanenkaTokens.of(context);
    final today = dailyTodayKey();
    final first = DateTime(data.year, data.month, 1).weekday % 7; // 일요일=0
    final dim = DateTime(data.year, data.month + 1, 0).day;
    final totalCells = ((first + dim + 6) ~/ 7) * 7;

    final rows = <Widget>[
      Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Center(
                child: Text(_kDow[i],
                    style: TextStyle(
                        fontSize: 11,
                        color: i == 0 ? tokens.loseInk : tokens.mute)),
              ),
            ),
        ],
      ),
      const SizedBox(height: 3),
    ];
    for (var start = 0; start < totalCells; start += 7) {
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = start; i < start + 7; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(1.5),
                child: _cell(context, tokens, i - first + 1, dim, i % 7 == 0, today),
              ),
            ),
        ],
      ));
    }
    return Column(children: rows);
  }

  Widget _cell(BuildContext context, PanenkaTokens tokens, int day, int dim,
      bool isSunday, String today) {
    if (day < 1 || day > dim) return const SizedBox(height: 56);
    final key = _ymd(data.year, data.month, day);
    final rec = data.days[key];
    final isToday = key == today;
    final isSel = key == selected;
    final dateStyle = TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: isSunday ? tokens.loseInk : tokens.mute);

    if (rec == null) {
      // 경기 없는 날: 점선 빈 칸
      return Container(
        height: 56,
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isToday ? tokens.accentInk : tokens.line,
              width: isToday ? 1.5 : 1),
        ),
        alignment: Alignment.topLeft,
        child: Opacity(opacity: 0.6, child: Text('$day', style: dateStyle)),
      );
    }

    final isBestFc = key == data.bestFcDate;
    final isBestWr = key == data.bestWinrateDate;
    final numStyle = TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: tokens.ink,
        letterSpacing: -0.2);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onPick(key),
      child: Container(
        height: 56,
        padding: const EdgeInsets.fromLTRB(4, 4, 3, 3),
        decoration: BoxDecoration(
          color: isSel ? tokens.accentSoft : tokens.soft,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isToday ? tokens.accentInk : Colors.transparent, width: 1.5),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$day', style: dateStyle),
                const SizedBox(height: 1),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('${rec.wins}-${rec.draws}-${rec.losses}',
                      maxLines: 1, softWrap: false, style: numStyle),
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: fmtThousands(rec.fc), style: numStyle),
                      TextSpan(
                          text: 'FC',
                          style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w500,
                              color: tokens.mute)),
                    ]),
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ],
            ),
            if (isBestFc || isBestWr)
              Positioned(
                top: 0,
                right: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isBestFc) _dot(kDailyBestFcColor),
                    if (isBestFc && isBestWr) const SizedBox(width: 2),
                    if (isBestWr) _dot(tokens.accentInk),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color c) => Container(
      width: 7, height: 7,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}

/// 달력 아래 범례 (점 2종 + 오늘)
class DailyLegend extends StatelessWidget {
  const DailyLegend({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tokens = PanenkaTokens.of(context);
    final style = TextStyle(fontSize: 10.5, color: tokens.mute);
    Widget dot(Color c) => Container(
        width: 7, height: 7, margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(color: c, shape: BoxShape.circle));
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [dot(kDailyBestFcColor), Text('최다 채굴', style: style)]),
        Row(mainAxisSize: MainAxisSize.min, children: [dot(tokens.accentInk), Text('최고 승률', style: style)]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 9, height: 9, margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                  border: Border.all(color: tokens.accentInk, width: 1.5),
                  borderRadius: BorderRadius.circular(2))),
          Text('오늘', style: style),
        ]),
      ],
    );
  }
}

/// 선택한 날 상세: 날짜(요일) · 전적 · 승률(총 경기) · 채굴 + 표식 배지
class DailyDetailCard extends StatelessWidget {
  final DailyDay day;
  final bool isToday;
  final bool isBestFc;
  final bool isBestWr;

  const DailyDetailCard({
    Key? key,
    required this.day,
    required this.isToday,
    required this.isBestFc,
    required this.isBestWr,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tokens = PanenkaTokens.of(context);
    final parts = day.date.split('-');
    final dt = parts.length == 3
        ? DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]))
        : DateTime.now();
    final lineLabel = TextStyle(fontSize: 13, color: tokens.mute);
    const lineValue = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
    Widget line(String k, Widget v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [Text(k, style: lineLabel), const Spacer(), v]),
        );
    Widget badge(String text, Color bg, Color fg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
          child: Text(text,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg, height: 1.0)),
        );
    return Card(
      margin: const EdgeInsets.only(top: 10, bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                      '${dt.month}월 ${dt.day}일 (${_kDow[dt.weekday % 7]})${isToday ? ' · 오늘' : ''}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                ),
                Text('${day.games}경기', style: TextStyle(fontSize: 12, color: tokens.mute)),
              ],
            ),
            if (isBestFc || isBestWr)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(spacing: 4, children: [
                  if (isBestFc) badge('이달 최다 채굴', kDailyBestFcColor, const Color(0xFF1A1400)),
                  if (isBestWr) badge('이달 최고 승률', tokens.accentInk, panenkaOnFill(tokens.accentInk)),
                ]),
              ),
            const SizedBox(height: 6),
            line('전적', Text('${day.wins}승 ${day.draws}무 ${day.losses}패', style: lineValue)),
            line('승률', Text('${day.winRate.toStringAsFixed(1)}% (총 ${day.games}경기)', style: lineValue)),
            line('채굴', Text('${fmtThousands(day.fc)} FC', style: lineValue)),
          ],
        ),
      ),
    );
  }
}

/// 이달 합계 3칸 + 최다 채굴일·최고 승률일 2칸
class DailySummaryTiles extends StatelessWidget {
  final DailyMonthData data;

  const DailySummaryTiles({Key? key, required this.data}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final tokens = PanenkaTokens.of(context);
    final s = data.summary;
    final games = (s['games'] as num? ?? 0).toInt();
    final bf = data.bestFcDate != null ? data.days[data.bestFcDate!] : null;
    final bw = data.bestWinrateDate != null ? data.days[data.bestWinrateDate!] : null;
    final kStyle = TextStyle(fontSize: 10.5, color: tokens.mute);
    const vStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w800);
    final smallStyle = TextStyle(fontSize: 10.5, color: tokens.mute);

    Widget tile(Widget k, Widget v) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(color: tokens.card, borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [k, const SizedBox(height: 2), v],
            ),
          ),
        );
    Widget dotLabel(Color c, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 7, height: 7, margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          Text(text, style: kStyle),
        ]);

    if (games == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('이 달에 수집된 경기가 없습니다.',
              style: TextStyle(fontSize: 13, color: tokens.mute)),
        ),
      );
    }
    return Column(
      children: [
        Row(children: [
          tile(Text('이달 전적', style: kStyle),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                  child: Text('${s['wins']}-${s['draws']}-${s['losses']}', style: vStyle))),
          const SizedBox(width: 6),
          tile(Text('이달 승률', style: kStyle),
              Text('${(s['win_rate'] as num? ?? 0).toStringAsFixed(1)}%', style: vStyle)),
          const SizedBox(width: 6),
          tile(Text('이달 채굴', style: kStyle),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                  child: Text('${fmtThousands(s['fc'])} FC', style: vStyle))),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          tile(
            dotLabel(kDailyBestFcColor, '최다 채굴'),
            bf == null
                ? Text('-', style: vStyle)
                : Text.rich(TextSpan(children: [
                    TextSpan(text: '${bf.day}일 ', style: vStyle),
                    TextSpan(text: '${fmtThousands(bf.fc)} FC', style: smallStyle),
                  ])),
          ),
          const SizedBox(width: 6),
          tile(
            dotLabel(tokens.accentInk, '최고 승률 (${data.bestMinGames}경기↑)'),
            bw == null
                ? Text('-', style: vStyle)
                : Text.rich(TextSpan(children: [
                    TextSpan(text: '${bw.day}일 ', style: vStyle),
                    TextSpan(
                        text: '${bw.winRate.toStringAsFixed(1)}% · ${bw.games}경기',
                        style: smallStyle),
                  ])),
          ),
        ]),
      ],
    );
  }
}
