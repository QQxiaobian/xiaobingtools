import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../core/db/repo.dart';
import '../../core/models/line.dart';
import '../../core/models/tower.dart';
import 'data_io.dart';

/// KML 导入：Point 视为杆塔，LineString 仅用于确定线路名称与走向。
class KmlIo {
  KmlIo._();

  static Future<ImportResult?> importKml() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['kml', 'xml'],
      dialogTitle: '选择 KML 文件',
    );
    if (picked == null) return null;

    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) throw const FileSystemException('KML 文件为空');
    final content = utf8.decode(bytes, allowMalformed: true);

    late final XmlDocument doc;
    try {
      doc = XmlDocument.parse(content);
    } on XmlParserException catch (e) {
      throw FormatException('KML 解析失败：${e.message}');
    }

    final placemarks = doc.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'Placemark')
        .toList();

    var lineName = '';
    var hasLineString = false;
    final points = <_KmlPoint>[];
    final lineVertices = <_KmlCoord>[];
    for (final placemark in placemarks) {
      final name = _textOf(placemark, 'name');
      final lineString = _elementOf(placemark, 'LineString');
      if (lineString != null) {
        hasLineString = true;
        if (lineName.isEmpty && name.isNotEmpty) lineName = name;
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
      final label = name.isEmpty ? 'T${points.length + 1}' : name;
      points.add(_KmlPoint(label, coords.first.lat, coords.first.lng, coords.first.alt));
    }

    // 只有折线、没有独立点位时，按折线顶点生成杆塔
    if (points.isEmpty && lineVertices.isNotEmpty) {
      for (var i = 0; i < lineVertices.length; i++) {
        final vertex = lineVertices[i];
        points.add(_KmlPoint('T${i + 1}', vertex.lat, vertex.lng, vertex.alt));
      }
    }

    if (points.isEmpty) {
      throw const FormatException('KML 中没有找到杆塔点位或线路折线');
    }
    if (lineName.isEmpty) lineName = p.basenameWithoutExtension(picked.name);

    final result = ImportResult();
    final existingLine = await Repo.lineByName(lineName);
    final lineId = existingLine?.id ?? await Repo.insertLine(Line(name: lineName));
    if (existingLine == null) {
      result.linesAdded++;
    } else {
      result.linesUpdated++;
    }

    final existingTowers = await Repo.towers(lineId);
    var seq = 0;
    for (final point in points) {
      seq++;
      final tower = Tower(
        lineId: lineId,
        towerNo: point.name,
        lng: point.lng,
        lat: point.lat,
        elevation: point.alt,
        seq: seq,
      );
      final matched = existingTowers.where((t) => t.towerNo == point.name);
      if (matched.isEmpty) {
        await Repo.insertTower(tower);
        result.towersAdded++;
      } else {
        await Repo.updateTower(tower.copyWith(id: matched.first.id));
        result.towersUpdated++;
      }
    }

    if (!hasLineString) {
      result.warnings.add('KML 未包含 LineString，仅导入了杆塔点位');
    } else if (points.every((point) => point.name.startsWith('T'))) {
      result.warnings.add('KML 仅有折线，已按折线顶点生成杆塔编号 T1 起，请按实际塔号修改');
    }
    return result;
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
