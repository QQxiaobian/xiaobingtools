import 'package:flutter/material.dart';

import '../../core/db/repo.dart';
import '../../core/models/line.dart';
import '../../core/models/tower.dart';

class TowerEditPage extends StatefulWidget {
  const TowerEditPage({super.key, required this.line, this.tower});

  final Line line;
  final Tower? tower;

  @override
  State<TowerEditPage> createState() => _TowerEditPageState();
}

class _TowerEditPageState extends State<TowerEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _towerNo;
  late final TextEditingController _lng;
  late final TextEditingController _lat;
  late final TextEditingController _elevation;
  late final TextEditingController _towerType;
  late final TextEditingController _seq;
  late final TextEditingController _remark;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final tower = widget.tower;
    _towerNo = TextEditingController(text: tower?.towerNo ?? '');
    _lng = TextEditingController(
      text: tower == null || !tower.hasCoordinate
          ? ''
          : tower.lng.toStringAsFixed(6),
    );
    _lat = TextEditingController(
      text: tower == null || !tower.hasCoordinate
          ? ''
          : tower.lat.toStringAsFixed(6),
    );
    _elevation = TextEditingController(
      text: tower == null || tower.elevation == 0
          ? ''
          : tower.elevation.toString(),
    );
    _towerType = TextEditingController(text: tower?.towerType ?? '');
    _seq = TextEditingController(
      text: tower == null || tower.seq == 0 ? '' : '${tower.seq}',
    );
    _remark = TextEditingController(text: tower?.remark ?? '');
  }

  @override
  void dispose() {
    _towerNo.dispose();
    _lng.dispose();
    _lat.dispose();
    _elevation.dispose();
    _towerType.dispose();
    _seq.dispose();
    _remark.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    if (widget.line.id == null) return;
    final lng = double.tryParse(_lng.text.trim()) ?? 0;
    final lat = double.tryParse(_lat.text.trim()) ?? 0;
    if (lng != 0 && (lng < -180 || lng > 180)) {
      _toast('经度应在 -180 ~ 180 之间');
      return;
    }
    if (lat != 0 && (lat < -90 || lat > 90)) {
      _toast('纬度应在 -90 ~ 90 之间');
      return;
    }
    setState(() => _saving = true);
    final data = Tower(
      id: widget.tower?.id,
      lineId: widget.line.id!,
      towerNo: _towerNo.text.trim(),
      lng: lng,
      lat: lat,
      elevation: double.tryParse(_elevation.text.trim()) ?? 0,
      towerType: _towerType.text.trim(),
      seq: int.tryParse(_seq.text.trim()) ?? 0,
      remark: _remark.text.trim(),
    );
    try {
      if (data.id == null) {
        await Repo.insertTower(data);
      } else {
        await Repo.updateTower(data);
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
        title: Text(widget.tower == null ? '添加杆塔' : '编辑杆塔'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _towerNo,
              decoration: const InputDecoration(
                labelText: '杆塔号',
                hintText: '例如：N12',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? '请填写杆塔号' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _lng,
                    decoration: const InputDecoration(
                      labelText: '经度',
                      hintText: '113.123456',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lat,
                    decoration: const InputDecoration(
                      labelText: '纬度',
                      hintText: '23.123456',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _elevation,
                    decoration: const InputDecoration(
                      labelText: '高程（m）',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _seq,
                    decoration: const InputDecoration(
                      labelText: '序号',
                      hintText: '用于连线顺序',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _towerType,
              decoration: const InputDecoration(
                labelText: '塔型',
                hintText: '例如：ZBC1、耐张塔',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _remark,
              decoration: const InputDecoration(
                labelText: '备注',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
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
