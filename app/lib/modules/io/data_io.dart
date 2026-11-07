import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/db/repo.dart';
import '../../core/models/flaw.dart';
import '../../core/models/line.dart';
import '../../core/models/tower.dart';
import 'xlsx_reader.dart';

class ImportResult {
  int linesAdded = 0;
  int linesUpdated = 0;
  int towersAdded = 0;
  int towersUpdated = 0;
  int skipped = 0;
  int filesImported = 0;
  final List<String> warnings = [];

  String get summary =>
      '${filesImported > 1 ? '共处理 $filesImported 个文件，' : ''}'
      '新增线路 $linesAdded 条，更新线路 $linesUpdated 条，'
      '新增杆塔 $towersAdded 基，更新杆塔 $towersUpdated 基，跳过 $skipped 条';
}

/// 台账 Excel 模板与导入导出、KML 导出、文件分享。
class DataIo {
  DataIo._();

  static const List<String> lineHeaders = [
    '线路名称',
    '电压等级',
    '运维班组',
    '起始塔号',
    '终止塔号',
    '备注',
  ];

  static const List<String> towerHeaders = [
    '线路名称',
    '杆塔号',
    '经度',
    '纬度',
    '高程',
    '塔型',
    '序号',
    '备注',
  ];

  static Future<Directory> exportsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'exports'));
    if (!dir.existsSync()) {
      dir.create(recursive: true);
    }
    return dir;
  }

  static String _stamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  /// 导出台账（线路 + 杆塔）。
  static Future<File> exportLedger() async {
    final lines = await Repo.lines();
    final towers = await Repo.towers();
    final excel = Excel.createExcel();
    final lineSheet = excel['线路台账'];
    final towerSheet = excel['杆塔台账'];
    excel.delete('Sheet1');

    _writeHeader(lineSheet, lineHeaders, [22, 12, 16, 12, 12, 28]);
    for (final line in lines) {
      lineSheet.appendRow([
        TextCellValue(line.name),
        TextCellValue(line.voltage),
        TextCellValue(line.team),
        TextCellValue(line.startTower),
        TextCellValue(line.endTower),
        TextCellValue(line.remark),
      ]);
    }

    _writeHeader(towerSheet, towerHeaders, [22, 12, 14, 14, 10, 14, 8, 24]);
    final lineNameById = {
      for (final line in lines)
        if (line.id != null) line.id!: line.name,
    };
    for (final tower in towers) {
      towerSheet.appendRow([
        TextCellValue(lineNameById[tower.lineId] ?? ''),
        TextCellValue(tower.towerNo),
        DoubleCellValue(tower.lng),
        DoubleCellValue(tower.lat),
        DoubleCellValue(tower.elevation),
        TextCellValue(tower.towerType),
        IntCellValue(tower.seq),
        TextCellValue(tower.remark),
      ]);
    }

    final file =
        File(p.join((await exportsDir()).path, '台账_${_stamp()}.xlsx'));
    await _saveExcel(excel, file);
    return file;
  }

  /// 导出空模板（含一行示例）。
  static Future<File> exportTemplate() async {
    final excel = Excel.createExcel();
    final lineSheet = excel['线路台账'];
    final towerSheet = excel['杆塔台账'];
    excel.delete('Sheet1');

    _writeHeader(lineSheet, lineHeaders, [22, 12, 16, 12, 12, 28]);
    lineSheet.appendRow([
      TextCellValue('示例线路'),
      TextCellValue('110kV'),
      TextCellValue('输电运维一班'),
      TextCellValue('N1'),
      TextCellValue('N30'),
      TextCellValue(''),
    ]);

    _writeHeader(towerSheet, towerHeaders, [22, 12, 14, 14, 10, 14, 8, 24]);
    towerSheet.appendRow([
      TextCellValue('示例线路'),
      TextCellValue('N1'),
      DoubleCellValue(113.264512),
      DoubleCellValue(23.129163),
      DoubleCellValue(36.5),
      TextCellValue('ZBC1'),
      IntCellValue(1),
      TextCellValue(''),
    ]);

    final file = File(p.join((await exportsDir()).path, '台账模板.xlsx'));
    await _saveExcel(excel, file);
    return file;
  }

  /// 选择 Excel 导入台账，按“线路名称 + 杆塔号”去重更新。
  static Future<ImportResult?> importLedger() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      dialogTitle: '选择台账 Excel',
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) {
      throw const FileSystemException('无法读取所选文件');
    }

    final excel = _decodeExcel(bytes);
    final importResult = ImportResult();

    // 兼容「杆塔信息 + 线路信息」两表格式（现场台账常用格式）
    final toolboxTower = excel.tables['杆塔信息'];
    final toolboxLine = excel.tables['线路信息'];
    if (toolboxTower != null || toolboxLine != null) {
      return _importToolboxFormat(
        toolboxTower,
        toolboxLine,
        picked.name,
      );
    }

    Sheet? lineTable = excel.tables['线路台账'];
    Sheet? towerTable = excel.tables['杆塔台账'];
    if (lineTable == null && towerTable == null) {
      final nonEmpty =
          excel.tables.values.where((sheet) => sheet.maxRows > 0).toList();
      if (nonEmpty.length == 1) {
        final header = _headerIndex(nonEmpty.single.rows.first);
        if (header.containsKey('线路名称') && header.containsKey('杆塔号')) {
          towerTable = nonEmpty.single;
        } else if (header.containsKey('线路名称')) {
          lineTable = nonEmpty.single;
        }
      }
    }
    if (lineTable == null && towerTable == null) {
      throw const FormatException('未找到“线路台账”或“杆塔台账”工作表');
    }

    if (lineTable != null) {
      final rows = lineTable.rows;
      if (rows.isNotEmpty) {
        final header = _headerIndex(rows.first);
        for (var i = 1; i < rows.length; i++) {
          final row = rows[i];
          final name = _cell(row, header['线路名称']);
          if (name.isEmpty) {
            importResult.skipped++;
            continue;
          }
          final data = Line(
            name: name,
            voltage: _cell(row, header['电压等级']),
            team: _cell(row, header['运维班组']),
            startTower: _cell(row, header['起始塔号']),
            endTower: _cell(row, header['终止塔号']),
            remark: _cell(row, header['备注']),
          );
          final existing = await Repo.lineByName(name);
          if (existing == null) {
            await Repo.insertLine(data);
            importResult.linesAdded++;
          } else {
            await Repo.updateLine(data.copyWith(id: existing.id));
            importResult.linesUpdated++;
          }
        }
      }
    }

    if (towerTable != null) {
      final rows = towerTable.rows;
      if (rows.isNotEmpty) {
        final header = _headerIndex(rows.first);
        for (var i = 1; i < rows.length; i++) {
          final row = rows[i];
          final lineName = _cell(row, header['线路名称']);
          final towerNo = _cell(row, header['杆塔号']);
          if (lineName.isEmpty || towerNo.isEmpty) {
            importResult.skipped++;
            continue;
          }
          final lng = _number(_cell(row, header['经度']));
          final lat = _number(_cell(row, header['纬度']));
          final lineId = await _ensureLineId(lineName);
          final tower = Tower(
            lineId: lineId,
            towerNo: towerNo,
            lng: lng,
            lat: lat,
            elevation: _number(_cell(row, header['高程'])),
            towerType: _cell(row, header['塔型']),
            seq: _number(_cell(row, header['序号'])).toInt(),
            remark: _cell(row, header['备注']),
          );
          final existingTowers = await Repo.towers(lineId);
          final matched = existingTowers.where((t) => t.towerNo == towerNo);
          if (matched.isEmpty) {
            await Repo.insertTower(tower);
            importResult.towersAdded++;
          } else {
            await Repo.updateTower(tower.copyWith(id: matched.first.id));
            importResult.towersUpdated++;
          }
          if (lng == 0 && lat == 0) {
            importResult.warnings.add('杆塔 $towerNo 缺少有效经纬度');
          }
        }
      }
    }

    return importResult;
  }

  /// 兼容「杆塔信息」「线路信息」两表格式的台账导入。
  static Future<ImportResult> _importToolboxFormat(
    Sheet? towerSheet,
    Sheet? lineSheet,
    String fileName,
  ) async {
    final result = ImportResult();

    final info = <String, String>{};
    if (lineSheet != null) {
      for (final row in lineSheet.rows) {
        final key = row.isEmpty
            ? ''
            : _cellText(row.first).trim().replaceAll(' ', '').replaceAll('\u3000', '');
        if (key.isEmpty || row.length < 2) continue;
        final value = _cellText(row[1]).trim();
        if (value.isNotEmpty) info[key] = value;
      }
    }

    final lineName = info['线路名称']?.isNotEmpty == true
        ? info['线路名称']!
        : p.basenameWithoutExtension(fileName);
    if (lineName.isEmpty) {
      throw const FormatException('线路信息表中未找到线路名称');
    }

    final line = Line(
      name: lineName,
      voltage: info['电压等级'] ?? '',
      team: info['资产单位'] ?? '',
      startTower: info['线路起点名称'] ?? '',
      endTower: info['线路终点名称'] ?? '',
      remark: info['备注'] ?? '',
    );
    final existingLine = await Repo.lineByName(lineName);
    final lineId = existingLine?.id ?? await Repo.insertLine(line);
    if (existingLine == null) {
      result.linesAdded++;
    } else {
      await Repo.updateLine(line.copyWith(id: existingLine.id));
      result.linesUpdated++;
    }

    if (towerSheet != null) {
      var headerRow = -1;
      var header = <String, int>{};
      for (var i = 0; i < towerSheet.rows.length; i++) {
        final candidate = _headerIndex(towerSheet.rows[i]);
        if (candidate.containsKey('杆塔编号') ||
            candidate.containsKey('杆塔号')) {
          headerRow = i;
          header = candidate;
          break;
        }
      }
      if (headerRow < 0) {
        result.warnings.add('「杆塔信息」中未找到“杆塔编号”表头');
      } else {
        final existingTowers = await Repo.towers(lineId);
        var autoSeq = 0;
        for (var i = headerRow + 1; i < towerSheet.rows.length; i++) {
          final row = towerSheet.rows[i];
          final towerNo = _cell(row, header['杆塔编号'] ?? header['杆塔号']);
          if (towerNo.isEmpty) {
            result.skipped++;
            continue;
          }
          autoSeq++;
          final lng = _number(_cell(row, header['经度']));
          final lat = _number(_cell(row, header['纬度']));
          final seq = _number(_cell(row, header['序号'])).toInt();
          final tower = Tower(
            lineId: lineId,
            towerNo: towerNo,
            lng: lng,
            lat: lat,
            elevation: _number(
              _pick(row, header, const ['塔基海拔', '塔顶海拔', '高程']),
            ),
            towerType: _pick(row, header, const ['杆塔型号', '塔型', '杆塔种类']),
            seq: seq == 0 ? autoSeq : seq,
            remark: _cell(row, header['备注']),
          );
          final matched = existingTowers.where((t) => t.towerNo == towerNo);
          if (matched.isEmpty) {
            await Repo.insertTower(tower);
            result.towersAdded++;
          } else {
            await Repo.updateTower(tower.copyWith(id: matched.first.id));
            result.towersUpdated++;
          }
          if (lng == 0 && lat == 0) {
            result.warnings.add('杆塔 $towerNo 缺少有效经纬度');
          }
        }
      }
    }

    return result;
  }

  /// 导出缺陷清单（含照片文件名）。
  static Future<File> exportFlaws(List<Flaw> flaws) async {
    final excel = Excel.createExcel();
    final sheet = excel['缺陷记录'];
    excel.delete('Sheet1');
    _writeHeader(
      sheet,
      ['线路名称', '杆塔号', '部位', '等级', '缺陷描述', '照片文件', '录入时间'],
      [22, 12, 14, 8, 40, 30, 20],
    );
    for (final flaw in flaws) {
      sheet.appendRow([
        TextCellValue(flaw.lineName),
        TextCellValue(flaw.towerNo),
        TextCellValue(flaw.part),
        TextCellValue(flaw.level),
        TextCellValue(flaw.description),
        TextCellValue(
          flaw.photoPath.isEmpty ? '' : p.basename(flaw.photoPath),
        ),
        TextCellValue(flaw.createdAt),
      ]);
    }
    final file =
        File(p.join((await exportsDir()).path, '缺陷记录_${_stamp()}.xlsx'));
    await _saveExcel(excel, file);
    return file;
  }

  /// 导出线路 KML（线路折线 + 杆塔点）。
  static Future<File> exportKml(Line line, List<Tower> towers) async {
    final sorted = [...towers]..sort((a, b) => a.seq.compareTo(b.seq));
    final points = sorted.where((t) => t.hasCoordinate).toList();
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<kml xmlns="http://www.opengis.net/kml/2.2">')
      ..writeln('<Document>')
      ..writeln('<name>${_xml(line.name)}</name>');
    if (points.length > 1) {
      buffer
        ..writeln('<Placemark>')
        ..writeln('<name>${_xml(line.name)}</name>')
        ..writeln('<LineString><tessellate>1</tessellate><coordinates>');
      for (final tower in points) {
        buffer.writeln('${tower.lng},${tower.lat},0');
      }
      buffer
        ..writeln('</coordinates></LineString>')
        ..writeln('</Placemark>');
    }
    for (final tower in points) {
      buffer
        ..writeln('<Placemark>')
        ..writeln('<name>${_xml(tower.towerNo)}</name>')
        ..writeln(
          '<Point><coordinates>${tower.lng},${tower.lat},0</coordinates></Point>',
        )
        ..writeln('</Placemark>');
    }
    buffer
      ..writeln('</Document>')
      ..writeln('</kml>');
    final file = File(
      p.join(
        (await exportsDir()).path,
        '${_safeName(line.name)}_${_stamp()}.kml',
      ),
    );
    await file.writeAsString(buffer.toString());
    return file;
  }

  static Future<void> shareFile(File file, {String? text}) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: text),
    );
  }

  static void _writeHeader(
    Sheet sheet,
    List<String> headers,
    List<double> widths,
  ) {
    sheet.appendRow(headers.map(TextCellValue.new).toList());
    for (var i = 0; i < widths.length; i++) {
      sheet.setColumnWidth(i, widths[i]);
    }
  }

  /// excel 包遇到不规范的自定义数字格式会抛异常，此时用最小读取器兜底重建工作簿。
  static Excel _decodeExcel(Uint8List bytes) {
    try {
      return Excel.decodeBytes(bytes);
    } catch (_) {
      final sheets = XlsxReader.read(bytes);
      if (sheets.isEmpty) rethrow;
      final excel = Excel.createExcel();
      final defaultName = excel.tables.keys.first;
      for (final sheet in sheets) {
        final target = excel[sheet.name];
        for (final row in sheet.rows) {
          target.appendRow(
            row.map<CellValue>((value) => TextCellValue(value)).toList(),
          );
        }
      }
      if (!sheets.any((sheet) => sheet.name == defaultName)) {
        excel.delete(defaultName);
      }
      return excel;
    }
  }

  static Future<void> _saveExcel(Excel excel, File file) async {
    final bytes = excel.save();
    if (bytes == null) {
      throw const FileSystemException('生成 Excel 失败');
    }
    await file.writeAsBytes(bytes, flush: true);
  }

  static Map<String, int> _headerIndex(List<Data?> row) {
    final map = <String, int>{};
    for (var i = 0; i < row.length; i++) {
      final key = _cellText(row[i])
          .trim()
          .replaceAll(' ', '')
          .replaceAll('\u3000', '');
      if (key.isNotEmpty) map[key] = i;
    }
    return map;
  }

  /// 依次尝试多个候选项，返回第一个非空单元格的文本。
  static String _pick(
    List<Data?> row,
    Map<String, int> header,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = _cell(row, header[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String _cell(List<Data?> row, int? index) {
    if (index == null || index >= row.length) return '';
    return _cellText(row[index]).trim();
  }

  static String _cellText(Data? data) {
    final value = data?.value;
    if (value == null) return '';
    if (value is TextCellValue) return value.value.text ?? '';
    if (value is IntCellValue) return value.value.toString();
    if (value is DoubleCellValue) return value.value.toString();
    if (value is BoolCellValue) return value.value.toString();
    if (value is FormulaCellValue) return value.formula;
    return value.toString();
  }

  static double _number(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(cleaned) ?? 0;
  }

  static Future<int> _ensureLineId(String name) async {
    final existing = await Repo.lineByName(name);
    if (existing?.id != null) return existing!.id!;
    return Repo.insertLine(Line(name: name));
  }

  static String _xml(String raw) => raw
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _safeName(String raw) =>
      raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}
