import 'package:flutter/material.dart';

import '../../core/db/repo.dart';
import '../../core/models/quiz.dart';

/// 添加 / 编辑单道题目。
class QuestionEditPage extends StatefulWidget {
  const QuestionEditPage({super.key, required this.bank, this.question});

  final QuestionBank bank;
  final Question? question;

  @override
  State<QuestionEditPage> createState() => _QuestionEditPageState();
}

class _QuestionEditPageState extends State<QuestionEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _stem = TextEditingController();
  final _chapter = TextEditingController();
  final _analysis = TextEditingController();
  final List<TextEditingController> _options = [];

  String _type = Question.typeSingle;
  String _judgeAnswer = 'A';
  final Set<String> _choiceAnswer = {'A'};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final q = widget.question;
    _type = q?.type ?? Question.typeSingle;
    _stem.text = q?.stem ?? '';
    _chapter.text = q?.chapter ?? '';
    _analysis.text = q?.analysis ?? '';
    if (q != null && !q.isJudge) {
      for (final option in q.options) {
        _options.add(TextEditingController(text: option));
      }
      _choiceAnswer
        ..clear()
        ..addAll(q.answerLetters);
    }
    if (q != null && q.isJudge) {
      _judgeAnswer = q.answer.isEmpty ? 'A' : q.answer;
    }
    while (_options.length < 4) {
      _options.add(TextEditingController());
    }
  }

  @override
  void dispose() {
    _stem.dispose();
    _chapter.dispose();
    _analysis.dispose();
    for (final controller in _options) {
      controller.dispose();
    }
    super.dispose();
  }

  void _switchType(String type) {
    setState(() {
      _type = type;
      if (type == Question.typeSingle && _choiceAnswer.length > 1) {
        final first = _choiceAnswer.first;
        _choiceAnswer
          ..clear()
          ..add(first);
      }
    });
  }

  String get _answer {
    if (_type == Question.typeJudge) return _judgeAnswer;
    final sorted = _choiceAnswer.toList()..sort();
    return sorted.join();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final options = _type == Question.typeJudge
        ? const <String>[]
        : _options
            .map((c) => c.text.trim())
            .where((text) => text.isNotEmpty)
            .toList();
    if (_type != Question.typeJudge && options.length < 2) {
      _toast('选择题至少需要 2 个选项');
      return;
    }
    if (_type != Question.typeJudge) {
      final maxLetter = String.fromCharCode(65 + options.length - 1);
      final invalid = _choiceAnswer.any(
        (letter) => letter.compareTo(maxLetter) > 0,
      );
      if (_answer.isEmpty || invalid) {
        _toast('请选择有效答案（选项范围内）');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final bankId = widget.bank.id;
      if (bankId == null) return;
      final existing = widget.question;
      final question = Question(
        id: existing?.id,
        bankId: bankId,
        type: _type,
        chapter: _chapter.text.trim(),
        stem: _stem.text.trim(),
        options:
            _type == Question.typeJudge ? const ['正确', '错误'] : options,
        answer: _answer,
        analysis: _analysis.text.trim(),
        seq: existing?.seq ?? 0,
      );
      if (existing?.id == null) {
        await Repo.insertQuestion(question);
      } else {
        await Repo.updateQuestion(question);
      }
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.question == null ? '添加题目' : '编辑题目'),
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
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: Question.typeSingle, label: Text('单选')),
                ButtonSegment(value: Question.typeMulti, label: Text('多选')),
                ButtonSegment(value: Question.typeJudge, label: Text('判断')),
              ],
              selected: {_type},
              onSelectionChanged: (value) => _switchType(value.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _stem,
              maxLines: null,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: '题干',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? '请输入题干' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _chapter,
              decoration: const InputDecoration(
                labelText: '章节（可选）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (_type == Question.typeJudge) ...[
              Text('答案', style: theme.textTheme.titleSmall),
              RadioGroup<String>(
                groupValue: _judgeAnswer,
                onChanged: (value) =>
                    setState(() => _judgeAnswer = value ?? 'A'),
                child: const Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        value: 'A',
                        title: Text('正确'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        value: 'B',
                        title: Text('错误'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Text('选项', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (var i = 0; i < _options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextFormField(
                    controller: _options[i],
                    decoration: InputDecoration(
                      labelText: '选项 ${String.fromCharCode(65 + i)}',
                      border: const OutlineInputBorder(),
                      suffixIcon: _options.length > 2
                          ? IconButton(
                              tooltip: '删除选项',
                              onPressed: () {
                                setState(() {
                                  _options.removeAt(i).dispose();
                                  // 答案字母重映射：被删选项之后整体前移。
                                  final old = _choiceAnswer.toList()..sort();
                                  _choiceAnswer.clear();
                                  for (final letter in old) {
                                    final code = letter.codeUnitAt(0);
                                    if (code == 65 + i) continue;
                                    _choiceAnswer.add(
                                      code > 65 + i
                                          ? String.fromCharCode(code - 1)
                                          : letter,
                                    );
                                  }
                                });
                              },
                              icon: const Icon(Icons.remove_circle_outline),
                            )
                          : null,
                    ),
                  ),
                ),
              if (_options.length < 10)
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _options.add(TextEditingController())),
                  icon: const Icon(Icons.add),
                  label: const Text('添加选项'),
                ),
              const SizedBox(height: 8),
              Text(
                _type == Question.typeMulti ? '答案（可多选）' : '答案',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  for (var i = 0; i < _options.length; i++)
                    FilterChip(
                      label: Text(String.fromCharCode(65 + i)),
                      selected: _choiceAnswer
                          .contains(String.fromCharCode(65 + i)),
                      onSelected: (selected) {
                        final letter = String.fromCharCode(65 + i);
                        setState(() {
                          if (_type == Question.typeSingle) {
                            _choiceAnswer
                              ..clear()
                              ..add(letter);
                          } else if (selected) {
                            _choiceAnswer.add(letter);
                          } else {
                            _choiceAnswer.remove(letter);
                          }
                        });
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _analysis,
              maxLines: null,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: '解析（可选）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
