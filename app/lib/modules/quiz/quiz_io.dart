import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../core/db/repo.dart';
import '../../core/models/quiz.dart';
import '../io/data_io.dart';
import '../io/xlsx_reader.dart';

class QuizImportResult {
  int banksAdded = 0;
  int questionsAdded = 0;
  int skipped = 0;
  final List<String> warnings = [];

  String get summary => banksAdded > 0
      ? '导入题库 $banksAdded 个、题目 $questionsAdded 道'
          '${skipped > 0 ? '，跳过 $skipped 行' : ''}'
      : '导入题目 $questionsAdded 道${skipped > 0 ? '，跳过 $skipped 行' : ''}';
}

/// 题库 Excel/CSV 导入与模板导出。
///
/// 表头别名自动识别：题干/题目、题型/类型、章节/知识点、选项A-F（或 A-F）、
/// 答案、解析；找不到表头时报错并提示使用模板。
class QuizIo {
  QuizIo._();

  static const List<String> templateHeaders = [
    '题型', '章节', '题干', '选项A', '选项B', '选项C', '选项D', '选项E', '选项F',
    '答案', '解析',
  ];

  static const _stemAliases = ['题干', '题目', '问题', '试题', '内容'];
  static const _typeAliases = ['题型', '类型'];
  static const _chapterAliases = ['章节', '知识点', '分类'];
  static const _answerAliases = ['答案', '正确答案', '参考答案'];
  static const _analysisAliases = ['解析', '答案解析', '说明'];

