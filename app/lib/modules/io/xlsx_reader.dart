import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// 极简 xlsx 读取器：只取工作表名与单元格文本。
///
/// excel 包在解析部分现场台账（自定义 numFmtId 不规范）时会抛异常，
/// 这里作为兜底实现，不依赖 styles.xml。
class XlsxSheetData {
  const XlsxSheetData(this.name, this.rows);

  final String name;
  final List<List<String>> rows;
}

class XlsxReader {
  XlsxReader._();

  static List<XlsxSheetData> read(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final entries = <String, Uint8List>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final content = file.content;
      if (content is Uint8List) {
        entries[file.name] = content;
      } else if (content is List<int>) {
        entries[file.name] = Uint8List.fromList(content);
      }
    }

    final shared = _parseSharedStrings(entries['xl/sharedStrings.xml']);
    final relations = _parseRelations(entries['xl/_rels/workbook.xml.rels']);

    final sheets = <XlsxSheetData>[];
    final workbookBytes = entries['xl/workbook.xml'];
    if (workbookBytes == null) return sheets;
    final workbook = XmlDocument.parse(utf8.decode(workbookBytes));

    for (final element in workbook.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'sheet') continue;
      final name = element.getAttribute('name') ?? 'Sheet${sheets.length + 1}';
      final relationId = _relationId(element);
      final path = relations[relationId];
      if (path == null) continue;
      final sheetBytes = entries[path];
      if (sheetBytes == null) continue;
      sheets.add(
        XlsxSheetData(name, _parseSheet(utf8.decode(sheetBytes), shared)),
      );
    }
    return sheets;
  }

  static String _relationId(XmlElement element) {
    for (final attribute in element.attributes) {
      if (attribute.name.local == 'id') return attribute.value;
    }
    return '';
  }

  static Map<String, String> _parseRelations(Uint8List? bytes) {
    if (bytes == null) return const {};
    final doc = XmlDocument.parse(utf8.decode(bytes));
    final result = <String, String>{};
    for (final element in doc.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'Relationship') continue;
      final id = element.getAttribute('Id');
      final target = element.getAttribute('Target');
      if (id == null || target == null) continue;
      final normalized = target.startsWith('/')
          ? target.substring(1)
          : (target.startsWith('xl/') ? target : 'xl/$target');
      result[id] = normalized;
    }
    return result;
  }

  static List<String> _parseSharedStrings(Uint8List? bytes) {
    if (bytes == null) return const [];
    final doc = XmlDocument.parse(utf8.decode(bytes));
    final result = <String>[];
    for (final si in doc.descendants.whereType<XmlElement>()) {
      if (si.name.local != 'si') continue;
      final buffer = StringBuffer();
      for (final text in si.descendants.whereType<XmlElement>()) {
        if (text.name.local == 't') buffer.write(text.innerText);
      }
      result.add(buffer.toString());
    }
    return result;
  }

  static List<List<String>> _parseSheet(String xml, List<String> shared) {
    final doc = XmlDocument.parse(xml);
    final rowMap = <int, List<String>>{};
    var fallbackRow = 0;
    for (final row in doc.descendants.whereType<XmlElement>()) {
      if (row.name.local != 'row') continue;
      final rowNumber = int.tryParse(row.getAttribute('r') ?? '');
      final index = rowNumber == null ? fallbackRow : rowNumber - 1;
      fallbackRow = index + 1;

      final cells = <int, String>{};
      var fallbackColumn = 0;
      for (final cell in row.childElements) {
        if (cell.name.local != 'c') continue;
        final ref = cell.getAttribute('r');
        final column = ref == null ? fallbackColumn : _columnIndex(ref);
        fallbackColumn = column + 1;
        cells[column] = _cellText(cell, shared);
      }
      if (cells.isEmpty) {
        rowMap[index] = const [];
        continue;
      }
      final maxColumn = cells.keys.reduce((a, b) => a > b ? a : b);
      final values = List<String>.filled(maxColumn + 1, '');
      cells.forEach((column, value) {
        if (column >= 0 && column < values.length) values[column] = value;
      });
      rowMap[index] = values;
    }

    final rows = <List<String>>[];
    final indices = rowMap.keys.toList()..sort();
    for (final index in indices) {
      rows.add(rowMap[index]!);
    }
    return rows;
  }

  static String _cellText(XmlElement cell, List<String> shared) {
    final type = cell.getAttribute('t') ?? '';
    if (type == 'inlineStr') {
      final buffer = StringBuffer();
      for (final element in cell.descendants.whereType<XmlElement>()) {
        if (element.name.local == 't') buffer.write(element.innerText);
      }
      return buffer.toString().trim();
    }
    for (final value in cell.childElements) {
      if (value.name.local != 'v') continue;
      final raw = value.innerText.trim();
      if (type == 's') {
        final index = int.tryParse(raw);
        if (index != null && index >= 0 && index < shared.length) {
          return shared[index].trim();
        }
        return '';
      }
      return raw;
    }
    return '';
  }

  static int _columnIndex(String cellRef) {
    var result = 0;
    for (final code in cellRef.codeUnits) {
      if (code >= 65 && code <= 90) {
        result = result * 26 + (code - 64);
      } else {
        break;
      }
    }
    return result <= 0 ? 0 : result - 1;
  }
}
