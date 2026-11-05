import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../models/flaw.dart';
import '../models/line.dart';
import '../models/quiz.dart';
import '../models/tower.dart';

/// 简单的数据访问层，全部为静态方法，界面直接调用。
class Repo {
  Repo._();

  static Future<List<Line>> lines() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('lines', orderBy: 'name COLLATE NOCASE');
    return rows.map(Line.fromMap).toList();
  }

  static Future<Line?> lineById(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('lines', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Line.fromMap(rows.first);
  }

  static Future<Line?> lineByName(String name) async {
    final db = await AppDatabase.instance.database;
    final rows =
        await db.query('lines', where: 'name = ?', whereArgs: [name], limit: 1);
    if (rows.isEmpty) return null;
    return Line.fromMap(rows.first);
  }

  static Future<int> insertLine(Line line) async {
    final db = await AppDatabase.instance.database;
    return db.insert('lines', line.toMap()..remove('id'));
  }

  static Future<void> updateLine(Line line) async {
    final db = await AppDatabase.instance.database;
    await db.update('lines', line.toMap(), where: 'id = ?', whereArgs: [line.id]);
  }

  static Future<void> deleteLine(int id) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.delete('towers', where: 'line_id = ?', whereArgs: [id]);
      await txn.delete('flaws', where: 'line_id = ?', whereArgs: [id]);
      await txn.delete('lines', where: 'id = ?', whereArgs: [id]);
    });
  }

  static Future<List<Tower>> towers([int? lineId]) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'towers',
      where: lineId == null ? null : 'line_id = ?',
      whereArgs: lineId == null ? null : [lineId],
      orderBy: 'seq ASC, tower_no ASC',
    );
    return rows.map(Tower.fromMap).toList();
  }

  static Future<int> insertTower(Tower tower) async {
    final db = await AppDatabase.instance.database;
    return db.insert('towers', tower.toMap()..remove('id'));
  }

  static Future<void> updateTower(Tower tower) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'towers',
      tower.toMap(),
      where: 'id = ?',
      whereArgs: [tower.id],
    );
  }

  static Future<void> deleteTower(int id) async {
    final db = await AppDatabase.instance.database;
    await db.delete('towers', where: 'id = ?', whereArgs: [id]);
  }

  static Future<Tower?> towerById(int id) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('towers', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Tower.fromMap(rows.first);
  }

  static Future<List<Flaw>> flaws() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('flaws', orderBy: 'created_at DESC');
    return rows.map(Flaw.fromMap).toList();
  }

  static Future<List<Flaw>> flawsOfLine(int lineId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'flaws',
      where: 'line_id = ?',
      whereArgs: [lineId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Flaw.fromMap).toList();
  }

  static Future<int> insertFlaw(Flaw flaw) async {
    final db = await AppDatabase.instance.database;
    return db.insert('flaws', flaw.toMap()..remove('id'));
  }

  static Future<void> updateFlaw(Flaw flaw) async {
    final db = await AppDatabase.instance.database;
    await db.update('flaws', flaw.toMap(), where: 'id = ?', whereArgs: [flaw.id]);
  }

  static Future<void> deleteFlaw(int id) async {
    final db = await AppDatabase.instance.database;
    await db.delete('flaws', where: 'id = ?', whereArgs: [id]);
  }

  // ---------- 刷题 ----------

  static Future<List<QuestionBank>> quizBanks() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('quiz_banks', orderBy: 'id ASC');
    return rows.map(QuestionBank.fromMap).toList();
  }

  static Future<int> insertQuestionBank(QuestionBank bank) async {
    final db = await AppDatabase.instance.database;
    return db.insert('quiz_banks', bank.toMap()..remove('id'));
  }

  static Future<void> updateQuestionBank(QuestionBank bank) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'quiz_banks',
      bank.toMap(),
      where: 'id = ?',
      whereArgs: [bank.id],
    );
  }

  /// 删除题库及其题目与答题记录。
  static Future<void> deleteQuestionBank(int id) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.delete(
        'quiz_stats',
        where:
            'question_id IN (SELECT id FROM quiz_questions WHERE bank_id = ?)',
        whereArgs: [id],
      );
      await txn.delete('quiz_questions', where: 'bank_id = ?', whereArgs: [id]);
      await txn.delete('quiz_banks', where: 'id = ?', whereArgs: [id]);
    });
  }

  static Future<List<Question>> questions(int bankId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'quiz_questions',
      where: 'bank_id = ?',
      whereArgs: [bankId],
      orderBy: 'seq ASC, id ASC',
    );
    return rows.map(Question.fromMap).toList();
  }

  static Future<int> questionCount(int bankId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM quiz_questions WHERE bank_id = ?',
      [bankId],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  static Future<int> insertQuestion(Question question) async {
    final db = await AppDatabase.instance.database;
    return db.insert('quiz_questions', question.toMap()..remove('id'));
  }

  static Future<void> insertQuestions(List<Question> questions) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      var seq = 0;
      for (final question in questions) {
        seq++;
        await txn.insert(
          'quiz_questions',
          question.copyWith(seq: seq).toMap()..remove('id'),
        );
      }
    });
  }

  static Future<void> updateQuestion(Question question) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'quiz_questions',
      question.toMap(),
      where: 'id = ?',
      whereArgs: [question.id],
    );
  }

  static Future<void> deleteQuestion(int id) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.delete('quiz_stats', where: 'question_id = ?', whereArgs: [id]);
      await txn.delete('quiz_questions', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// 题库内去重后的章节列表。
  static Future<List<String>> questionChapters(int bankId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT chapter FROM quiz_questions '
      "WHERE bank_id = ? AND chapter != '' ORDER BY chapter",
      [bankId],
    );
    return rows.map((row) => row['chapter'] as String).toList();
  }

  /// 跨题库按关键词搜题（题干 / 解析 / 选项）。
  static Future<List<Question>> searchQuestions(String keyword) async {
    final db = await AppDatabase.instance.database;
    final like = '%$keyword%';
    final rows = await db.query(
      'quiz_questions',
      where: 'stem LIKE ? OR analysis LIKE ? OR options LIKE ?',
      whereArgs: [like, like, like],
      orderBy: 'bank_id ASC, seq ASC',
      limit: 200,
    );
    return rows.map(Question.fromMap).toList();
  }

  /// 记录一次答题结果，维护正确/错误计数与连对次数。
  static Future<void> recordAnswer(Question question, bool correct) async {
    if (question.id == null) return;
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'quiz_stats',
        where: 'question_id = ?',
        whereArgs: [question.id],
      );
      final stat = rows.isEmpty
          ? QuestionStat(questionId: question.id!, bankId: question.bankId)
          : QuestionStat.fromMap(rows.first);
      final next = correct
          ? QuestionStat(
              questionId: question.id!,
              bankId: question.bankId,
              correctCount: stat.correctCount + 1,
              wrongCount: stat.wrongCount,
              streak: stat.streak + 1,
              lastWrongAt: stat.lastWrongAt,
              updatedAt: now,
            )
          : QuestionStat(
              questionId: question.id!,
              bankId: question.bankId,
              correctCount: stat.correctCount,
              wrongCount: stat.wrongCount + 1,
              streak: 0,
              lastWrongAt: now,
              updatedAt: now,
            );
      await txn.insert(
        'quiz_stats',
        next.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  /// 错题本：答错过且未连续答对 [QuestionStat.masteredStreak] 次的题。
  static Future<List<Question>> wrongQuestions({int? bankId}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT q.* FROM quiz_questions q '
      'INNER JOIN quiz_stats s ON s.question_id = q.id '
      'WHERE s.wrong_count > 0 AND s.streak < ? '
      '${bankId == null ? '' : 'AND q.bank_id = ? '}'
      'ORDER BY s.last_wrong_at DESC',
      [QuestionStat.masteredStreak, if (bankId != null) bankId],
    );
    return rows.map(Question.fromMap).toList();
  }

  /// 错题本待攻克数量（可按题库过滤）。
  static Future<int> wrongQuestionCount({int? bankId}) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM quiz_stats s '
      'WHERE s.wrong_count > 0 AND s.streak < ? '
      '${bankId == null ? '' : 'AND s.bank_id = ? '}',
      [QuestionStat.masteredStreak, if (bankId != null) bankId],
    );
    return (rows.first.values.first as int?) ?? 0;
  }

  /// 全局刷题概览：总题数、已答题数、总正确率。
  static Future<Map<String, int>> quizOverview() async {
    final db = await AppDatabase.instance.database;
    final totals = await db.rawQuery('SELECT COUNT(*) AS c FROM quiz_questions');
    final stats = await db.rawQuery(
      'SELECT COUNT(*) AS practiced, '
      'COALESCE(SUM(correct_count), 0) AS correct, '
      'COALESCE(SUM(wrong_count), 0) AS wrong FROM quiz_stats',
    );
    return {
      'total': (totals.first['c'] as int?) ?? 0,
      'practiced': (stats.first['practiced'] as int?) ?? 0,
      'correct': (stats.first['correct'] as int?) ?? 0,
      'wrong': (stats.first['wrong'] as int?) ?? 0,
    };
  }
}
