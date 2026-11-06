import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'destination.dart';

class Catalog {
  final Database db;
  Catalog._(this.db);
  static Future<Catalog> open(
    Destination destination, {
    bool readOnly = false,
  }) async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      destination.path('_metadata/catalog.sqlite'),
      options: OpenDatabaseOptions(
        readOnly: readOnly,
        version: 1,
        onConfigure: (db) async {
          if (!readOnly) {
            await db.execute('PRAGMA journal_mode=DELETE');
            await db.execute('PRAGMA synchronous=FULL');
          }
        },
        onCreate: (db, _) async {
          for (final table in [
            'files',
            'versions',
            'runs',
            'sources',
            'pending',
          ]) {
            await db.execute(
              'CREATE TABLE $table (key TEXT PRIMARY KEY, data TEXT NOT NULL)',
            );
          }
          await db.execute(
            'CREATE TABLE membership (source TEXT, file TEXT, state TEXT NOT NULL, PRIMARY KEY(source,file))',
          );
        },
      ),
    );
    return Catalog._(db);
  }

  Future<void> put(String table, String key, Map<String, dynamic> data) =>
      db.insert(table, {
        'key': key,
        'data': jsonEncode(data),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<Map<String, dynamic>?> get(String table, String key) async {
    final rows = await db.query(table, where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty
        ? null
        : jsonDecode(rows.single['data'] as String) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> all(String table) async =>
      (await db.query(table))
          .map(
            (row) => jsonDecode(row['data'] as String) as Map<String, dynamic>,
          )
          .toList();
  Future<void> remove(String table, String key) =>
      db.delete(table, where: 'key = ?', whereArgs: [key]);
  Future<void> member(String source, String file, String state) => db.insert(
    'membership',
    {'source': source, 'file': file, 'state': state},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  Future<void> completeScan(String source, Set<String> seen) async {
    await db.transaction((txn) async {
      final previous = await txn.query(
        'membership',
        where: 'source = ?',
        whereArgs: [source],
      );
      for (final row in previous) {
        if (!seen.contains(row['file'])) {
          await txn.update(
            'membership',
            {'state': 'absent: deleted, moved out of scope, or inaccessible'},
            where: 'source = ? AND file = ?',
            whereArgs: [source, row['file']],
          );
        }
      }
    });
  }

  Future<List<Map<String, Object?>>> memberships(String key) =>
      db.query('membership', where: 'file = ?', whereArgs: [key]);
  Future<void> close() => db.close();
}
