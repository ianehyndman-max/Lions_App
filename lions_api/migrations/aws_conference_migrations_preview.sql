-- Safe preview script for the conference AWS migration
-- This does NOT modify the database.
-- Run it with:
--   mysql -u <admin> -p <database_name> < lions_api/migrations/aws_conference_migrations_preview.sql

SELECT 'members.is_conference_member' AS check_name,
       IF(
         EXISTS(
           SELECT 1
           FROM INFORMATION_SCHEMA.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE()
             AND TABLE_NAME = 'members'
             AND COLUMN_NAME = 'is_conference_member'
         ),
         'exists',
         'missing'
       ) AS status;

SELECT 'conference_content table' AS check_name,
       IF(
         EXISTS(
           SELECT 1
           FROM INFORMATION_SCHEMA.TABLES
           WHERE TABLE_SCHEMA = DATABASE()
             AND TABLE_NAME = 'conference_content'
         ),
         'exists',
         'missing'
       ) AS status;

SELECT 'conference_ideas table' AS check_name,
       IF(
         EXISTS(
           SELECT 1
           FROM INFORMATION_SCHEMA.TABLES
           WHERE TABLE_SCHEMA = DATABASE()
             AND TABLE_NAME = 'conference_ideas'
         ),
         'exists',
         'missing'
       ) AS status;

SELECT 'conference_sections table' AS check_name,
       IF(
         EXISTS(
           SELECT 1
           FROM INFORMATION_SCHEMA.TABLES
           WHERE TABLE_SCHEMA = DATABASE()
             AND TABLE_NAME = 'conference_sections'
         ),
         'exists',
         'missing'
       ) AS status;

SELECT 'conference_section_attachments table' AS check_name,
       IF(
         EXISTS(
           SELECT 1
           FROM INFORMATION_SCHEMA.TABLES
           WHERE TABLE_SCHEMA = DATABASE()
             AND TABLE_NAME = 'conference_section_attachments'
         ),
         'exists',
         'missing'
       ) AS status;

SELECT 'conference_sections.status column' AS check_name,
       IF(
         EXISTS(
           SELECT 1
           FROM INFORMATION_SCHEMA.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE()
             AND TABLE_NAME = 'conference_sections'
             AND COLUMN_NAME = 'status'
         ),
         'exists',
         'missing'
       ) AS status;

SELECT 'conference_sections.archived_at column' AS check_name,
       IF(
         EXISTS(
           SELECT 1
           FROM INFORMATION_SCHEMA.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE()
             AND TABLE_NAME = 'conference_sections'
             AND COLUMN_NAME = 'archived_at'
         ),
         'exists',
         'missing'
       ) AS status;

SELECT 'conference_sections.parent_id column' AS check_name,
       IF(
         EXISTS(
           SELECT 1
           FROM INFORMATION_SCHEMA.COLUMNS
           WHERE TABLE_SCHEMA = DATABASE()
             AND TABLE_NAME = 'conference_sections'
             AND COLUMN_NAME = 'parent_id'
         ),
         'exists',
         'missing'
       ) AS status;

SELECT 'conference_sections idx_conference_sections_parent index' AS check_name,
       IF(
         EXISTS(
           SELECT 1
           FROM INFORMATION_SCHEMA.STATISTICS
           WHERE TABLE_SCHEMA = DATABASE()
             AND TABLE_NAME = 'conference_sections'
             AND INDEX_NAME = 'idx_conference_sections_parent'
         ),
         'exists',
         'missing'
       ) AS status;
