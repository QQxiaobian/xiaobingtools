import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../core/db/repo.dart';
import '../../core/models/line.dart';
import '../../core/models/tower.dart';
import 'data_io.dart';

/// KML 批量导入：Point 视为杆塔，LineString 仅用于确定走向。
///
/// 每个 KML 文件导入为一条线路，线路名称与电压等级优先从文件名识别，
/// 例如「220kV白树牵线.kml」→ 电压 220、名称「白树牵线」。
class KmlIo {
  KmlIo._();

  static Future<ImportResult?> importKml() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['kml', 'xml'],
      dialogTitle: '选择 KML 文件（可多选）',
    );
    if (picked.isEmpty) return null;

    final result = ImportResult();
    final failures = <String>[];
    for (final file in picked) {
      try {
        await _importFile(file, result);
        result.filesImported++;
      } catch (e) {
        failures.add('${file.name}：$e');
        result.skipped++;
      }
    }

    if (result.filesImported == 0) {
      throw FormatException('KML 导入失败\n${failures.join('\n')}');
    }
    result.warnings.insertAll(0, failures);
    return result;
  }

  static Future<void> _importFile(PlatformFile file, ImportResult result) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw const FileSystemException('文件为空');

    final parsed = _parseKml(utf8.decode(bytes, allowMalformed: true));

    // 文件名优先；识别不到时退回 KML 内的名称。
    final fromName = parseFileName(file.name);
    var lineName = fromName.name;
    if (lineName.isEmpty || _isGenericName(lineName)) {
      lineName = parsed.name.isNotEmpty ? parsed.name : fromName.name;
    }
    if (lineName.isEmpty) lineName = p.basenameWithoutExtension(file.name);
    final voltage = fromName.voltage;

    final existingLine = await Repo.lineByName(lineName);
    final int lineId;
    if (existingLine == null) {
      lineId = await Repo.insertLine(
        Line(
          name: lineName,
          voltage: voltage,
          remark: voltage.isEmpty ? '' : '由 KML 导入',
        ),
      );
      result.linesAdded++;
    } else {
      lineId = existingLine.id!;
      // 文件名带电压等级且与原台账不同则同步，方便批量补全台账。
      if (voltage.isNotEmpty && existingLine.voltage != voltage) {
        await Repo.updateLine(existingLine.copyWith(voltage: voltage));
      }
      result.linesUpdated++;
    }

    final existingTowers = await Repo.towers(lineId);
    final byTowerNo = {
      for (final tower in existingTowers) tower.towerNo: tower,
    };
    var seq = 0;
    for (final point in parsed.points) {
      seq++;
      final tower = Tower(
        lineId: lineId,
        towerNo: point.name,
        lng: point.lng,
        lat: point.lat,
        elevation: point.alt,
        seq: seq,
      );
      final matched = byTowerNo[point.name];
      if (matched == null) {
        final id = await Repo.insertTower(tower);
        byTowerNo[point.name] = tower.copyWith(id: id);
        result.towersAdded++;
      } else {
        await Repo.updateTower(tower.copyWith(id: matched.id));
        result.towersUpdated++;
      }
    }

    if (!parsed.hasLineString) {
      result.warnings.add('${file.name}：未包含 LineString，仅导入了杆塔点位');
    } else if (parsed.points.every((point) => point.name.startsWith('T'))) {
      result.warnings.add(
        '${file.name}：仅有折线，已按折线顶点生成杆塔编号 T1 起，请按实际塔号修改',
      );
    }
    if (voltage.isEmpty) {
      result.warnings.add('${file.name}：文件名中未识别到电压等级，已留空（可后续在台账中补充）');
    }
  }

  static bool _isGenericName(String name) {
    final lower = name.toLowerCase();
    return lower == 'doc' || lower == 'untitled' || lower == '无标题' || name == 'document';
  }

  /// 从文件名识别线路名称与电压等级。
  ///
  /// 支持「220kV白树牵线」「白树牵线_220kV」「35千伏XX线」等写法，
  /// 并会自动去掉导出时附加的 `_20260101_120000` 时间戳。
  static ({String name, String voltage}) parseFileName(String fileName) {
    var base = p.basenameWithoutExtension(fileName).trim();
    base = base.replaceAll(RegExp(r'[_\-\s]?\d{8}[_\-\s]\d{6}$'), '');

    var voltage = '';
    final match = RegExp(r'(\d+(?:\.\d+)?)\s*(?:kv|千伏)', caseSensitive: false)
        .firstMatch(base);
    if (match != null) {
      voltage = match.group(1)!;
      base = base.replaceRange(match.start, match.end, '');
      // 去掉单位后常见的尾随分隔符。
      base = base.replaceAll(RegExp(r'^[\s_\-—－·.]+|[\s_\-—－·.]+$'), '');
      base = base.replaceAll(RegExp(r'[\s_\-—－·.]{2,}'), ' ');
    }
    final name = base.trim();
    if (name.isEmpty) {
      return (name: p.basenameWithoutExtension(fileName).trim(), voltage: voltage);
    }
    return (name: name, voltage: voltage);
  }

  static _KmlContent _parseKml(String content) {
    late final XmlDocument doc;
    try {
      doc = XmlDocument.parse(content);
    } on XmlParserException catch (e) {
      throw FormatException('解析失败：${e.message}');
    }

    final placemarks = doc.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'Placemark')
        .toList();

    var name = '';
    var hasLineString = false;
    final points = <_KmlPoint>[];
    final lineVertices = <_KmlCoord>[];
    for (final placemark in placemarks) {
      final placemarkName = _textOf(placemark, 'name');
      final lineString = _elementOf(placemark, 'LineString');
      if (lineString != null) {
        hasLineString = true;
        if (name.isEmpty && placemarkName.isNotEmpty) name = placemarkName;
        if (lineVertices.isEmpty) {
          lineVertices.addAll(
            _parseCoordinates(_textOf(lineString, 'coordinates')),
          );
        }
      }

      final point = _elementOf(placemark, 'Point');
      if (point == null) continue;
      final coords = _parseCoordinates(_textOf(point, 'coordinates'));
      if (coords.isEmpty) continue;
      final label = placemarkName.isEmpty ? 'T${points.length + 1}' : placemarkName;
      points.add(
        _KmlPoint(label, coords.first.lat, coords.first.lng, coords.first.alt),
      );
    }

    // 只有折线、没有独立点位时，按折线顶点生成杆塔
    if (points.isEmpty && lineVertices.isNotEmpty) {
      for (var i = 0; i < lineVertices.length; i++) {
        final vertex = lineVertices[i];
        points.add(_KmlPoint('T${i + 1}', vertex.lat, vertex.lng, vertex.alt));
      }
    }

    if (points.isEmpty) {
      throw const FormatException('没有找到杆塔点位或线路折线');
    }
    return _KmlContent(name, points, hasLineString);
  }

  static XmlElement? _elementOf(XmlElement parent, String localName) {
    for (final element in parent.descendants.whereType<XmlElement>()) {
      if (element.name.local == localName) return element;
    }
    return null;
  }

  static String _textOf(XmlElement parent, String localName) {
    final element = _elementOf(parent, localName);
    return element?.innerText.trim() ?? '';
  }

  static List<_KmlCoord> _parseCoordinates(String raw) {
    final result = <_KmlCoord>[];
    for (final token in raw.split(RegExp(r'\s+'))) {
      final parts = token.split(',');
      if (parts.length < 2) continue;
      final lng = double.tryParse(parts[0].trim());
      final lat = double.tryParse(parts[1].trim());
      if (lng == null || lat == null) continue;
      final alt = parts.length > 2 ? double.tryParse(parts[2].trim()) ?? 0 : 0.0;
      result.add(_KmlCoord(lat, lng, alt));
    }
    return result;
  }
}

class _KmlContent {
  const _KmlContent(this.name, this.points, this.hasLineString);

  final String name;
  final List<_KmlPoint> points;
  final bool hasLineString;
}

class _KmlPoint {
  const _KmlPoint(this.name, this.lat, this.lng, this.alt);

  final String name;
  final double lat;
  final double lng;
  final double alt;
}

class _KmlCoord {
  const _KmlCoord(this.lat, this.lng, this.alt);

  final double lat;
  final double lng;
  final double alt;
}
