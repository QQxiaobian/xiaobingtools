import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/db/repo.dart';
import '../../core/models/flaw.dart';
import '../io/data_io.dart';
import '../io/file_actions.dart';
import 'flaw_edit_page.dart';

class FlawListPage extends StatefulWidget {
  const FlawListPage({super.key});

  @override
  State<FlawListPage> createState() => _FlawListPageState();
}

class _FlawListPageState extends State<FlawListPage> {
  List<Flaw> _flaws = [];
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final flaws = await Repo.flaws();
    if (!mounted) return;
    setState(() {
      _flaws = flaws;
      _loading = false;
    });
  }

  Future<void> _openEditor([Flaw? flaw]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => FlawEditPage(flaw: flaw)),
    );
    if (saved == true) {
      await _reload();
    }
  }

  Future<void> _delete(Flaw flaw) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除缺陷'),
        content: const Text('确定删除这条缺陷记录吗？照片文件不会被删除。'),
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
    if (confirmed != true || flaw.id == null) return;
    await Repo.deleteFlaw(flaw.id!);
    await _reload();
  }

  Future<void> _export() async {
    if (_exporting) return;
    if (_flaws.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('还没有缺陷记录')));
      return;
    }
    setState(() => _exporting = true);
    try {
      final file = await DataIo.exportFlaws(_flaws);
      if (!mounted) return;
      await showExportResult(context, file, title: '缺陷记录已导出');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导出失败：$e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Color _levelColor(String level) {
    switch (level) {
      case '危急':
        return const Color(0xFFC62828);
      case '严重':
        return const Color(0xFFEF6C00);
      default:
        return const Color(0xFF2E7D32);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('缺陷记录'),
        actions: [
          IconButton(
            tooltip: '导出 Excel',
            onPressed: _exporting ? null : _export,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('记录缺陷'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _flaws.isEmpty
              ? const Center(
                  child: Text(
                    '暂无缺陷记录\n点击右下角记录第一条',
                    textAlign: TextAlign.center,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88, top: 4),
                    itemCount: _flaws.length,
                    itemBuilder: (context, index) {
                      final flaw = _flaws[index];
                      return Card(
                        margin:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: ListTile(
                          leading: _Thumb(path: flaw.photoPath),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '${flaw.lineName}'
                                  '${flaw.towerNo.isEmpty ? '' : ' / ${flaw.towerNo}'}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _levelColor(flaw.level)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  flaw.level,
                                  style: TextStyle(
                                    color: _levelColor(flaw.level),
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            '${flaw.part.isEmpty ? '未填部位' : flaw.part} · '
                            '${flaw.description}\n${flaw.createdAt}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') {
                                _openEditor(flaw);
                              } else if (value == 'delete') {
                                _delete(flaw);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('编辑')),
                              PopupMenuItem(value: 'delete', child: Text('删除')),
                            ],
                          ),
                          onTap: () => _openEditor(flaw),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty || !File(path).existsSync()) {
      return CircleAvatar(
        radius: 22,
        child: Icon(Icons.image_not_supported_outlined,
            color: Theme.of(context).disabledColor),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        File(path),
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        cacheWidth: 120,
      ),
    );
  }
}
