import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/db/repo.dart';
import '../../core/models/quiz.dart';

/// 模拟考试设置：选题库、各题型题量与分值、考试时长。
class ExamSetupPage extends StatefulWidget {
  const ExamSetupPage({super.key});

  @override
  State<ExamSetupPage> createState() => _ExamSetupPageState();
}

class _ExamSetupPageState extends State<ExamSetupPage> {
  List<QuestionBank> _banks = [];
  Map<int, List<Question>> _questionsByBank = {};
  int? _bankId;
  bool _loading = true;

  final Map<String, TextEditingController> _countControllers = {
    Question.typeSingle: TextEditingController(text: '10'),
    Question.typeMulti: TextEditingController(text: '5'),
    Question.typeJudge: TextEditingController(text: '5'),
  };
  final Map<String, TextEditingController> _scoreControllers = {
    Question.typeSingle: TextEditingController(text: '1'),
    Question.typeMulti: TextEditingController(text: '2'),
    Question.typeJudge: TextEditingController(text: '1'),
  };
  final _minutesController = TextEditingController(text: '30');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _countControllers.values) {
      controller.dispose();
    }
    for (final controller in _scoreControllers.values) {
      controller.dispose();
    }
    _minutesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final banks = await Repo.quizBanks();
    final map = <int, List<Question>>{};
    for (final bank in banks) {
      if (bank.id != null) {
        map[bank.id!] = await Repo.questions(bank.id!);
      }
    }
    map.removeWhere((_, questions) => questions.isEmpty);
    if (!mounted) return;
    setState(() {
      _banks = banks.where((b) => map.containsKey(b.id)).toList();
      _questionsByBank = map;
      _bankId = _banks.isEmpty ? null : _banks.first.id;
      _loading = false;
    });
  }

  int _available(String type) {
    final bankId = _bankId;
    if (bankId == null) return 0;
    return _questionsByBank[bankId]!
        .where((q) => q.type == type)
        .length;
  }

  int _parseCount(String type) =>
      int.tryParse(_countControllers[type]!.text.trim()) ?? 0;

  double _parseScore(String type) =>
      double.tryParse(_scoreControllers[type]!.text.trim()) ?? 1;

  double get _totalScore => Question.types.fold(
        0,
        (sum, type) => sum + _parseCount(type) * _parseScore(type),
      );

  String? _validate() {
    if (_bankId == null) return '请先选择题库';
    for (final type in Question.types) {
      final count = _parseCount(type);
      if (count < 0) return '$type题量不能为负数';
      if (count > _available(type)) {
        return '$type最多 ${(_available(type))} 道，当前设置 $count 道';
      }
    }
    if (Question.types.every((t) => _parseCount(t) == 0)) {
      return '请至少设置一种题型的题量';
    }
    return null;
  }

  void _start() {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final random = Random();
    final questions = <Question>[];
    final scores = <String, double>{};
    for (final type in Question.types) {
      final count = _parseCount(type);
      if (count == 0) continue;
      final pool = _questionsByBank[_bankId]!
          .where((q) => q.type == type)
          .toList()
        ..shuffle(random);
      questions.addAll(pool.take(count));
      scores[type] = _parseScore(type);
    }
    final minutes = int.tryParse(_minutesController.text.trim()) ?? 0;
    final bank = _banks.firstWhere((b) => b.id == _bankId);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExamPage(
          title: bank.name,
          questions: questions,
          scorePerType: scores,
          minutes: minutes,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('模拟考试')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _banks.isEmpty
              ? const Center(child: Text('暂无可用题库，请先导入题目'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: _bankId,
                      decoration: const InputDecoration(
                        labelText: '选择题库',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final bank in _banks)
                          DropdownMenuItem(
                            value: bank.id,
                            child: Text(bank.name),
                          ),
                      ],
                      onChanged: (value) => setState(() => _bankId = value),
                    ),
                    const SizedBox(height: 16),
                    Text('题型与分值', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    for (final type in Question.types)
                      if (_available(type) > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 96,
                                child: Text('$type（共${_available(type)}）'),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _countControllers[type],
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: '题量',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _scoreControllers[type],
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  decoration: const InputDecoration(
                                    labelText: '每题分值',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ],
                          ),
                        ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _minutesController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '考试时长（分钟，0 为不限时）',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '预计满分 ${_totalScore.toStringAsFixed(1)} 分'
                      ' · 及格 ${(60 * _totalScore / 100).toStringAsFixed(1)} 分',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _start,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('开始考试'),
                    ),
                  ],
                ),
    );
  }
}

/// 考试页面：倒计时、答题、交卷判分、成绩报告。
class ExamPage extends StatefulWidget {
  const ExamPage({
    super.key,
    required this.title,
    required this.questions,
    required this.scorePerType,
    required this.minutes,
  });

