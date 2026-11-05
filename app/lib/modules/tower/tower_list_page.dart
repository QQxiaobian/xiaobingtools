import 'package:flutter/material.dart';

import '../../core/db/repo.dart';
import '../../core/models/line.dart';
import '../../core/models/tower.dart';
import '../../core/utils/geo.dart';
import '../map/map_page.dart';
import 'tower_edit_page.dart';

class TowerListPage extends StatefulWidget {
  const TowerListPage({super.key, required this.line});

  final Line line;

  @override
  State<TowerListPage> createState() => _TowerListPageState();
}

class _TowerListPageState extends State<TowerListPage> {
  List<Tower> _towers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (widget.line.id == null) return;
    final towers = await Repo.towers(widget.line.id);
    if (!mounted) return;
    setState(() {
      _towers = towers;
      _loading = false;
    });
  }

  double get _totalLength {
    var total = 0.0;
    for (var i = 1; i < _towers.length; i++) {
      final a = _towers[i - 1];
      final b = _towers[i];
      if (!a.hasCoordinate || !b.hasCoordinate) continue;
      total += distanceMeters(a.lat, a.lng, b.lat, b.lng);
    }
    return total;
  }

  Future<void> _openEditor([Tower? tower]) async {
    if (widget.line.id == null) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TowerEditPage(line: widget.line, tower: tower),
      ),
    );
    if (saved == true) {
      await _reload();
    }
  }

  Future<void> _delete(Tower tower) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除杆塔'),
        content: Text('确定删除杆塔 ${tower.towerNo} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || tower.id == null) return;
    await Repo.deleteTower(tower.id!);
    await _reload();
  }

  void _openMap() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MapPage(line: widget.line)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.line.name),
        actions: [
          IconButton(
            tooltip: '地图查看',
            onPressed: _openMap,
            icon: const Icon(Icons.map_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('添加杆塔'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Text(
                    '共 ${_towers.length} 基杆塔 · 线路长度约 '
                    '${formatDistance(_totalLength)}'
                    '${widget.line.voltage.isEmpty ? '' : ' · ${widget.line.voltage}'}',
                  ),
                ),
                Expanded(
                  child: _towers.isEmpty
                      ? const Center(
                          child: Text('暂无杆塔，点击右下角添加'),
                        )
                      : RefreshIndicator(
                          onRefresh: _reload,
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 88),
                            itemCount: _towers.length,
                            itemBuilder: (context, index) {
                              final tower = _towers[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 18,
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                title: Text(
                                  tower.towerNo,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  [
                                    if (tower.hasCoordinate)
                                      '${formatLngLat(tower.lng)}, '
                                          '${formatLngLat(tower.lat)}'
                                    else
                                      '未填写经纬度',
                                    if (tower.towerType.isNotEmpty) tower.towerType,
                                    if (tower.elevation > 0)
                                      '高程 ${tower.elevation.toStringAsFixed(1)}m',
                                  ].join(' · '),
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _openEditor(tower);
                                    } else if (value == 'delete') {
                                      _delete(tower);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('编辑'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('删除'),
                                    ),
                                  ],
                                ),
                                onTap: () => _openEditor(tower),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
