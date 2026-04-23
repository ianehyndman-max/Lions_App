import 'dart:io';
import 'package:mysql_client/mysql_client.dart';

String _envOr(String key, String fallback) => Platform.environment[key] ?? fallback;

final _dbHost = _envOr('DB_HOST', '127.0.0.1');
final _dbPort = int.tryParse(Platform.environment['DB_PORT'] ?? '') ?? 3306;
final _dbUser = _envOr('DB_USER', 'root');
final _dbPass = _envOr('DB_PASS', '');
final _dbName = _envOr('DB_NAME', 'lions');

Future<void> main() async {
  stdout.writeln('Connecting to database...');
  final conn = await MySQLConnection.createConnection(
    host: _dbHost,
    port: _dbPort,
    userName: _dbUser,
    password: _dbPass,
    databaseName: _dbName,
  );

  try {
    await conn.connect();
    stdout.writeln('Connected to $_dbHost:$_dbPort ($_dbName)');

    try {
      await conn.execute(
        'ALTER TABLE event_volunteers ADD COLUMN meal_choice VARCHAR(100) DEFAULT NULL',
      );
      stdout.writeln('Added event_volunteers.meal_choice');
    } catch (e) {
      if (e.toString().contains('Duplicate column name')) {
        stdout.writeln('event_volunteers.meal_choice already exists');
      } else {
        rethrow;
      }
    }

    await conn.execute('''
      CREATE TABLE IF NOT EXISTS dinner_meal_options (
        id INT AUTO_INCREMENT PRIMARY KEY,
        option_name VARCHAR(100) NOT NULL,
        sort_order INT NOT NULL DEFAULT 999,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
      )
    ''');
    stdout.writeln('Ensured dinner_meal_options table exists');
  } finally {
    await conn.close();
    stdout.writeln('Database connection closed');
  }
}
