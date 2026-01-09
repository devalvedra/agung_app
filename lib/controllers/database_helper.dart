import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'delivery_tracking.db');
    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tbtracking (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        inv TEXT NOT NULL,
        image_path TEXT NOT NULL,
        drop_point_code TEXT NOT NULL,
        lat REAL,
        lng REAL,
        timestamps TEXT NOT NULL
      )
    ''');
  }

  /// Insert a new tracking record
  Future<int> insertTracking({
    required String inv,
    required String imagePath,
    required String dropPointCode,
    double? lat,
    double? lng,
  }) async {
    final db = await database;
    return await db.insert('tbtracking', {
      'inv': inv,
      'image_path': imagePath,
      'drop_point_code': dropPointCode,
      'lat': lat,
      'lng': lng,
      'timestamps': DateTime.now().toIso8601String(),
    });
  }

  /// Get all tracking records
  Future<List<Map<String, dynamic>>> getAllTrackings() async {
    final db = await database;
    return await db.query('tbtracking', orderBy: 'timestamps DESC');
  }

  /// Get tracking records by drop point code
  Future<List<Map<String, dynamic>>> getTrackingsByDropPoint(
    String dropPointCode,
  ) async {
    final db = await database;
    return await db.query(
      'tbtracking',
      where: 'drop_point_code = ?',
      whereArgs: [dropPointCode],
      orderBy: 'timestamps DESC',
    );
  }

  /// Get tracking record by id
  Future<Map<String, dynamic>?> getTrackingById(int id) async {
    final db = await database;
    final results = await db.query(
      'tbtracking',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Delete a tracking record
  Future<int> deleteTracking(int id) async {
    final db = await database;
    return await db.delete('tbtracking', where: 'id = ?', whereArgs: [id]);
  }

  /// Close the database
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
