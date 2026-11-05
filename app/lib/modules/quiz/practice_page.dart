import 'package:flutter/material.dart';

import '../../core/db/repo.dart';
import '../../core/models/quiz.dart';

enum PracticeMode { sequential, random, memorize }

/// 练习 / 背题页面。
class PracticePage extends StatefulWidget {
  const PracticePage({
    super.key,
    required this.questions,
    required this.mode,
    this.autoNext = false,
    this.title = '练习',
  });

  final List<Question> questions;
  final PracticeMode mode;
  final bool autoNext;
  final String title;

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  int _index = 0;
  final Set<String> _picked = {};
  bool _answered = false;
  bool _lastCorrect = false;
  final Set<int> _recorded = {};
  int _correctCount = 0;
  int _answeredCount = 0;
  bool _finished = false;

  bool get _memorize => widget.mode == PracticeMode.memorize;

  Question get _question => widget.questions[_index];

  @override
  void initState() {
    super.initState();
    if (_memorize) _answered = true;
  }

  void _tapOption(String letter) {
    if (_answered && !_memorize) return;
    if (_memorize) return;
    final q = _question;
    if (q.isMulti) {
      setState(() {
        if (_picked.contains(letter)) {
          _picked.remove(letter);
        } else {
          _picked.add(letter);
        }
      });
    } else {
      setState(() {
        _picked
          ..clear()
          ..add(letter);
      });
      _submit();
    }
  }

  Future<void> _submit() async {
    if (_answered || _picked.isEmpty) return;
    final q = _question;
    final correct = q.isCorrect(_picked);
    setState(() {
      _answered = true;
      _lastCorrect = correct;
      _answeredCount++;
      if (correct) _correctCount++;
    });
    if (q.id != null && !_recorded.contains(q.id)) {
      _recorded.add(q.id!);
      await Repo.recordAnswer(q, correct);
    }
    if (correct && widget.autoNext && _index < widget.questions.length - 1) {
      await Future.delayed(const Duration(milliseconds: 350));
      if (mounted && _answered && _lastCorrect) _next();
    }
  }

  void _goTo(int index) {
    setState(() {
      _index = index;
      _picked.clear();
      _answered = _memorize;
      _lastCorrect = false;
    });
  }

  void _next() {
    if (_index < widget.questions.length - 1) {
      _goTo(_index + 1);
    } else {
      setState(() => _finished = true);
    }
  }

  String _displayAnswer(Question q) {
    if (q.isJudge) return q.answer == 'A' ? '正确' : '错误';
    return q.answer;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _memorize ? '背题 · ${widget.title}' : widget.title,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: widget.questions.isEmpty
          ? const Center(child: Text('没有符合条件的题目'))
          : _finished
              ? _buildResult()
              : _buildQuestion(),
    );
  }

  Widget _buildResult() {
    final theme = Theme.of(context);
    if (_memorize) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 56),
            const SizedBox(height: 12),
            Text('已过完 ${widget.questions.length} 题',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回'),
            ),
          ],
        ),
      );
    }
    final total = _answeredCount;
    final accuracy =
        total == 0 ? 0.0 : _correctCount * 100.0 / total;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              accuracy >= 60
                  ? Icons.emoji_events_outlined
                  : Icons.fitness_center,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text('练习完成', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(
              '答题 $total 道 · 答对 $_correctCount 道\n正确率 ${accuracy.toStringAsFixed(0)}%'
              '${total - _correctCount > 0 ? '\n错题已自动加入错题本' : ''}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion() {
    final theme = Theme.of(context);
    final q = _question;
    final letters = q.optionLetters;
    return Column(
      children: [
        // 进度条
        LinearProgressIndicator(
          value: (_index + 1) / widget.questions.length,
          minHeight: 3,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(q.type, style: theme.textTheme.labelSmall),
              ),
              if (q.chapter.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    q.chapter,
                    style: theme.textTheme.labelSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const Spacer(),
              Text(
                '${_index + 1} / ${widget.questions.length}',
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(q.stem, style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              for (var i = 0; i < q.options.length; i++)
                _OptionTile(
                  letter: letters[i],
                  text: q.options[i],
                  multi: q.isMulti,
                  selected: _picked.contains(letters[i]),
                  answered: _answered,
                  isCorrectAnswer: q.answerLetters.contains(letters[i]),
                  onTap: () => _tapOption(letters[i]),
                ),
              if (_answered) ...[
                const SizedBox(height: 12),
                Card(
                  color: _memorize || _lastCorrect
                      ? const Color(0xFF2E7D32).withValues(alpha: 0.08)
                      : const Color(0xFFC62828).withValues(alpha: 0.08),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _memorize
                              ? '答案：${_displayAnswer(q)}'
                              : _lastCorrect
                                  ? '回答正确 · 答案：${_displayAnswer(q)}'
                                  : '回答错误 · 正确答案：${_displayAnswer(q)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _memorize || _lastCorrect
                                ? const Color(0xFF2E7D32)
                                : const Color(0xFFC62828),
                          ),
                        ),
                        if (q.analysis.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('解析：${q.analysis}'),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        // 底部操作栏
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
                  child: const Text('上一题'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _memorize || _answered
                      ? FilledButton(
                          onPressed: _next,
                          child: Text(
                            _index == widget.questions.length - 1
                                ? (_memorize ? '完成背题' : '完成练习')
                                : '下一题',
                          ),
                        )
                      : q.isMulti
                          ? FilledButton(
                              onPressed: _picked.isEmpty ? null : _submit,
                              child: const Text('提交'),
                            )
                          : const FilledButton(
                              onPressed: null,
                              child: Text('点选选项作答'),
                            ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.letter,
    required this.text,
    required this.multi,
    required this.selected,
    required this.answered,
    required this.isCorrectAnswer,
    required this.onTap,
  });

  final String letter;
  final String text;
  final bool multi;
  final bool selected;
  final bool answered;
  final bool isCorrectAnswer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color? tileColor;
    Color? borderColor = theme.dividerColor;
    Color letterColor = theme.colorScheme.onSurfaceVariant;
    if (answered) {
      if (isCorrectAnswer) {
        tileColor = const Color(0xFF2E7D32).withValues(alpha: 0.10);
        borderColor = const Color(0xFF2E7D32);
        letterColor = const Color(0xFF2E7D32);
      } else if (selected) {
        tileColor = const Color(0xFFC62828).withValues(alpha: 0.10);
        borderColor = const Color(0xFFC62828);
        letterColor = const Color(0xFFC62828);
      }
    } else if (selected) {
      tileColor = theme.colorScheme.primaryContainer.withValues(alpha: 0.5);
      borderColor = theme.colorScheme.primary;
      letterColor = theme.colorScheme.primary;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: tileColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: borderColor),
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
                    border: Border.all(color: letterColor, width: 1.4),
                    color: selected || (answered && isCorrectAnswer)
                        ? letterColor.withValues(alpha: 0.15)
                        : null,
                  ),
                  child: Text(
                    letter,
                    style: TextStyle(
                      color: letterColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
                if (answered && isCorrectAnswer)
                  const Icon(Icons.check_circle,
                      size: 20, color: Color(0xFF2E7D32))
                else if (answered && selected)
                  const Icon(Icons.cancel, size: 20, color: Color(0xFFC62828)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
