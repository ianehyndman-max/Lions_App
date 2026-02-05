// Run this script to add email fields to lions_club table
// dart run lions_api/bin/migrate_add_email_fields.dart

import 'dart:io';
import 'package:mysql_client/mysql_client.dart';

// Same config as your lions_api.dart
String _envOr(String key, String fallback) => Platform.environment[key] ?? fallback;

// TEMPORARILY USING LOCALHOST - change back to AWS RDS for production
final _dbHost = _envOr('DB_HOST', 'localhost');
// final _dbHost = _envOr('DB_HOST', 'lions-club-db.c12ge624w2tu.ap-southeast-2.rds.amazonaws.com');
final _dbPort = int.tryParse(Platform.environment['DB_PORT'] ?? '') ?? 3306;
final _dbUser = _envOr('DB_USER', 'root');
// final _dbUser = _envOr('DB_USER', 'admin');
final _dbPass = _envOr('DB_PASS', 'IanMySql1*.*');
// final _dbPass = _envOr('DB_PASS', 'ML4231LionsApp!');
final _dbName = _envOr('DB_NAME', 'lions');

void main() async {
  print('🔄 Connecting to database...');
  
  final conn = await MySQLConnection.createConnection(
    host: _dbHost,
    port: _dbPort,
    userName: _dbUser,
    password: _dbPass,
    databaseName: _dbName,
  );
  
  try {
    await conn.connect();
    print('✅ Connected to MySQL at $_dbHost:$_dbPort ($_dbName)');
    
    print('\n🔄 Adding email fields to lions_club table...');
    
    await conn.execute('''
      ALTER TABLE lions_club 
      ADD COLUMN email_subdomain VARCHAR(100) DEFAULT NULL COMMENT 'Email subdomain (e.g., "mudgeeraba" for noreply@mudgeeraba.thelionsapp.com)',
      ADD COLUMN reply_to_email VARCHAR(255) DEFAULT NULL COMMENT 'Club''s actual email address for replies',
      ADD COLUMN from_name VARCHAR(255) DEFAULT NULL COMMENT 'Display name for email sender (e.g., "Mudgeeraba Lions Club")'
    ''');
    
    print('✅ Successfully added email fields to lions_club table!');
    print('\n📝 New fields added:');
    print('   - email_subdomain: Subdomain for emails (e.g., "mudgeeraba")');
    print('   - reply_to_email: Club\'s actual email address');
    print('   - from_name: Display name for sender');
    
    print('\n💡 Next steps:');
    print('   1. Update club records with email settings via the app');
    print('   2. Configure your domain (thelionsapp.com) with email service');
    print('   3. Update SMTP credentials in environment variables');
    
  } catch (e) {
    if (e.toString().contains('Duplicate column name')) {
      print('ℹ️  Email fields already exist in lions_club table - skipping migration');
    } else {
      print('❌ Error: $e');
      rethrow;
    }
  } finally {
    await conn.close();
    print('\n🔌 Database connection closed');
  }
}
