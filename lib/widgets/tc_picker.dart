import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';

/// 팀컬러 선택 1건 (칸 하나에 팀컬러 1개 × 단계 1개).
///
/// 집훈 계산기에서 쓰던 것을 선수 상세·비교 화면과 같이 쓰려고 공용으로 분리 (2026-09-30).
/// '전체 능력치 +N'은 [all], 세부 효과(예: 시야 +3)는 [detail]에 담는다.
class TcPick {
  final String section;
  final int tcId;
  final String name;
  final int level;
  final int count;
  final int all;
  final Map<String, int> detail;
  const TcPick(this.section, this.tcId, this.name, this.level, this.count, this.all, this.detail);

  /// tcId 0 = '—' (선택 해제)
  static const none = TcPick('', 0, '', 0, 0, 0, {});

  factory TcPick.from(String section, Map<String, dynamic> item, Map lv) {
    final detail = <String, int>{};
    for (final e in (lv['effects'] as List? ?? const [])) {
      final stat = '${e['stat']}';
      if (stat == '전체 능력치') continue;
      detail[stat] = (detail[stat] ?? 0) + ((e['value'] as num?)?.toInt() ?? 0);
    }
    return TcPick(section, (item['tc_id'] as num).toInt(), '${item['name'] ?? ''}',
        (lv['level'] as num?)?.toInt() ?? 1, (lv['count'] as num?)?.toInt() ?? 0,
        (lv['all'] as num?)?.toInt() ?? 0, detail);
  }

  String get effectText {
    final parts = <String>['$count명'];
    if (all > 0) parts.add('전체 +$all');
    parts.addAll(detail.entries.map((e) => '${e.key} +${e.value}'));
    return parts.join(' · ');
  }
}

/// 팀컬러 선택 시트: 검색 + 'LvN. 이름' 목록 (카드에 해당하는 것만)
class TcSheet extends StatefulWidget {
  final String title;
  final String section;
  final List<Map<String, dynamic>> items;
  final TcPick? current;
  final int grade;
  const TcSheet({super.key, required this.title, required this.section, required this.items, required this.current, required this.grade});

  @override
  State<TcSheet> createState() => _TcSheetState();
}

class _TcSheetState extends State<TcSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final muted = Colors.grey.shade500;
    final tokens = PanenkaTokens.of(context);
    final rows = <TcPick>[];
    for (final it in widget.items) {
      final name = '${it['name'] ?? ''}';
      if (_q.isNotEmpty && !name.toLowerCase().contains(_q.toLowerCase())) continue;
      for (final lv in (it['levels'] as List? ?? const [])) {
        rows.add(TcPick.from(widget.section, it, lv as Map));
      }
    }
    final minGrade = {for (final it in widget.items) (it['tc_id'] as num).toInt(): (it['min_grade'] as num?)?.toInt() ?? 0};
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .78),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(width: 36, height: 4, decoration: BoxDecoration(color: muted.withOpacity(.5), borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Row(children: [
                  Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 6),
                  Text('이 카드에 해당하는 것만', style: TextStyle(fontSize: 11, color: muted)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  onChanged: (v) => setState(() => _q = v.trim()),
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
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: rows.length + 1,
                  separatorBuilder: (_, __) => Divider(height: 1, color: muted.withOpacity(.15)),
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      final on = widget.current == null;
                      return ListTile(
                        dense: true,
                        title: const Text('—'),
                        subtitle: Text('적용 안 함', style: TextStyle(fontSize: 11, color: muted)),
                        trailing: on ? Icon(Icons.check, color: tokens.accentInk, size: 18) : null,
                        onTap: () => Navigator.pop(context, TcPick.none),
                      );
                    }
                    final p = rows[i - 1];
                    final on = widget.current != null && widget.current!.tcId == p.tcId && widget.current!.level == p.level;
                    final mg = minGrade[p.tcId] ?? 0;
                    final under = mg > 0 && widget.grade < mg;
                    return ListTile(
                      dense: true,
                      title: Text('Lv${p.level}. ${p.name}',
                          style: TextStyle(fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: under ? muted : null)),
                      subtitle: Text('${p.effectText}${mg > 0 ? ' · $mg강 이상' : ''}', style: TextStyle(fontSize: 11, color: muted)),
                      trailing: on ? Icon(Icons.check, color: tokens.accentInk, size: 18) : null,
                      onTap: () => Navigator.pop(context, p),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
