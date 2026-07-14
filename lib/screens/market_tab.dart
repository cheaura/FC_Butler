// 이적시장 거래기록 탭 (2026-07-14) — 웹 대시보드 이적시장 섹션의 모바일 버전
// 서버 API는 웹과 동일: /api/user/nexon-key*, /api/user/market/*
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class MarketTab extends StatefulWidget {
  final String username;

  const MarketTab({Key? key, required this.username}) : super(key: key);

  @override
  State<MarketTab> createState() => _MarketTabState();
}

class _MarketTabState extends State<MarketTab> with AutomaticKeepAliveClientMixin {
  final ApiService _api = ApiService();

  // 키 상태
  bool _keyChecked = false;
  bool _keyRegistered = false;
  String _keyMasked = '';
  final TextEditingController _keyController = TextEditingController();
  bool _keySaving = false;

  // 거래내역
  String _tradeType = 'all';
  final TextEditingController _playerController = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _note;
  Map<String, dynamic>? _realized;

  // 스쿼드 손익
  bool _pnlLoading = false;
  Map<String, dynamic>? _pnl;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _checkKey();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _playerController.dispose();
    super.dispose();
  }

  Future<void> _checkKey() async {
    final res = await _api.getNexonKeyStatus(widget.username);
    if (!mounted) return;
    setState(() {
      _keyChecked = true;
      _keyRegistered = res['registered'] == true;
      _keyMasked = res['masked']?.toString() ?? '';
    });
    if (_keyRegistered) {
      _loadTrades(reset: true);
    }
  }

  Future<void> _saveKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    setState(() => _keySaving = true);
    final res = await _api.registerNexonKey(widget.username, key);
    if (!mounted) return;
    setState(() => _keySaving = false);
    final msg = res['message']?.toString() ?? res['error']?.toString() ?? '';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    if (res['success'] == true) {
      _keyController.clear();
      _checkKey();
    }
  }

  Future<void> _deleteKey() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('API 키 삭제'),
        content: const Text('등록된 넥슨 API 키를 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    await _api.deleteNexonKey(widget.username);
    if (!mounted) return;
    setState(() {
      _keyRegistered = false;
      _items = [];
      _total = 0;
    });
  }

  Future<void> _loadTrades({required bool reset}) async {
    if (_loading || _loadingMore) return;
    setState(() {
      if (reset) {
        _loading = true;
        _items = [];
        _total = 0;
        _note = null;
        _realized = null;
      } else {
        _loadingMore = true;
      }
    });
    final res = await _api.getTradeHistory(
      username: widget.username,
      type: _tradeType,
      player: _playerController.text.trim(),
      offset: reset ? 0 : _items.length,
      limit: 30,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadingMore = false;
      if (res['success'] == true) {
        _total = (res['total'] as num?)?.toInt() ?? 0;
        _items.addAll(List<Map<String, dynamic>>.from(res['items'] ?? []));
        _note = res['note']?.toString();
        _realized = res['realized'] as Map<String, dynamic>?;
      } else if (res['error'] == 'NO_API_KEY') {
        _keyRegistered = false;
      } else {
        _note = res['message']?.toString() ?? res['error']?.toString() ?? '조회 실패';
      }
    });
  }

  Future<void> _loadPnl() async {
    setState(() => _pnlLoading = true);
    final res = await _api.getSquadPnl(widget.username);
    if (!mounted) return;
    setState(() {
      _pnlLoading = false;
      _pnl = res;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_keyChecked) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_keyRegistered) {
      return _buildKeyRegister();
    }
    return RefreshIndicator(
      onRefresh: () => _loadTrades(reset: true),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildKeyStatusRow(),
          const SizedBox(height: 8),
          _buildFilterRow(),
          const SizedBox(height: 8),
          if (_realized != null) _buildRealizedCard(),
          _buildSummaryLine(),
          const SizedBox(height: 4),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: Text(_note ?? '거래 내역이 없습니다.')),
            )
          else
            ..._items.map(_buildTradeCard),
          if (!_loading && _items.length < _total)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: _loadingMore ? null : () => _loadTrades(reset: false),
                  icon: _loadingMore
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.expand_more),
                  label: const Text('더 불러오기'),
                ),
              ),
            ),
          const Divider(height: 32),
          _buildSquadPnlSection(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildKeyRegister() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: const [
                  Icon(Icons.vpn_key, size: 20),
                  SizedBox(width: 8),
                  Text('넥슨 API 키 등록', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 8),
                const Text(
                  '거래기록 조회에는 넥슨 오픈API 키가 필요합니다.\n'
                  'openapi.nexon.com 에서 발급한 키(live_ 또는 test_ 로 시작)를 입력하세요.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _keyController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    hintText: 'live_...',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _keySaving ? null : _saveKey,
                    child: _keySaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('등록'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKeyStatusRow() {
    return Row(
      children: [
        const Icon(Icons.vpn_key, size: 16, color: Colors.green),
        const SizedBox(width: 6),
        Expanded(
          child: Text('API 키 등록됨 $_keyMasked',
              style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
        ),
        TextButton(onPressed: _deleteKey, child: const Text('키 삭제', style: TextStyle(fontSize: 12))),
      ],
    );
  }

  Widget _buildFilterRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final t in const [
              ['all', '전체'],
              ['buy', '구매'],
              ['sell', '판매'],
            ])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(t[1], style: const TextStyle(fontSize: 12)),
                  selected: _tradeType == t[0],
                  onSelected: (_) {
                    setState(() => _tradeType = t[0]);
                    _loadTrades(reset: true);
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _playerController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  hintText: '선수명 검색 (예: 홀란)',
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                style: const TextStyle(fontSize: 13),
                onSubmitted: (_) => _loadTrades(reset: true),
              ),
            ),
            const SizedBox(width: 6),
            ElevatedButton(
              onPressed: () => _loadTrades(reset: true),
              child: const Text('조회'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryLine() {
    if (_total == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text('총 $_total건 중 ${_items.length}건 표시',
          style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
    );
  }

  Widget _buildRealizedCard() {
    final r = _realized!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          '실현손익: 구매 ${r['buyDisplay'] ?? '-'} → 판매 ${r['sellDisplay'] ?? '-'} '
          '(${r['profitDisplay'] ?? '-'})',
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildTradeCard(Map<String, dynamic> it) {
    final dt = (it['tradeDate']?.toString() ?? '').replaceFirst('T', ' ');
    final dtShort = dt.length >= 16 ? dt.substring(0, 16) : dt;
    final isSell = it['tradeType'] == 'sell';
    final grade = it['grade'] != null ? '${it['grade']}강' : '';
    Widget? profitWidget;
    if (it['profit'] != null) {
      final type = it['profitType']?.toString();
      final sign = type == 'gain' ? '+' : (type == 'loss' ? '-' : '');
      final color = type == 'gain'
          ? Colors.red
          : (type == 'loss' ? Colors.blue : Theme.of(context).hintColor);
      final pct = it['profitPercent'] != null ? ' (${sign}${(it['profitPercent'] as num).abs()}%)' : '';
      profitWidget = Text('$sign${it['profitDisplay'] ?? '0'}$pct',
          style: TextStyle(fontSize: 12, color: color));
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (isSell ? Colors.blue : Colors.red).withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(isSell ? '판매' : '구매',
                  style: TextStyle(fontSize: 11, color: isSell ? Colors.blue : Colors.red)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${it['season'] ?? ''} ${it['playerName'] ?? '-'} $grade'.trim(),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(dtShort, style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(it['valueDisplay']?.toString() ?? '-',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                if (profitWidget != null) profitWidget,
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSquadPnlSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('내 스쿼드 손익', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const Spacer(),
            OutlinedButton(
              onPressed: _pnlLoading ? null : _loadPnl,
              child: _pnlLoading
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('불러오기'),
            ),
          ],
        ),
        Text('최근 경기 라인업 선수들의 구매가 vs 현재 시세',
            style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
        const SizedBox(height: 8),
        if (_pnl != null) _buildPnlBody(),
      ],
    );
  }

  Widget _buildPnlBody() {
    final p = _pnl!;
    if (p['success'] != true) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(p['error']?.toString() ?? '조회 실패', style: const TextStyle(fontSize: 13)),
      );
    }
    final items = List<Map<String, dynamic>>.from(p['items'] ?? []);
    final summary = p['summary'] as Map<String, dynamic>? ?? {};
    final totalType = summary['totalProfitType']?.toString();
    final totalColor = totalType == 'gain'
        ? Colors.red
        : (totalType == 'loss' ? Colors.blue : Theme.of(context).hintColor);
    final sign = totalType == 'gain' ? '+' : (totalType == 'loss' ? '-' : '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              '구매합 ${summary['totalBuyDisplay'] ?? '-'} → 현재가치 ${summary['totalCurrentDisplay'] ?? '-'}'
              '  ($sign${summary['totalProfitDisplay'] ?? '-'})',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: totalColor),
            ),
          ),
        ),
        ...items.map((it) {
          final type = it['profitType']?.toString();
          final c = type == 'gain'
              ? Colors.red
              : (type == 'loss' ? Colors.blue : Theme.of(context).hintColor);
          final s = type == 'gain' ? '+' : (type == 'loss' ? '-' : '');
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text('${it['season'] ?? ''} ${it['playerName'] ?? '-'} ${it['grade'] != null ? '${it['grade']}강' : ''}'.trim(),
                style: const TextStyle(fontSize: 13)),
            subtitle: Text('구매 ${it['buyDisplay'] ?? '-'} → 현재 ${it['currentDisplay'] ?? '-'}',
                style: const TextStyle(fontSize: 11)),
            trailing: it['profit'] != null
                ? Text('$s${it['profitDisplay'] ?? ''}', style: TextStyle(fontSize: 12, color: c))
                : const Text('-', style: TextStyle(fontSize: 12)),
          );
        }),
      ],
    );
  }
}
