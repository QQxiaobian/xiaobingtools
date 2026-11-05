import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _database;

  Future<Database> get database async {
    final cached = _database;
    if (cached != null) return cached;
    final db = await _open();
    _database = db;
    return db;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'xianlu_toolbox.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE lines (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            voltage TEXT NOT NULL DEFAULT '',
            team TEXT NOT NULL DEFAULT '',
            start_tower TEXT NOT NULL DEFAULT '',
            end_tower TEXT NOT NULL DEFAULT '',
            remark TEXT NOT NULL DEFAULT ''
          )
        ''');
        await db.execute('''
          CREATE TABLE towers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            line_id INTEGER NOT NULL,
            tower_no TEXT NOT NULL,
            lng REAL NOT NULL DEFAULT 0,
            lat REAL NOT NULL DEFAULT 0,
            elevation REAL NOT NULL DEFAULT 0,
            tower_type TEXT NOT NULL DEFAULT '',
            seq INTEGER NOT NULL DEFAULT 0,
            remark TEXT NOT NULL DEFAULT ''
          )
        ''');
        await db.execute('CREATE INDEX idx_towers_line ON towers(line_id)');
        await db.execute('''
          CREATE TABLE flaws (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            line_id INTEGER NOT NULL,
            line_name TEXT NOT NULL DEFAULT '',
            tower_id INTEGER,
            tower_no TEXT NOT NULL DEFAULT '',
            part TEXT NOT NULL DEFAULT '',
            level TEXT NOT NULL DEFAULT '一般',
            description TEXT NOT NULL DEFAULT '',
            photo_path TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL DEFAULT ''
          )
        ''');
        await db.execute('CREATE INDEX idx_flaws_line ON flaws(line_id)');
      },
    );
  }
}
