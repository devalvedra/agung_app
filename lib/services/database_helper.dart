import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Helper class to manage local SQLite database
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  /// Get database instance
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('agung_app.db');
    return _database!;
  }

  /// Initialize database
  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  /// Create database tables
  Future<void> _createDB(Database db, int version) async {
    // Create settings table
    await db.execute('''
      CREATE TABLE settings(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        key TEXT NOT NULL UNIQUE,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  /// Close database
  Future<void> close() async {
    final db = await instance.database;
    await db.close();
  }

  /// Insert or update a setting
  Future<int> insertOrUpdateSetting(String key, String value) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    return await db.insert('settings', {
      'key': key,
      'value': value,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Get a setting value by key
  Future<String?> getSetting(String key) async {
    final db = await database;
    final results = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (results.isNotEmpty) {
      return results.first['value'] as String;
    }
    return null;
  }

  /// Delete a setting
  Future<int> deleteSetting(String key) async {
    final db = await database;
    return await db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }

  /// Get all settings
  Future<Map<String, String>> getAllSettings() async {
    final db = await database;
    final results = await db.query('settings');

    return Map.fromEntries(
      results.map(
        (row) => MapEntry(row['key'] as String, row['value'] as String),
      ),
    );
  }
}
