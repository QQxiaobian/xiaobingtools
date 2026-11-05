import 'dart:io';

import 'package:exif/exif.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/config.dart';
import '../../core/db/repo.dart';
import '../../core/models/tower.dart';
import '../../core/utils/geo.dart';
import '../io/data_io.dart';

class PhotoPage extends StatefulWidget {
  const PhotoPage({super.key});

  @override
  State<PhotoPage> createState() => _PhotoPageState();
}

class _PhotoEntry {
  _PhotoEntry({required this.file, required this.takenAt});

  File file;
  final DateTime takenAt;
  double? lat;
  double? lng;
  double? distance;
  Tower? matchedTower;
  String matchedLineName = '';
  String newName = '';
  int seq = 0;
  bool selected = true;
  bool renamed = false;

  bool get hasGps => lat != null && lng != null;

  String get oldBaseName => p.basenameWithoutExtension(file.path);
}

class _PhotoPageState extends State<PhotoPage> {
  static const int _maxFiles = 800;

  final TextEditingController _templateController =
      TextEditingController(text: '{线路}_{塔号}_{日期}_{序号}');

  List<Tower> _towers = [];
  Map<int, String> _lineNames = {};
  List<_PhotoEntry> _entries = [];
  String? _dirPath;
  bool _scanning = false;
  bool _renaming = false;
  String _progressText = '';
  double _threshold = AppConfig.defaultMatchThreshold;

  @override
  void initState() {
    super.initState();
    _loadTowers();
    _templateController.addListener(() {
      if (_entries.isNotEmpty) _refreshNames();
    });
  }

  @override
  void dispose() {
    _templateController.dispose();
    super.dispose();
  }

  Future<void> _loadTowers() async {
    final towers = await Repo.towers();
    final lines = await Repo.lines();
    if (!mounted) return;
    setState(() {
      _towers = towers;
      _lineNames = {
        for (final line in lines)
          if (line.id != null) line.id!: line.name,
      };
    });
  }

