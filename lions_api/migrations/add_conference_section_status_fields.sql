SET @add_status_column = (
  SELECT IF(
    EXISTS(
      SELECT 1
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'conference_sections'
        AND COLUMN_NAME = 'status'
    ),
    'SELECT 1',
    "ALTER TABLE conference_sections ADD COLUMN status ENUM('draft','in_review','approved','archived') NOT NULL DEFAULT 'draft' AFTER sort_order"
  )
);

PREPARE stmt_add_status_column FROM @add_status_column;
EXECUTE stmt_add_status_column;
DEALLOCATE PREPARE stmt_add_status_column;

SET @add_archived_at_column = (
  SELECT IF(
    EXISTS(
      SELECT 1
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'conference_sections'
        AND COLUMN_NAME = 'archived_at'
    ),
    'SELECT 1',
    'ALTER TABLE conference_sections ADD COLUMN archived_at TIMESTAMP NULL DEFAULT NULL AFTER status'
  )
);

PREPARE stmt_add_archived_at_column FROM @add_archived_at_column;
EXECUTE stmt_add_archived_at_column;
DEALLOCATE PREPARE stmt_add_archived_at_column;

SET @add_archived_by_column = (
  SELECT IF(
    EXISTS(
      SELECT 1
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'conference_sections'
        AND COLUMN_NAME = 'archived_by_member_id'
    ),
    'SELECT 1',
    'ALTER TABLE conference_sections ADD COLUMN archived_by_member_id BIGINT NULL DEFAULT NULL AFTER archived_at'
  )
);

PREPARE stmt_add_archived_by_column FROM @add_archived_by_column;
EXECUTE stmt_add_archived_by_column;
DEALLOCATE PREPARE stmt_add_archived_by_column;

SET @add_updated_by_column = (
  SELECT IF(
    EXISTS(
      SELECT 1
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'conference_sections'
        AND COLUMN_NAME = 'updated_by_member_id'
    ),
    'SELECT 1',
    'ALTER TABLE conference_sections ADD COLUMN updated_by_member_id BIGINT NULL DEFAULT NULL AFTER created_by_member_id'
  )
);

PREPARE stmt_add_updated_by_column FROM @add_updated_by_column;
EXECUTE stmt_add_updated_by_column;
DEALLOCATE PREPARE stmt_add_updated_by_column;

SET @seed_status_for_existing = (
  SELECT IF(
    EXISTS(
      SELECT 1
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'conference_sections'
        AND COLUMN_NAME = 'status'
    ),
    "UPDATE conference_sections SET status = 'approved' WHERE status IS NULL OR status = ''",
    'SELECT 1'
  )
);

PREPARE stmt_seed_status_for_existing FROM @seed_status_for_existing;
EXECUTE stmt_seed_status_for_existing;
DEALLOCATE PREPARE stmt_seed_status_for_existing;

SET @add_status_index = (
  SELECT IF(
    EXISTS(
      SELECT 1
      FROM INFORMATION_SCHEMA.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'conference_sections'
        AND INDEX_NAME = 'idx_conference_sections_status'
    ),
    'SELECT 1',
    'CREATE INDEX idx_conference_sections_status ON conference_sections (conference_content_id, status, sort_order)'
  )
);

PREPARE stmt_add_status_index FROM @add_status_index;
EXECUTE stmt_add_status_index;
DEALLOCATE PREPARE stmt_add_status_index;
