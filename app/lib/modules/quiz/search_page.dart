import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/db/repo.dart';
import '../../core/models/quiz.dart';

/// 跨题库搜题：结果直接显示答案与解析。
class QuizSearchPage extends StatefulWidget {
  const QuizSearchPage({super.key});

  @override
  State<QuizSearchPage> createState() => _QuizSearchPageState();
}

class _QuizSearchPageState extends State<QuizSearchPage> {
  final _controller = TextEditingController();
  List<Question> _results = [];
  Map<int, String> _bankNames = {};
  bool _searching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadBankNames();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadBankNames() async {
    final banks = await Repo.quizBanks();
    if (!mounted) return;
    setState(() {
      _bankNames = {
        for (final bank in banks)
          if (bank.id != null) bank.id!: bank.name,
      };
    });
  }

  void _onChanged(String keyword) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(keyword));
  }

  Future<void> _search(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    final results = await Repo.searchQuestions(trimmed);
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜索题干 / 选项 / 答案 / 解析',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              tooltip: '清空',
              onPressed: () {
                _controller.clear();
                _onChanged('');
              },
              icon: const Icon(Icons.clear),
            ),
        ],
      ),
      body: _searching
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
              ? Center(
                  child: Text(
                    _controller.text.trim().isEmpty ? '输入关键词搜索全部题库' : '没有找到相关题目',
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24, top: 4),
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final q = _results[index];
                    final letters = q.optionLetters;
                    final answerText =
                        q.isJudge ? (q.answer == 'A' ? '正确' : '错误') : q.answer;
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              q.stem,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_bankNames[q.bankId] ?? ''} · ${q.type}'
                              '${q.chapter.isEmpty ? '' : ' · ${q.chapter}'}',
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            for (var i = 0; i < q.options.length; i++)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  '${letters[i]}. ${q.options[i]}',
                                  style: TextStyle(
                                    color: q.answerLetters
                                            .contains(letters[i])
                                        ? const Color(0xFF2E7D32)
                                        : null,
                                    fontWeight:
                                        q.answerLetters.contains(letters[i])
                                            ? FontWeight.w600
                                            : null,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2E7D32)
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '答案：$answerText',
                                style: const TextStyle(
                                  color: Color(0xFF2E7D32),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (q.analysis.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text('解析：${q.analysis}'),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