  /// 选择文件导入题库。[targetBankId] 不为空时全部导入该题库，
  /// 否则每个非空工作表生成一个独立题库。
  static Future<QuizImportResult?> importBanks({int? targetBankId}) async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
      dialogTitle: '选择题库文件（xlsx / csv）',
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) {
      throw const FileSystemException('无法读取所选文件');
    }

    final List<XlsxSheetData> sheets;
    if (picked.name.toLowerCase().endsWith('.csv')) {
      sheets = [
        XlsxSheetData(
          p.basenameWithoutExtension(picked.name),
          _parseCsv(bytes),
        ),
      ];
    } else {
      sheets = XlsxReader.read(bytes);
    }
    if (sheets.isEmpty) {
      throw const FormatException('文件中没有可读取的工作表');
    }

    final result = QuizImportResult();
    for (final sheet in sheets) {
      final questions = _parseSheet(sheet, result.warnings);
      if (questions.isEmpty) {
        if (sheet.rows.isNotEmpty) {
          result.warnings.add('工作表「${sheet.name}」没有可导入的题目');
        }
        continue;
      }
      int bankId;
      if (targetBankId != null) {
        bankId = targetBankId;
      } else {
        bankId = await Repo.insertQuestionBank(
          QuestionBank(
            name: sheet.name,
            createdAt: DateTime.now().toIso8601String(),
          ),
        );
        result.banksAdded++;
      }
      await Repo.insertQuestions(
        questions.map((q) => q.copyWith(bankId: bankId)).toList(),
      );
      result.questionsAdded += questions.length;
      result.skipped += _lastSkipped;
    }
    if (result.questionsAdded == 0) {
      throw FormatException(
        '没有导入任何题目。\n请确认表头包含：${templateHeaders.join('、')}\n'
        '可先在题库页导出模板参考。',
      );
    }
    return result;
  }

  /// 导出空白模板（含一行单选、一行判断示例）。
  static Future<File> exportTemplate() async {
    final excel = Excel.createExcel();
    final sheet = excel['题库模板'];
    excel.delete('Sheet1');
    sheet.appendRow(templateHeaders.map(TextCellValue.new).toList());
    sheet.appendRow([
      TextCellValue('单选'),
      TextCellValue('第一章'),
      TextCellValue('示例：高空作业应使用哪种安全防护用具？'),
      TextCellValue('安全带'),
      TextCellValue('普通绳索'),
      TextCellValue('塑料安全帽'),
      TextCellValue('帆布鞋'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue('A'),
      TextCellValue('高空作业必须系安全带。'),
    ]);
    sheet.appendRow([
      TextCellValue('判断'),
      TextCellValue('第一章'),
      TextCellValue('示例：雷雨天气可以进行杆塔检修作业。'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue('错误'),
      TextCellValue('雷雨天气禁止登塔作业。'),
    ]);
    final file = File(
      p.join((await DataIo.exportsDir()).path, '题库导入模板.xlsx'),
    );
    final bytes = excel.save();
    if (bytes == null) {
      throw const FileSystemException('生成模板失败');
    }
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  // ---------- 解析 ----------

  static int _lastSkipped = 0;

  static List<Question> _parseSheet(XlsxSheetData sheet, List<String> warnings) {
    _lastSkipped = 0;
    final rows = sheet.rows;
    final questions = <Question>[];
    if (rows.isEmpty) return questions;

    // 在前若干行里找表头：至少命中题干 + 答案/题型 之一。
    var headerRow = -1;
    Map<String, int> header = const {};
    for (var i = 0; i < rows.length && i < 10; i++) {
      final candidate = _headerIndex(rows[i]);
      final hasStem = _findColumn(candidate, _stemAliases) != null;
      final hasOther = _findColumn(candidate, _typeAliases) != null ||
          _findColumn(candidate, _answerAliases) != null;
      if (hasStem && hasOther) {
        headerRow = i;
        header = candidate;
        break;
      }
    }
    if (headerRow < 0) {
      if (rows.any((row) => row.any((cell) => cell.trim().isNotEmpty))) {
        warnings.add('工作表「${sheet.name}」未识别到表头，已跳过');
      }
      return questions;
    }

    final stemCol = _findColumn(header, _stemAliases);
    final typeCol = _findColumn(header, _typeAliases);
    final chapterCol = _findColumn(header, _chapterAliases);
    final answerCol = _findColumn(header, _answerAliases);
    final analysisCol = _findColumn(header, _analysisAliases);
    final optionCols = _optionColumns(header);
    if (stemCol == null || answerCol == null) {
      warnings.add('工作表「${sheet.name}」缺少题干或答案列');
      return questions;
    }

    for (var i = headerRow + 1; i < rows.length; i++) {
      final row = rows[i];
      final stem = _cell(row, stemCol);
      if (stem.isEmpty) {
        if (row.any((cell) => cell.trim().isNotEmpty)) _lastSkipped++;
        continue;
      }
      final options = [
        for (final col in optionCols)
          if (_cell(row, col).isNotEmpty) _cell(row, col),
      ];
      final rawAnswer = _cell(row, answerCol);
      var type = _normType(_cell(row, typeCol));
      final letters = _answerLetters(rawAnswer);
      // 未填题型时按选项数量与答案形式推断。
      if (type.isEmpty) {
        if (options.isEmpty) {
          type = _judgeAnswer(rawAnswer) != null ? Question.typeJudge : '';
        } else {
          type = letters.length > 1 ? Question.typeMulti : Question.typeSingle;
        }
      }
      // 无选项的“选择题”按答案降级为判断题。
      if (options.isEmpty && type != Question.typeJudge) {
        if (_judgeAnswer(rawAnswer) != null) {
          type = Question.typeJudge;
        } else {
          _lastSkipped++;
          warnings.add('第 ${i + 1} 行缺少选项，已跳过');
          continue;
        }
      }
      final String answer;
      if (type == Question.typeJudge) {
        // 判断题只接受 对/错/√/×/A/B 等已知写法，其余视为无法识别。
        answer = _judgeAnswer(rawAnswer) ?? '';
      } else {
        answer = letters;
      }
      if (type.isEmpty || answer.isEmpty) {
        _lastSkipped++;
        warnings.add('第 ${i + 1} 行答案无法识别，已跳过');
        continue;
      }
      questions.add(
        Question(
          bankId: 0,
          type: type,
          chapter: _cell(row, chapterCol),
          stem: stem,
          options: type == Question.typeJudge ? const ['正确', '错误'] : options,
          answer: answer,
          analysis: _cell(row, analysisCol),
        ),
      );
    }
    return questions;
  }

  static String _normType(String raw) {
    final value = raw.trim();
    if (value.contains('多选')) return Question.typeMulti;
    if (value.contains('判断')) return Question.typeJudge;
    if (value.contains('单选')) return Question.typeSingle;
    return '';
  }

  /// 提取答案字母（A-J），去重排序，如 "abd" → "ABD"。
  static String _answerLetters(String raw) {
    final value = raw.replaceAll('答案', '').replaceAll('：', '');
    final letters = <String>{};
    for (final code in value.toUpperCase().codeUnits) {
      if (code >= 65 && code <= 74) {
        letters.add(String.fromCharCode(code));
      }
    }
    final sorted = letters.toList()..sort();
    return sorted.join();
  }

  static String? _judgeAnswer(String raw) {
    switch (raw.trim()) {
      case '对':
      case '正确':
      case '是':
      case '√':
      case 'T':
      case 't':
      case 'TRUE':
      case 'true':
      case 'A':
      case 'a':
        return 'A';
      case '错':
      case '错误':
      case '否':
      case '×':
      case 'x':
      case 'X':
      case 'F':
      case 'f':
      case 'FALSE':
      case 'false':
      case 'B':
      case 'b':
        return 'B';
    }
    return null;
  }

  /// 选项列：支持「选项A」或单独的「A」列头。
  static List<int> _optionColumns(Map<String, int> header) {
    final columns = <int, int>{}; // 字母序号 -> 列号
    header.forEach((key, index) {
      final upper = key.toUpperCase();
      if (upper.length == 1) {
        final code = upper.codeUnitAt(0);
        if (code >= 65 && code <= 70) columns[code - 65] = index;
      } else if (upper.startsWith('选项') && upper.length == 3) {
        final code = upper.codeUnitAt(2);
        if (code >= 65 && code <= 70) columns[code - 65] = index;
      }
    });
    final order = columns.keys.toList()..sort();
    return [for (final key in order) columns[key]!];
  }

  static int? _findColumn(Map<String, int> header, List<String> aliases) {
    for (final alias in aliases) {
      final index = header[alias];
      if (index != null) return index;
    }
    return null;
  }

  static Map<String, int> _headerIndex(List<String> row) {
    final map = <String, int>{};
    for (var i = 0; i < row.length; i++) {
      final key = row[i].trim().replaceAll(' ', '').replaceAll('　', '');
      if (key.isNotEmpty && !map.containsKey(key)) map[key] = i;
    }
    return map;
  }

  static String _cell(List<String> row, int? index) {
    if (index == null || index >= row.length) return '';
    return row[index].trim();
  }

  /// 简单 CSV 解析：支持引号包裹的逗号/换行。仅支持 UTF-8 编码。
  static List<List<String>> _parseCsv(List<int> bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.contains('\uFFFD')) {
      throw const FormatException('CSV 编码无法识别，请另存为 UTF-8 格式（或使用 xlsx）');
    }
    if (text.startsWith('\uFEFF')) text = text.substring(1);

    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (inQuotes) {
        if (char == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(char);
        }
        continue;
      }
      switch (char) {
        case '"':
          inQuotes = true;
        case ',':
          row.add(field.toString());
          field.clear();
        case '\n':
          row.add(field.toString());
          field.clear();
          rows.add(row);
          row = [];
        case '\r':
          break;
        default:
          field.write(char);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }
}
