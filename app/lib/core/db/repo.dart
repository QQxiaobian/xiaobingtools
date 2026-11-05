import '../db/app_database.dart';
import '../models/flaw.dart';
import '../models/line.dart';
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
}
