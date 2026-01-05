import 'package:flutter/material.dart';
import '../services/api_service.dart';

class NotificationsScreen extends StatefulWidget {
  final String username;
  final ApiService apiService;

  const NotificationsScreen({
    Key? key,
    required this.username,
    required this.apiService,
  }) : super(key: key);

  @override
  _NotificationsScreenState createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  int _currentLimit = 30;
  final int _loadMoreCount = 30;
  final int _maxLimit = 100;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications({bool loadMore = false}) async {
    if (loadMore) {
      setState(() {
        _currentLimit = (_currentLimit + _loadMoreCount).clamp(0, _maxLimit);
      });
    } else {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final result = await _apiService.getNotifications(limit: _currentLimit);
      
      if (result['success'] == true && result['notifications'] != null) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(result['notifications']);
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? '알림을 불러올 수 없습니다')),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e')),
        );
      }
    }
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'relegation_status_change':
        return Icons.shield;
      case 'macro_start':
        return Icons.play_arrow;
      case 'macro_stop':
        return Icons.stop;
      case 'program_exit':
        return Icons.exit_to_app;
      case 'notice_new':
      case 'notice_changed':
        return Icons.announcement;
      case 'parking_stop':
        return Icons.local_parking;
      case 'no_response':
        return Icons.warning;
      case 'schedule_reached':
        return Icons.schedule;
      case 'status_offline':
        return Icons.offline_bolt;
      default:
        return Icons.notifications;
    }
  }

  Color _getNotificationColor(String type) {
    switch (type) {
      case 'relegation_status_change':
        return Colors.blue;
      case 'macro_start':
        return Colors.green;
      case 'macro_stop':
      case 'program_exit':
        return Colors.orange;
      case 'notice_new':
      case 'notice_changed':
        return Colors.purple;
      case 'no_response':
      case 'status_offline':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatDateTime(String dateTime) {
    try {
      final dt = DateTime.parse(dateTime);
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) {
        return '방금 전';
      } else if (diff.inHours < 1) {
        return '${diff.inMinutes}분 전';
      } else if (diff.inDays < 1) {
        return '${diff.inHours}시간 전';
      } else if (diff.inDays < 7) {
        return '${diff.inDays}일 전';
      } else {
        return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return dateTime;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림 목록'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadNotifications(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_off, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        '알림이 없습니다',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadNotifications(),
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _notifications.length,
                          itemBuilder: (context, index) {
                            final notification = _notifications[index];
                            final icon = _getNotificationIcon(notification['type'] ?? '');
                            final color = _getNotificationColor(notification['type'] ?? '');

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: color.withOpacity(0.1),
                                  child: Icon(icon, color: color),
                                ),
                                title: Text(
                                  notification['title'] ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      notification['body'] ?? '',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatDateTime(notification['created_at'] ?? ''),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                                isThreeLine: true,
                              ),
                            );
                          },
                        ),
                      ),
                      if (_notifications.length >= _currentLimit && _currentLimit < _maxLimit)
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: ElevatedButton.icon(
                            onPressed: () => _loadNotifications(loadMore: true),
                            icon: const Icon(Icons.expand_more),
                            label: Text('$_loadMoreCount개 더 보기'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 48),
                            ),
                          ),
                        ),
                      if (_currentLimit >= _maxLimit)
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            '최대 $_maxLimit개까지만 표시됩니다',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