  final String title;
  final List<Question> questions;
  final Map<String, double> scorePerType;
  final int minutes;

  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> {
  final Map<int, Set<String>> _answers = {};
  int _index = 0;
  Timer? _timer;
  int _secondsLeft = 0;
  bool _submitted = false;
  double _total = 0;
  Map<String, (double, double)> _typeScores = {};

  @override
  void initState() {
    super.initState();
    if (widget.minutes > 0) {
      _secondsLeft = widget.minutes * 60;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_secondsLeft <= 1) {
          _submit(auto: true);
        } else {
          setState(() => _secondsLeft--);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _timeText {
    final m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Question get _question => widget.questions[_index];

  void _tapOption(String letter) {
    if (_submitted) return;
    final q = _question;
    final id = q.id;
    if (id == null) return;
    setState(() {
      final picked = _answers.putIfAbsent(id, () => {});
      if (q.isMulti) {
        if (picked.contains(letter)) {
          picked.remove(letter);
        } else {
          picked.add(letter);
        }
      } else {
        picked
          ..clear()
          ..add(letter);
      }
    });
  }

  Future<void> _submit({bool auto = false}) async {
    if (_submitted) return;
    final unanswered = widget.questions.length - _answers.length;
    if (!auto) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('交卷'),
          content: Text(
            unanswered > 0 ? '还有 $unanswered 题未作答，确定交卷吗？' : '确定交卷吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('继续作答'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('交卷'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    _timer?.cancel();
    var total = 0.0;
    final typeScores = <String, (double, double)>{};
    for (final q in widget.questions) {
      final score = widget.scorePerType[q.type] ?? 1;
      final picked = _answers[q.id] ?? {};
      final correct = q.isCorrect(picked);
      final current = typeScores[q.type] ?? (0.0, 0.0);
      typeScores[q.type] = (current.$1 + (correct ? score : 0), current.$2 + score);
      total += correct ? score : 0;
      if (q.id != null && picked.isNotEmpty) {
        // 答题结果回流统计，错题进入错题本。
        await Repo.recordAnswer(q, correct);
      }
    }
    setState(() {
      _submitted = true;
      _total = total;
      _typeScores = typeScores;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _submitted
            ? const Text('成绩报告')
            : Text(
                widget.minutes > 0 ? '剩余 $_timeText' : widget.title,
                overflow: TextOverflow.ellipsis,
              ),
        actions: [
          if (!_submitted)
            TextButton(
              onPressed: _submit,
              child: const Text('交卷'),
            ),
        ],
      ),
      body: _submitted ? _buildResult() : _buildExam(),
    );
  }

  Widget _buildExam() {
    final theme = Theme.of(context);
    final q = _question;
    final letters = q.optionLetters;
    final picked = _answers[q.id] ?? {};
    return Column(
      children: [
        LinearProgressIndicator(
          value: (_index + 1) / widget.questions.length,
          minHeight: 3,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${_index + 1}/${widget.questions.length}　[${q.type}] ${q.stem}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < q.options.length; i++)
                _ExamOptionTile(
                  letter: letters[i],
                  text: q.options[i],
                  multi: q.isMulti,
                  selected: picked.contains(letters[i]),
                  onTap: () => _tapOption(letters[i]),
                ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                OutlinedButton(
                  onPressed:
                      _index > 0 ? () => setState(() => _index--) : null,
                  child: const Text('上一题'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _index < widget.questions.length - 1
                        ? () => setState(() => _index++)
                        : _submit,
                    child: Text(
                      _index < widget.questions.length - 1 ? '下一题' : '交卷',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResult() {
    final theme = Theme.of(context);
    final fullScore = widget.scorePerType.entries.fold<double>(
      0,
      (sum, e) =>
          sum +
          e.value *
              widget.questions.where((q) => q.type == e.key).length,
    );
    final pass = fullScore > 0 && _total >= fullScore * 0.6;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(
                  pass ? Icons.emoji_events_outlined : Icons.refresh,
                  size: 48,
                  color: pass
                      ? const Color(0xFF2E7D32)
                      : theme.colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  '${_total.toStringAsFixed(1)} / ${fullScore.toStringAsFixed(1)} 分',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  pass ? '成绩合格' : '成绩不合格（及格线 60%）',
                  style: TextStyle(
                    color: pass
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFC62828),
                  ),
                ),
                const SizedBox(height: 12),
                for (final entry in _typeScores.entries)
                  Text(
                    '${entry.key}：${entry.value.$1.toStringAsFixed(1)}'
                    ' / ${entry.value.$2.toStringAsFixed(1)} 分',
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('逐题解析', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        for (var i = 0; i < widget.questions.length; i++)
          _ReviewCard(
            index: i + 1,
            question: widget.questions[i],
            picked: _answers[widget.questions[i].id] ?? {},
            score: widget.scorePerType[widget.questions[i].type] ?? 1,
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('返回'),
        ),
      ],
    );
  }
}

class _ExamOptionTile extends StatelessWidget {
  const _ExamOptionTile({
    required this.letter,
    required this.text,
    required this.multi,
    required this.selected,
    required this.onTap,
  });

  final String letter;
  final String text;
  final bool multi;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
            : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected ? theme.colorScheme.primary : theme.dividerColor,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: multi ? BoxShape.rectangle : BoxShape.circle,
                    borderRadius: multi ? BorderRadius.circular(6) : null,
                    border: Border.all(
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      width: 1.4,
                    ),
                  ),
                  child: Text(
                    letter,
                    style: TextStyle(
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.index,
    required this.question,
    required this.picked,
    required this.score,
  });

  final int index;
  final Question question;
  final Set<String> picked;
  final double score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = question;
    final correct = q.isCorrect(picked);
    final letters = q.optionLetters;
    final pickedText = picked.isEmpty
        ? '未作答'
        : q.isJudge
            ? (picked.first == 'A' ? '正确' : '错误')
            : (picked.toList()..sort()).join();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  correct ? Icons.check_circle : Icons.cancel,
                  size: 20,
                  color: correct
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFFC62828),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$index. [${q.type}·${score.toStringAsFixed(1)}分] ${q.stem}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < q.options.length; i++)
              Text(
                '${letters[i]}. ${q.options[i]}',
                style: TextStyle(
                  color: q.answerLetters.contains(letters[i])
                      ? const Color(0xFF2E7D32)
                      : null,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              '你的答案：$pickedText　正确答案：'
              '${q.isJudge ? (q.answer == 'A' ? '正确' : '错误') : q.answer}',
              style: TextStyle(
                color:
                    correct ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (q.analysis.isNotEmpty) Text('解析：${q.analysis}'),
          ],
        ),
      ),
    );
  }
}
