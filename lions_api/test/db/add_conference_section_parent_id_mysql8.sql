-- Test-database version of migrations/add_conference_section_parent_id.sql.
--
-- The original migration uses `ADD COLUMN IF NOT EXISTS`, which is
-- MariaDB-only syntax and fails on MySQL 8. This version uses the same
-- INFORMATION_SCHEMA + prepared-statement pattern as
-- add_conference_section_status_fields.sql so it runs on MySQL 8.
-- (In production the API adds this column itself at startup via
-- _ensureConferenceSectionParentColumn in bin/lions_api.dart.)

SET @add_parent_id_column = (
  SELECT IF(
    EXISTS(
      SELECT 1
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'conference_sections'
        AND COLUMN_NAME = 'parent_id'
    ),
    'SELECT 1',
    'ALTER TABLE conference_sections ADD COLUMN parent_id BIGINT NULL DEFAULT NULL AFTER sort_order'
  )
);

PREPARE stmt_add_parent_id FROM @add_parent_id_column;
EXECUTE stmt_add_parent_id;
DEALLOCATE PREPARE stmt_add_parent_id;

SET @add_parent_index = (
  SELECT IF(
    EXISTS(
      SELECT 1
      FROM INFORMATION_SCHEMA.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'conference_sections'
        AND INDEX_NAME = 'idx_conference_sections_parent'
    ),
    'SELECT 1',
    'ALTER TABLE conference_sections ADD INDEX idx_conference_sections_parent (parent_id, sort_order)'
  )
);

PREPARE stmt_add_parent_index FROM @add_parent_index;
EXECUTE stmt_add_parent_index;
DEALLOCATE PREPARE stmt_add_parent_index;