  Future<void> _pickDirectory() async {
    try {
      final status = await Permission.manageExternalStorage.request();
      if (!mounted) return;
      if (!status.isGranted) {
        _toast('未获得“所有文件访问”权限。仍可尝试选择目录，若扫描无结果请到系统设置中授权。');
      }
    } catch (_) {
      // 权限申请失败时继续，由文件选择器决定可访问范围。
    }
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: '选择照片所在目录',
    );
    if (path == null) return;
    await _scan(path);
  }

  Future<void> _scan(String path) async {
    setState(() {
      _scanning = true;
      _dirPath = path;
      _entries = [];
      _progressText = '正在扫描目录…';
    });
    final files = <File>[];
    await _collect(Directory(path), files, 0);
    if (!mounted) return;

    final entries = <_PhotoEntry>[];
    try {
      for (var i = 0; i < files.length; i++) {
        final file = files[i];
        final takenAt = await _readTakenAt(file);
        final entry = _PhotoEntry(file: file, takenAt: takenAt);
        final gps = await _readGps(file);
        if (gps != null) {
          entry.lat = gps.$1;
          entry.lng = gps.$2;
        }
        entries.add(entry);
        if (i % 10 == 0 || i == files.length - 1) {
          if (!mounted) return;
          setState(() {
            _progressText = '正在读取照片信息 ${i + 1}/${files.length}';
          });
        }
      }
    } catch (e) {
      _toast('读取照片失败：$e');
    }

    entries.sort((a, b) => a.takenAt.compareTo(b.takenAt));
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _scanning = false;
      _progressText = '';
    });
    _rematch();
  }

  Future<void> _collect(Directory dir, List<File> files, int depth) async {
    if (depth > 4 || files.length >= _maxFiles) return;
    List<FileSystemEntity> children;
    try {
      children = dir.listSync(followLinks: false);
    } catch (_) {
      return;
    }
    for (final entity in children) {
      if (files.length >= _maxFiles) return;
      if (entity is Directory) {
        await _collect(entity, files, depth + 1);
      } else if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (ext == '.jpg' || ext == '.jpeg') {
          files.add(entity);
        }
      }
    }
  }

  Future<DateTime> _readTakenAt(File file) async {
    try {
      final tags = await readExifFromFile(file);
      final raw = tags['EXIF DateTimeOriginal']?.printable ??
          tags['Image DateTime']?.printable;
      if (raw != null && raw.isNotEmpty) {
        final normalized = raw.replaceFirst(
          RegExp(r'^(\d{4}):(\d{2}):(\d{2})'),
          r'$1-$2-$3',
        );
        final parsed = DateTime.tryParse(normalized);
        if (parsed != null) return parsed;
      }
    } catch (_) {
      // 忽略无 EXIF 的照片。
    }
    try {
      return file.lastModifiedSync();
    } catch (_) {
      return DateTime.now();
    }
  }

  Future<(double, double)?> _readGps(File file) async {
    try {
      final tags = await readExifFromFile(file);
      final lat = _dms(tags['GPS GPSLatitude']);
      final lng = _dms(tags['GPS GPSLongitude']);
      if (lat == null || lng == null) return null;
      final latRef = tags['GPS GPSLatitudeRef']?.printable ?? '';
      final lngRef = tags['GPS GPSLongitudeRef']?.printable ?? '';
      final signLat = latRef.contains('S') ? -1 : 1;
      final signLng = lngRef.contains('W') ? -1 : 1;
      return (lat * signLat, lng * signLng);
    } catch (_) {
      return null;
    }
  }

  double? _dms(IfdTag? tag) {
    if (tag == null) return null;
    final values = tag.values.toList();
    if (values.length < 3) return null;
    final d = _ratio(values[0]);
    final m = _ratio(values[1]);
    final s = _ratio(values[2]);
    if (d == null || m == null || s == null) return null;
    return d + m / 60 + s / 3600;
  }

  double? _ratio(Object? value) {
    if (value is Ratio) return value.toDouble();
    if (value is num) return value.toDouble();
    return null;
  }

  void _rematch() {
    for (final entry in _entries) {
      entry.matchedTower = null;
      entry.matchedLineName = '';
      entry.distance = null;
      if (!entry.hasGps) continue;
      Tower? nearest;
      var nearestDistance = double.infinity;
      for (final tower in _towers) {
        if (!tower.hasCoordinate) continue;
        final d = distanceMeters(
          entry.lat!,
          entry.lng!,
          tower.lat,
          tower.lng,
        );
        if (d < nearestDistance) {
          nearestDistance = d;
          nearest = tower;
        }
      }
      if (nearest != null && nearestDistance <= _threshold) {
        entry.matchedTower = nearest;
        entry.matchedLineName = _lineNames[nearest.lineId] ?? '';
        entry.distance = nearestDistance;
      }
    }
    _refreshNames();
  }

  void _refreshNames() {
    final counters = <String, int>{};
    var unmatched = 0;
    for (final entry in _entries) {
      final tower = entry.matchedTower;
      final lineName =
          entry.matchedLineName.isEmpty ? '未匹配' : entry.matchedLineName;
      final towerNo = tower?.towerNo ?? '未知塔位';
      if (tower == null) {
        unmatched++;
        entry.seq = unmatched;
      } else {
        final key = '$lineName|$towerNo';
        counters[key] = (counters[key] ?? 0) + 1;
        entry.seq = counters[key]!;
      }
      final name = _applyTemplate(
        _templateController.text,
        lineName: lineName,
        towerNo: towerNo,
        date: _dateText(entry.takenAt),
        seq: entry.seq,
        original: entry.oldBaseName,
      );
      entry.newName = _sanitize(name);
    }
    setState(() {});
  }

  String _applyTemplate(
    String template, {
    required String lineName,
    required String towerNo,
    required String date,
    required int seq,
    required String original,
  }) {
    var result = template
        .replaceAll('{线路}', lineName)
        .replaceAll('{塔号}', towerNo)
        .replaceAll('{日期}', date)
        .replaceAll('{序号}', seq.toString())
        .replaceAll('{原名}', original);
    if (result.trim().isEmpty) result = original;
    return result;
  }

  String _sanitize(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), '_')
        .trim();
    return cleaned.length > 100 ? cleaned.substring(0, 100) : cleaned;
  }

  String _dateText(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}${two(dt.month)}${two(dt.day)}';
  }

  Future<void> _changeThreshold() async {
    var value = _threshold;
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('照片匹配杆塔的距离阈值'),
        content: StatefulBuilder(
          builder: (ctx, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${value.toStringAsFixed(0)} 米'),
              Slider(
                value: value,
                min: 10,
                max: 500,
                divisions: 49,
                label: '${value.toStringAsFixed(0)} m',
                onChanged: (v) => setLocal(() => value = v),
              ),
              const Text(
                '照片 GPS 与杆塔距离小于该值时，自动匹配到最近杆塔。',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, value),
            child: const Text('应用'),
          ),
        ],
      ),
    );
    if (result == null) return;
    setState(() => _threshold = result);
    _rematch();
  }

  Future<void> _renameSelected() async {
    if (_renaming) return;
    final targets = _entries
        .where((e) =>
            e.selected &&
            !e.renamed &&
            e.newName.trim() != e.oldBaseName)
        .toList();
    if (targets.isEmpty) {
      _toast('没有需要重命名的照片');
      return;
    }
    setState(() => _renaming = true);
    final log = StringBuffer();
    var success = 0;
    var failed = 0;
    for (final entry in targets) {
      final ext = p.extension(entry.file.path);
      var candidate = entry.newName.trim();
      if (candidate.length > 100) candidate = candidate.substring(0, 100);
      var targetPath = p.join(p.dirname(entry.file.path), '$candidate$ext');
      var index = 1;
      while (File(targetPath).existsSync() &&
          !p.equals(targetPath, entry.file.path)) {
        targetPath =
            p.join(p.dirname(entry.file.path), '$candidate($index)$ext');
        index++;
      }
      final oldName = p.basename(entry.file.path);
      try {
        final renamed = await entry.file.rename(targetPath);
        entry.file = renamed;
        entry.renamed = true;
        entry.selected = false;
        success++;
        log.writeln('成功\t$oldName\t${p.basename(renamed.path)}');
      } catch (e) {
        failed++;
        log.writeln('失败\t$oldName\t$e');
      }
    }

    File? logFile;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final stamp = '${now.year}${two(now.month)}${two(now.day)}'
          '_${two(now.hour)}${two(now.minute)}${two(now.second)}';
      logFile = File(p.join(docs.path, '照片重命名日志_$stamp.txt'));
      await logFile.writeAsString(log.toString());
    } catch (_) {
      // 日志写入失败不影响主流程。
    }

    if (!mounted) return;
    setState(() => _renaming = false);
    final savedLog = logFile;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名完成'),
        content: Text(
          '成功 $success 张，失败 $failed 张。\n'
          '${savedLog == null ? '' : '日志：${savedLog.path}'}',
        ),
        actions: [
          if (savedLog != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                DataIo.shareFile(savedLog, text: '照片重命名日志');
              },
              child: const Text('分享日志'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  void _toggleAll(bool select) {
    setState(() {
      for (final entry in _entries) {
        if (!entry.renamed) entry.selected = select;
      }
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _entries.where((e) => e.selected && !e.renamed).length;
    final matchedCount = _entries.where((e) => e.matchedTower != null).length;
    final hasGps = _entries.where((e) => e.hasGps).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('照片归档'),
        actions: [
          IconButton(
            tooltip: '匹配阈值',
            onPressed: _changeThreshold,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: '选择目录',
            onPressed: _scanning ? null : _pickDirectory,
            icon: const Icon(Icons.folder_open),
          ),
        ],
      ),
      body: _scanning
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_progressText),
                ],
              ),
            )
          : _dirPath == null
              ? _EmptyState(onPick: _pickDirectory)
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '目录：${p.basename(_dirPath!)}'
                            '（共 ${_entries.length} 张，含 GPS $hasGps 张，'
                            '匹配杆塔 $matchedCount 张）',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _templateController,
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: '命名模板',
                              helperText:
                                  '可用占位：{线路} {塔号} {日期} {序号} {原名}',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _entries.isEmpty
                          ? const Center(child: Text('该目录下没有 jpg 照片'))
                          : ListView.builder(
                              itemCount: _entries.length,
                              itemBuilder: (context, index) =>
                                  _buildEntry(_entries[index]),
                            ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Row(
                          children: [
                            TextButton(
                              onPressed: () => _toggleAll(false),
                              child: const Text('全不选'),
                            ),
                            TextButton(
                              onPressed: () => _toggleAll(true),
                              child: const Text('全选'),
                            ),
                            const Spacer(),
                            FilledButton.icon(
                              onPressed:
                                  _renaming ? null : _renameSelected,
                              icon: _renaming
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.drive_file_rename_outline),
                              label: Text('重命名 $selectedCount 张'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildEntry(_PhotoEntry entry) {
    final theme = Theme.of(context);
    final changed = entry.newName.trim() != entry.oldBaseName;
    final subtitle = StringBuffer(entry.file.path);
    if (entry.matchedTower != null) {
      subtitle
        ..write('\n匹配：${entry.matchedLineName} / ${entry.matchedTower!.towerNo}')
        ..write('（${formatDistance(entry.distance ?? 0)}）');
    } else if (entry.hasGps) {
      subtitle.write('\n未匹配到 ${_threshold.toStringAsFixed(0)}m 内的杆塔');
    } else {
      subtitle.write('\n无 GPS 信息');
    }

    return ListTile(
      leading: Checkbox(
        value: entry.selected,
        onChanged: entry.renamed
            ? null
            : (value) => setState(() => entry.selected = value ?? false),
      ),
      title: Text(
        changed ? '${entry.oldBaseName} → ${entry.newName}' : entry.oldBaseName,
        style: TextStyle(
          color: entry.renamed ? theme.colorScheme.primary : null,
          fontSize: 13,
        ),
      ),
      subtitle: Text(
        subtitle.toString(),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
      trailing: entry.renamed
          ? const Icon(Icons.check_circle, color: Colors.green)
          : Text(
              _dateText(entry.takenAt),
              style: const TextStyle(fontSize: 11),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_library_outlined, size: 64),
            const SizedBox(height: 12),
            const Text('选择巡检照片所在目录'),
            const SizedBox(height: 4),
            const Text(
              '按照片 GPS 自动匹配最近杆塔，再按模板批量重命名。\n'
              '建议先备份原照片。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.folder_open),
              label: const Text('选择目录'),
            ),
          ],
        ),
      ),
    );
  }
}
