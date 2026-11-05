import 'package:flutter/material.dart';

import '../../core/db/repo.dart';
import '../../core/models/line.dart';

class LineEditPage extends StatefulWidget {
  const LineEditPage({super.key, this.line});

  final Line? line;

  @override
  State<LineEditPage> createState() => _LineEditPageState();
}

class _LineEditPageState extends State<LineEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _voltage;
  late final TextEditingController _team;
  late final TextEditingController _startTower;
  late final TextEditingController _endTower;
  late final TextEditingController _remark;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final line = widget.line;
    _name = TextEditingController(text: line?.name ?? '');
    _voltage = TextEditingController(text: line?.voltage ?? '');
    _team = TextEditingController(text: line?.team ?? '');
    _startTower = TextEditingController(text: line?.startTower ?? '');
    _endTower = TextEditingController(text: line?.endTower ?? '');
    _remark = TextEditingController(text: line?.remark ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _voltage.dispose();
    _team.dispose();
    _startTower.dispose();
    _endTower.dispose();
    _remark.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    final data = Line(
      id: widget.line?.id,
      name: _name.text.trim(),
      voltage: _voltage.text.trim(),
      team: _team.text.trim(),
      startTower: _startTower.text.trim(),
      endTower: _endTower.text.trim(),
      remark: _remark.text.trim(),
    );
    try {
      if (data.id == null) {
        await Repo.insertLine(data);
      } else {
        await Repo.updateLine(data);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.line == null ? '新建线路' : '编辑线路')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '线路名称',
                hintText: '例如：xx 110kV 甲乙线',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? '请填写线路名称' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _voltage,
              decoration: const InputDecoration(
                labelText: '电压等级',
                hintText: '例如：110kV',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _team,
              decoration: const InputDecoration(
                labelText: '运维班组',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _startTower,
                    decoration: const InputDecoration(
                      labelText: '起始塔号',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _endTower,
                    decoration: const InputDecoration(
                      labelText: '终止塔号',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ],
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
