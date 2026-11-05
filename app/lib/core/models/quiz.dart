import 'dart:convert';

/// 题库。
class QuestionBank {
  final int? id;
  final String name;
  final String remark;
  final String createdAt;

  const QuestionBank({
    this.id,
    required this.name,
    this.remark = '',
    this.createdAt = '',
  });

  factory QuestionBank.fromMap(Map<String, Object?> map) => QuestionBank(
        id: map['id'] as int?,
        name: (map['name'] as String?) ?? '',
        remark: (map['remark'] as String?) ?? '',
        createdAt: (map['created_at'] as String?) ?? '',
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'remark': remark,
        'created_at': createdAt,
      };

  QuestionBank copyWith({int? id, String? name, String? remark}) =>
      QuestionBank(
        id: id ?? this.id,
        name: name ?? this.name,
        remark: remark ?? this.remark,
        createdAt: createdAt,
      );
}

/// 题目。选项序列化为 JSON 数组存储；判断题固定为 ["正确", "错误"]。
class Question {
  static const typeSingle = '单选';
  static const typeMulti = '多选';
  static const typeJudge = '判断';

  static const types = [typeSingle, typeMulti, typeJudge];

  final int? id;
  final int bankId;
  final String type;
  final String chapter;
  final String stem;
  final List<String> options;
  final String answer;
  final String analysis;
  final int seq;

  const Question({
    this.id,
    required this.bankId,
    required this.type,
    required this.stem,
    this.chapter = '',
    this.options = const [],
    this.answer = '',
    this.analysis = '',
    this.seq = 0,
  });

  factory Question.fromMap(Map<String, Object?> map) {
    final rawOptions = (map['options'] as String?) ?? '';
    List<String> options;
    try {
      options = (jsonDecode(rawOptions) as List)
          .map((item) => item.toString())
          .toList();
    } catch (_) {
      options = const [];
    }
    return Question(
      id: map['id'] as int?,
      bankId: (map['bank_id'] as int?) ?? 0,
      type: (map['type'] as String?) ?? typeSingle,
      chapter: (map['chapter'] as String?) ?? '',
      stem: (map['stem'] as String?) ?? '',
      options: options,
      answer: (map['answer'] as String?) ?? '',
      analysis: (map['analysis'] as String?) ?? '',
      seq: (map['seq'] as int?) ?? 0,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'bank_id': bankId,
        'type': type,
        'chapter': chapter,
        'stem': stem,
        'options': jsonEncode(options),
        'answer': answer,
        'analysis': analysis,
        'seq': seq,
      };

  Question copyWith({
    int? id,
    int? bankId,
    String? type,
    String? chapter,
    String? stem,
    List<String>? options,
    String? answer,
    String? analysis,
    int? seq,
  }) =>
      Question(
        id: id ?? this.id,
        bankId: bankId ?? this.bankId,
        type: type ?? this.type,
        chapter: chapter ?? this.chapter,
        stem: stem ?? this.stem,
        options: options ?? this.options,
        answer: answer ?? this.answer,
        analysis: analysis ?? this.analysis,
        seq: seq ?? this.seq,
      );

  bool get isSingle => type == typeSingle;
  bool get isMulti => type == typeMulti;
  bool get isJudge => type == typeJudge;

  /// 选项字母，如 ["A", "B", "C"]。
  List<String> get optionLetters => [
        for (var i = 0; i < options.length; i++)
          String.fromCharCode(65 + i),
      ];

  /// 答案字母集合，如 {'A', 'C'}。
  Set<String> get answerLetters => answer.toUpperCase().split('').toSet();

  /// 判断用户答案（字母集合）是否正确。
  bool isCorrect(Set<String> picked) {
    final expected = answerLetters;
    if (picked.length != expected.length) return false;
    return picked.containsAll(expected);
  }
}

/// 单题答题统计，错题本 = wrongCount > 0 且 streak < [masteredStreak]。
class QuestionStat {
  /// 连续答对达到该次数视为已掌握，移出错题本。
  static const masteredStreak = 2;

  final int questionId;
  final int bankId;
  final int correctCount;
  final int wrongCount;
  final int streak;
  final String lastWrongAt;
  final String updatedAt;

  const QuestionStat({
    required this.questionId,
    this.bankId = 0,
    this.correctCount = 0,
    this.wrongCount = 0,
    this.streak = 0,
    this.lastWrongAt = '',
    this.updatedAt = '',
  });

  factory QuestionStat.fromMap(Map<String, Object?> map) => QuestionStat(
        questionId: (map['question_id'] as int?) ?? 0,
        bankId: (map['bank_id'] as int?) ?? 0,
        correctCount: (map['correct_count'] as int?) ?? 0,
        wrongCount: (map['wrong_count'] as int?) ?? 0,
        streak: (map['streak'] as int?) ?? 0,
        lastWrongAt: (map['last_wrong_at'] as String?) ?? '',
        updatedAt: (map['updated_at'] as String?) ?? '',
      );

  Map<String, Object?> toMap() => {
        'question_id': questionId,
        'bank_id': bankId,
        'correct_count': correctCount,
        'wrong_count': wrongCount,
        'streak': streak,
        'last_wrong_at': lastWrongAt,
        'updated_at': updatedAt,
      };

  bool get inWrongBook => wrongCount > 0 && streak < masteredStreak;
}
