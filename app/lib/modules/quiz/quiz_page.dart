import 'package:flutter/material.dart';

import '../../core/db/repo.dart';
import '../../core/models/quiz.dart';
import '../io/file_actions.dart';
import 'bank_page.dart';
import 'exam_page.dart';
import 'quiz_io.dart';
import 'sample_questions.dart';
import 'search_page.dart';
import 'wrong_page.dart';

/// 刷题首页：统计概览、错题本/模拟考试入口、题库管理。
class QuizPage extends StatefulWidget {
  const QuizPage({super.key});

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  List<QuestionBank> _banks = [];
  Map<int, int> _counts = {};
  Map<String, int> _overview = const {};
  int _wrongCount = 0;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final banks = await Repo.quizBanks();
    final overview = await Repo.quizOverview();
    final wrongCount = await Repo.wrongQuestionCount();
    final counts = <int, int>{};
    for (final bank in banks) {
      if (bank.id != null) counts[bank.id!] = await Repo.questionCount(bank.id!);
    }
    if (!mounted) return;
    setState(() {
      _banks = banks;
      _counts = counts;
      _overview = overview;
      _wrongCount = wrongCount;
      _loading = false;
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editBankName([QuestionBank? bank]) async {
    final controller = TextEditingController(text: bank?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(bank == null ? '新建题库' : '重命名题库'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '题库名称，如：安规题库',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;
    if (bank == null) {
      await Repo.insertQuestionBank(
        QuestionBank(name: trimmed, createdAt: DateTime.now().toIso8601String()),
      );
    } else {
      await Repo.updateQuestionBank(bank.copyWith(name: trimmed));
    }
    await _reload();
  }

  Future<void> _deleteBank(QuestionBank bank) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除题库'),
        content: Text('确定删除「${bank.name}」吗？题目和答题记录会一并删除。'),
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
    if (confirmed != true || bank.id == null) return;
    await Repo.deleteQuestionBank(bank.id!);
    await _reload();
  }

  Future<void> _import({int? bankId}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await QuizIo.importBanks(targetBankId: bankId);
      if (result == null) return;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导入完成'),
          content: Text(
            result.summary +
                (result.warnings.isEmpty
                    ? ''
                    : '\n\n${result.warnings.take(8).join('\n')}'
                      '${result.warnings.length > 8 ? '\n…共 ${result.warnings.length} 条提示' : ''}'),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      await _reload();
    } catch (e) {
      _toast('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportTemplate() async {
    try {
      final file = await QuizIo.exportTemplate();
      if (!mounted) return;
      await showExportResult(context, file, title: '题库模板已导出');
    } catch (e) {
      _toast('导出失败：$e');
    }
  }

  Future<void> _loadSample() async {
    final bankId = await Repo.insertQuestionBank(
      QuestionBank(
        name: '示例题库（安规）',
        remark: '内置示例，可随时删除',
        createdAt: DateTime.now().toIso8601String(),
      ),
    );
    await Repo.insertQuestions(sampleQuestions(bankId));
    await _reload();
  }

  Future<void> _openBank(QuestionBank bank) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BankPage(bank: bank)),
    );
    await _reload();
  }

  String get _accuracyText {
    final correct = _overview['correct'] ?? 0;
    final wrong = _overview['wrong'] ?? 0;
    final total = correct + wrong;
    if (total == 0) return '--';
    return '${(correct * 100 / total).toStringAsFixed(0)}%';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('刷题'),
        actions: [
          IconButton(
            tooltip: '搜题',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const QuizSearchPage()),
            ),
            icon: const Icon(Icons.search),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (value) {
              switch (value) {
                case 'import':
                  _import();
                case 'template':
                  _exportTemplate();
                case 'sample':
                  _loadSample();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'import', child: Text('导入题库（xlsx/csv）')),
              PopupMenuItem(value: 'template', child: Text('导出导入模板')),
              PopupMenuItem(value: 'sample', child: Text('载入示例题库')),
            ],
          ),
        ],
      ),
      floatingActionButton: _banks.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _editBankName(),
              icon: const Icon(Icons.add),
              label: const Text('新建题库'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  // 统计概览
                  Card(
                    margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _Stat(label: '题目总数', value: '${_overview['total'] ?? 0}'),
                          _Stat(label: '已练题数', value: '${_overview['practiced'] ?? 0}'),
                          _Stat(label: '总正确率', value: _accuracyText),
                        ],
                      ),
                    ),
                  ),
                  // 错题本 / 模拟考试
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: _EntryCard(
                            icon: Icons.bookmark_added_outlined,
                            color: const Color(0xFFC62828),
                            title: '错题本',
                            subtitle: _wrongCount == 0
                                ? '暂无待攻克错题'
                                : '$_wrongCount 道待攻克',
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const WrongBookPage(),
                                ),
                              );
                              await _reload();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _EntryCard(
                            icon: Icons.fact_check_outlined,
                            color: const Color(0xFF1565C0),
                            title: '模拟考试',
                            subtitle: '随机组卷 · 计时判分',
                            onTap: _banks.isEmpty
                                ? null
                                : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const ExamSetupPage(),
                                      ),
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text('题库', style: theme.textTheme.titleSmall),
                  ),
                  if (_banks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(Icons.quiz_outlined,
                              size: 56, color: theme.colorScheme.primary),
                          const SizedBox(height: 12),
                          const Text('还没有题库', textAlign: TextAlign.center),
                          const SizedBox(height: 4),
                          Text(
                            '导入 Excel/CSV 题库，或先载入示例题库体验',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              FilledButton.icon(
                                onPressed: _busy ? null : () => _import(),
                                icon: const Icon(Icons.upload_file_outlined),
                                label: const Text('导入题库'),
                              ),
                              OutlinedButton(
                                onPressed: _loadSample,
                                child: const Text('载入示例题库'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else
                    for (final bank in _banks)
                      Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: ListTile(
                          title: Text(
                            bank.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text('共 ${_counts[bank.id] ?? 0} 题'),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              switch (value) {
                                case 'rename':
                                  _editBankName(bank);
                                case 'import':
                                  _import(bankId: bank.id);
                                case 'delete':
                                  _deleteBank(bank);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'rename', child: Text('重命名')),
                              PopupMenuItem(
                                value: 'import',
                                child: Text('导入题目到此题库'),
                              ),
                              PopupMenuItem(value: 'delete', child: Text('删除题库')),
                            ],
                          ),
                          onTap: () => _openBank(bank),
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
