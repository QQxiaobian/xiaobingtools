import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/db/repo.dart';
import '../../core/models/flaw.dart';
import '../../core/models/line.dart';
import '../../core/models/tower.dart';

class FlawEditPage extends StatefulWidget {
  const FlawEditPage({super.key, this.flaw});

  final Flaw? flaw;

  @override
  State<FlawEditPage> createState() => _FlawEditPageState();
}

class _FlawEditPageState extends State<FlawEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _picker = ImagePicker();

  List<Line> _lines = [];
  List<Tower> _towers = [];
  int? _lineId;
  int? _towerId;
  String _part = Flaw.parts.first;
  String _level = Flaw.levels.first;
  String _photoPath = '';
  bool _loading = true;
  bool _saving = false;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    final flaw = widget.flaw;
    _description.text = flaw?.description ?? '';
    _part = flaw?.part.isNotEmpty == true ? flaw!.part : Flaw.parts.first;
    _level = flaw?.level.isNotEmpty == true ? flaw!.level : Flaw.levels.first;
    _photoPath = flaw?.photoPath ?? '';
    _lineId = flaw?.lineId;
    _towerId = flaw?.towerId;
    _load();
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final lines = await Repo.lines();
    if (!mounted) return;
    setState(() {
      _lines = lines;
      final ids = lines.map((line) => line.id).toSet();
      if (!ids.contains(_lineId)) {
        _lineId = lines.isEmpty ? null : lines.first.id;
        _towerId = null;
      }
      _loading = false;
    });
    await _loadTowers();
  }

  Future<void> _loadTowers() async {
    if (_lineId == null) return;
    final towers = await Repo.towers(_lineId);
    if (!mounted) return;
    setState(() {
      _towers = towers;
      if (_towerId != null && !towers.any((t) => t.id == _towerId)) {
        _towerId = null;
      }
    });
  }

  Future<void> _pickPhoto(ImageSource source) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (picked == null) return;
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'flaws'));
      if (!dir.existsSync()) dir.create(recursive: true);
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final ext = p.extension(picked.path);
      final target = p.join(dir.path, 'flaw_$stamp$ext');
      await File(picked.path).copy(target);
      if (!mounted) return;
      setState(() => _photoPath = target);
    } catch (e) {
      _toast('拍照/选图失败：$e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    if (_lineId == null) {
      _toast('请先选择线路');
      return;
    }
    setState(() => _saving = true);
    final line = _lines.firstWhere((l) => l.id == _lineId);
    final tower = _towers.where((t) => t.id == _towerId).firstOrNull;
    final data = Flaw(
      id: widget.flaw?.id,
      lineId: _lineId!,
      lineName: line.name,
      towerId: tower?.id,
      towerNo: tower?.towerNo ?? '',
      part: _part,
      level: _level,
      description: _description.text.trim(),
      photoPath: _photoPath,
      createdAt: widget.flaw?.createdAt ??
          DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
    );
    try {
      if (data.id == null) {
        await Repo.insertFlaw(data);
      } else {
        await Repo.updateFlaw(data);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('保存失败：$e');
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
        title: Text(widget.flaw == null ? '记录缺陷' : '编辑缺陷'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _lines.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '还没有线路台账，请先到“线路台账”新建线路或导入 Excel。',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: _lineId,
                        decoration: const InputDecoration(
                          labelText: '线路',
                          border: OutlineInputBorder(),
                        ),
                        items: _lines
                            .map(
                              (line) => DropdownMenuItem(
                                value: line.id,
                                child: Text(
                                  line.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _lineId = value;
                            _towerId = null;
                          });
                          _loadTowers();
                        },
                        validator: (value) => value == null ? '请选择线路' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        key: ValueKey('tower_${_lineId ?? 0}'),
                        initialValue: _towerId ?? 0,
                        decoration: const InputDecoration(
                          labelText: '杆塔（可不选）',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 0,
                            child: Text('不指定杆塔'),
                          ),
                          ..._towers.map(
                            (tower) => DropdownMenuItem(
                              value: tower.id ?? 0,
                              child: Text(tower.towerNo),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(
                          () => _towerId =
                              (value == null || value == 0) ? null : value,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _part,
                              decoration: const InputDecoration(
                                labelText: '缺陷部位',
                                border: OutlineInputBorder(),
                              ),
                              items: Flaw.parts
                                  .map(
                                    (part) => DropdownMenuItem(
                                      value: part,
                                      child: Text(part),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setState(() => _part = value ?? _part),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _level,
                              decoration: const InputDecoration(
                                labelText: '缺陷等级',
                                border: OutlineInputBorder(),
                              ),
                              items: Flaw.levels
                                  .map(
                                    (level) => DropdownMenuItem(
                                      value: level,
                                      child: Text(level),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) =>
                                  setState(() => _level = value ?? _level),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _description,
                        decoration: const InputDecoration(
                          labelText: '缺陷描述',
                          hintText: '例如：N12 小号侧导线有异物悬挂',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 4,
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? '请填写缺陷描述'
                                : null,
                      ),
                      const SizedBox(height: 16),
                      Text('现场照片', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      if (_photoPath.isNotEmpty && File(_photoPath).existsSync())
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(_photoPath),
                            height: 180,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            cacheWidth: 600,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _picking
                                ? null
                                : () => _pickPhoto(ImageSource.camera),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('拍照'),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: _picking
                                ? null
                                : () => _pickPhoto(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('从相册选择'),
                          ),
                          if (_photoPath.isNotEmpty)
                            TextButton(
                              onPressed: () =>
                                  setState(() => _photoPath = ''),
                              child: const Text('移除'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save),
                        label: Text(_saving ? '保存中…' : '保存'),
                      ),
                    ],
                  ),
                ),
    );
  }
}
