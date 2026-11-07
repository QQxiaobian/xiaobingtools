import 'package:flutter/material.dart';

import '../../core/db/repo.dart';
import '../../core/models/line.dart';
import '../io/data_io.dart';
import '../io/file_actions.dart';
import '../io/kml_io.dart';
import '../map/map_page.dart';
import '../tower/tower_list_page.dart';
import 'line_edit_page.dart';

class LineListPage extends StatefulWidget {
  const LineListPage({super.key});

  @override
  State<LineListPage> createState() => _LineListPageState();
}

class _LineListPageState extends State<LineListPage> {
  List<Line> _lines = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final lines = await Repo.lines();
    if (!mounted) return;
    setState(() {
      _lines = lines;
      _loading = false;
    });
  }

  Future<void> _openEditor([Line? line]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => LineEditPage(line: line)),
    );
    if (saved == true) {
      await _reload();
    }
  }

  Future<void> _delete(Line line) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除线路'),
        content: Text('确定删除“${line.name}”及其全部杆塔数据吗？'),
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
    if (confirmed != true || line.id == null) return;
    await Repo.deleteLine(line.id!);
    await _reload();
  }

  Future<void> _import() async {
    try {
      final result = await DataIo.importLedger();
      if (result == null) return;
      await _reload();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导入完成'),
          content: SingleChildScrollView(
            child: Text(
              result.warnings.isEmpty
                  ? result.summary
                  : '${result.summary}\n\n提示：\n${result.warnings.take(10).join('\n')}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } catch (e) {
      _toast('导入失败：$e');
    }
  }

  Future<void> _importKml() async {
    try {
      final result = await KmlIo.importKml();
      if (result == null) return;
      await _reload();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('KML 批量导入完成'),
          content: SingleChildScrollView(
            child: Text(
              result.warnings.isEmpty
                  ? result.summary
                  : '${result.summary}\n\n提示：\n${result.warnings.take(10).join('\n')}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } catch (e) {
      _toast('KML 导入失败：$e');
    }
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await DataIo.exportLedger();
      if (!mounted) return;
      await showExportResult(context, file, title: '台账已导出');
    } catch (e) {
      _toast('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _template() async {
    try {
      final file = await DataIo.exportTemplate();
      if (!mounted) return;
      await showExportResult(context, file, title: '模板已生成');
    } catch (e) {
      _toast('生成模板失败：$e');
    }
  }

  Future<void> _exportKml(Line line) async {
    try {
      final towers = await Repo.towers(line.id);
      if (towers.where((t) => t.hasCoordinate).isEmpty) {
        _toast('该线路还没有带经纬度的杆塔，无法导出 KML');
        return;
      }
      final file = await DataIo.exportKml(line, towers);
      if (!mounted) return;
      await showExportResult(context, file, title: 'KML 已导出');
    } catch (e) {
      _toast('导出失败：$e');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('线路台账'),
        actions: [
          IconButton(
            tooltip: '导入 Excel',
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.upload_file),
          ),
          IconButton(
            tooltip: '导出 Excel',
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.download_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'template':
                  _template();
                case 'kml':
                  _importKml();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'kml', child: Text('批量导入 KML 文件（可多选）')),
              PopupMenuItem(value: 'template', child: Text('下载导入模板')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('新建线路'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _lines.isEmpty
              ? _EmptyHint(onImport: _import, onImportKml: _importKml)
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88, top: 4),
                    itemCount: _lines.length,
                    itemBuilder: (context, index) {
                      final line = _lines[index];
                      return _LineCard(
                        line: line,
                        onTap: line.id == null
                            ? null
                            : () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TowerListPage(line: line),
                                  ),
                                );
                                await _reload();
                              },
                        onEdit: () => _openEditor(line),
                        onMap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MapPage(line: line),
                          ),
                        ),
                        onKml: () => _exportKml(line),
                        onDelete: () => _delete(line),
                      );
                    },
                  ),
                ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.onTap,
    required this.onEdit,
    required this.onMap,
    required this.onKml,
    required this.onDelete,
  });

  final Line line;
  final VoidCallback? onTap;
  final VoidCallback onEdit;
  final VoidCallback onMap;
  final VoidCallback onKml;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (line.voltage.isNotEmpty) line.voltage,
      if (line.team.isNotEmpty) line.team,
      if (line.startTower.isNotEmpty || line.endTower.isNotEmpty)
        '${line.startTower.isEmpty ? '?' : line.startTower} ~ '
            '${line.endTower.isEmpty ? '?' : line.endTower}',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        title: Text(
          line.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle.isEmpty ? '未填写电压等级 / 班组 / 塔号范围' : subtitle),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'edit':
                onEdit();
              case 'map':
                onMap();
              case 'kml':
                onKml();
              case 'delete':
                onDelete();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('编辑')),
            PopupMenuItem(value: 'map', child: Text('在地图查看')),
            PopupMenuItem(value: 'kml', child: Text('导出 KML')),
            PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.onImport, required this.onImportKml});

  final VoidCallback onImport;
  final VoidCallback onImportKml;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.route_outlined, size: 64),
            const SizedBox(height: 12),
            const Text('还没有线路数据'),
            const SizedBox(height: 4),
            const Text(
              '点击右下角新建线路，或导入已有 Excel 台账 / KML 文件',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.upload_file),
              label: const Text('导入 Excel 台账'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onImportKml,
              icon: const Icon(Icons.map_outlined),
              label: const Text('批量导入 KML'),
            ),
          ],
        ),
      ),
    );
  }
}
