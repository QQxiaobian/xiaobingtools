import 'package:flutter/material.dart';

import '../../core/db/repo.dart';
import '../../core/models/quiz.dart';
import 'practice_page.dart';

/// 错题本：答错自动收录，连对 [QuestionStat.masteredStreak] 次自动移出。
class WrongBookPage extends StatefulWidget {
  const WrongBookPage({super.key});

  @override
  State<WrongBookPage> createState() => _WrongBookPageState();
}

class _WrongBookPageState extends State<WrongBookPage> {
  List<Question> _questions = [];
  List<QuestionBank> _banks = [];
  int? _bankFilter;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final banks = await Repo.quizBanks();
    final questions = await Repo.wrongQuestions(bankId: _bankFilter);
    if (!mounted) return;
    setState(() {
      _banks = banks;
      _questions = questions;
      _loading = false;
    });
  }

  String _bankName(int id) {
    for (final bank in _banks) {
      if (bank.id == id) return bank.name;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('错题本')),
      floatingActionButton: _questions.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PracticePage(
                      questions: _questions,
                      mode: PracticeMode.sequential,
                      title: '错题练习',
                    ),
                  ),
                );
                await _reload();
              },
              icon: const Icon(Icons.play_arrow),
              label: Text('开始练习（${_questions.length}）'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_banks.isNotEmpty)
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
                            label: const Text('全部题库'),
                            selected: _bankFilter == null,
                            onSelected: (_) {
                              setState(() => _bankFilter = null);
                              _reload();
                            },
                          ),
                        ),
                        for (final bank in _banks)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(bank.name),
                              selected: _bankFilter == bank.id,
                              onSelected: (_) {
                                setState(() => _bankFilter = bank.id);
                                _reload();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '连对 ${QuestionStat.masteredStreak} 次后自动移出错题本',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                Expanded(
                  child: _questions.isEmpty
                      ? const Center(
                          child: Text(
                            '暂无待攻克错题\n练习中答错的题目会自动收录到这里',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 96, top: 4),
                          itemCount: _questions.length,
                          itemBuilder: (context, index) {
                            final q = _questions[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              child: ListTile(
                                title: Text(
                                  q.stem,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${_bankName(q.bankId)} · ${q.type}'
                                  ' · 答案 ${q.isJudge ? (q.answer == 'A' ? '正确' : '错误') : q.answer}',
                                ),
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
