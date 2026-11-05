import 'package:flutter/material.dart';

import '../../core/db/repo.dart';
import '../../core/models/quiz.dart';
import 'practice_page.dart';
import 'question_edit_page.dart';

/// 题库详情：题目列表（可按题型/章节筛选）、增删改、开始练习。
class BankPage extends StatefulWidget {
  const BankPage({super.key, required this.bank});

  final QuestionBank bank;

  @override
  State<BankPage> createState() => _BankPageState();
}

class _BankPageState extends State<BankPage> {
  List<Question> _questions = [];
  List<String> _chapters = [];
  String? _typeFilter;
  String? _chapterFilter;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final bankId = widget.bank.id;
    if (bankId == null) return;
    final questions = await Repo.questions(bankId);
    final chapters = await Repo.questionChapters(bankId);
    if (!mounted) return;
    setState(() {
      _questions = questions;
      _chapters = chapters;
      if (_chapterFilter != null && !chapters.contains(_chapterFilter)) {
        _chapterFilter = null;
      }
      _loading = false;
    });
  }

  List<Question> get _filtered => _questions.where((q) {
        if (_typeFilter != null && q.type != _typeFilter) return false;
        if (_chapterFilter != null && q.chapter != _chapterFilter) return false;
        return true;
      }).toList();

  Future<void> _editQuestion([Question? question]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => QuestionEditPage(bank: widget.bank, question: question),
      ),
    );
    if (saved == true) await _reload();
  }

  Future<void> _deleteQuestion(Question question) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除题目'),
        content: const Text('确定删除这道题吗？相关答题记录会一并删除。'),
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
    if (confirmed != true || question.id == null) return;
    await Repo.deleteQuestion(question.id!);
    await _reload();
  }

  /// 练习设置底部弹窗：模式、题型、章节、自动下一题。
  Future<void> _openPracticeSetup() async {
    if (_questions.isEmpty) return;
    var mode = PracticeMode.sequential;
    String? type;
    String? chapter;
    var autoNext = false;

    final started = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final count = _questions.where((q) {
            if (type != null && q.type != type) return false;
            if (chapter != null && q.chapter != chapter) return false;
            return true;
          }).length;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('练习设置', style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  SegmentedButton<PracticeMode>(
                    segments: const [
                      ButtonSegment(
                        value: PracticeMode.sequential,
                        label: Text('顺序'),
                        icon: Icon(Icons.format_list_numbered),
                      ),
                      ButtonSegment(
                        value: PracticeMode.random,
                        label: Text('随机'),
                        icon: Icon(Icons.shuffle),
                      ),
                      ButtonSegment(
                        value: PracticeMode.memorize,
                        label: Text('背题'),
                        icon: Icon(Icons.visibility_outlined),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (value) =>
                        setSheetState(() => mode = value.first),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('全部题型'),
                        selected: type == null,
                        onSelected: (_) => setSheetState(() => type = null),
                      ),
                      for (final t in Question.types)
                        ChoiceChip(
                          label: Text(t),
                          selected: type == t,
                          onSelected: (_) => setSheetState(() => type = t),
                        ),
                    ],
                  ),
                  if (_chapters.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          label: const Text('全部章节'),
                          selected: chapter == null,
                          onSelected: (_) => setSheetState(() => chapter = null),
                        ),
                        for (final c in _chapters)
                          ChoiceChip(
                            label: Text(c),
                            selected: chapter == c,
                            onSelected: (_) => setSheetState(() => chapter = c),
                          ),
                      ],
                    ),
                  ],
                  if (mode != PracticeMode.memorize)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('答对自动下一题'),
                      value: autoNext,
                      onChanged: (value) =>
                          setSheetState(() => autoNext = value),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: count == 0 ? null : () => Navigator.pop(ctx, true),
                      child: Text('开始练习（$count 题）'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (started != true || !mounted) return;
    var questions = _questions.where((q) {
      if (type != null && q.type != type) return false;
      if (chapter != null && q.chapter != chapter) return false;
      return true;
    }).toList();
    if (mode == PracticeMode.random) {
      questions = [...questions]..shuffle();
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PracticePage(
          questions: questions,
          mode: mode,
          autoNext: autoNext,
          title: widget.bank.name,
        ),
      ),
    );
    if (mounted) await _reload();
  }

  Color _typeColor(String type) {
    switch (type) {
      case Question.typeMulti:
        return const Color(0xFF6A1B9A);
      case Question.typeJudge:
        return const Color(0xFF2E7D32);
      default:
        return const Color(0xFF1565C0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bank.name),
        actions: [
          IconButton(
            tooltip: '筛选',
            onPressed: (_chapters.isEmpty && _questions.isEmpty)
                ? null
                : () async {
                    // 简单的筛选菜单：题型
                    final selected = await showModalBottomSheet<String>(
                      context: context,
                      builder: (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              title: const Text('全部题型'),
                              trailing: _typeFilter == null
                                  ? const Icon(Icons.check)
                                  : null,
                              onTap: () => Navigator.pop(ctx, ''),
                            ),
                            for (final t in Question.types)
                              ListTile(
                                title: Text(t),
                                trailing: _typeFilter == t
                                    ? const Icon(Icons.check)
                                    : null,
                                onTap: () => Navigator.pop(ctx, t),
                              ),
                          ],
                        ),
                      ),
                    );
                    if (selected != null) {
                      setState(
                        () => _typeFilter = selected.isEmpty ? null : selected,
                      );
                    }
                  },
            icon: const Icon(Icons.filter_list),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_questions.isNotEmpty)
            FloatingActionButton.extended(
              heroTag: 'practice',
              onPressed: _openPracticeSetup,
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始练习'),
            ),
          const SizedBox(height: 12),
          FloatingActionButton.small(
            heroTag: 'addQuestion',
            tooltip: '添加题目',
            onPressed: () => _editQuestion(),
            child: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _questions.isEmpty
              ? const Center(
                  child: Text(
                    '题库还没有题目\n点右下角添加，或回到题库列表导入 Excel',
                    textAlign: TextAlign.center,
                  ),
                )
              : Column(
                  children: [
                    if (_chapters.isNotEmpty)
                      SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: const Text('全部章节'),
                                selected: _chapterFilter == null,
                                onSelected: (_) =>
                                    setState(() => _chapterFilter = null),
                              ),
                            ),
                            for (final chapter in _chapters)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(chapter),
                                  selected: _chapterFilter == chapter,
                                  onSelected: (_) =>
                                      setState(() => _chapterFilter = chapter),
                                ),
                              ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 120, top: 4),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final q = filtered[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            child: ListTile(
                              leading: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _typeColor(q.type)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  q.type,
                                  style: TextStyle(
                                    color: _typeColor(q.type),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              title: Text(
                                q.stem,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${q.chapter.isEmpty ? '未分章节' : q.chapter}'
                                ' · 答案 ${q.isJudge ? (q.answer == 'A' ? '正确' : '错误') : q.answer}',
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _editQuestion(q);
                                  } else if (value == 'delete') {
                                    _deleteQuestion(q);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除'),
                                  ),
                                ],
                              ),
                              onTap: () => _editQuestion(q),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
