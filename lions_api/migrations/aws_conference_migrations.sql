-- Conference database migration script for AWS / production MySQL
-- This script is idempotent and can be run repeatedly.
-- It applies the conference-related schema changes in order:
-- 1) add conference member flag and conference tables
-- 2) add conference section attachment table
-- 3) add conference section status/archive fields
-- 4) add conference section parent_id support

SET @add_conference_member_column = (
  SELECT IF(
    EXISTS(
      SELECT 1
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'members'
        AND COLUMN_NAME = 'is_conference_member'
    ),
    'SELECT 1',
    'ALTER TABLE members ADD COLUMN is_conference_member TINYINT(1) NOT NULL DEFAULT 0 AFTER is_super'
  )
);

PREPARE stmt_add_conference_member_column FROM @add_conference_member_column;
EXECUTE stmt_add_conference_member_column;
DEALLOCATE PREPARE stmt_add_conference_member_column;

CREATE TABLE IF NOT EXISTS conference_content (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  title VARCHAR(255) NOT NULL DEFAULT 'Conference',
  conference_date DATE DEFAULT NULL,
  theme VARCHAR(255) DEFAULT NULL,
  locations_notes TEXT DEFAULT NULL,
  breakout_sessions_notes TEXT DEFAULT NULL,
  general_notes TEXT DEFAULT NULL,
  last_updated_by_member_id BIGINT DEFAULT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_conference_content_member (last_updated_by_member_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS conference_ideas (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  title VARCHAR(255) NOT NULL,
  description TEXT DEFAULT NULL,
  category VARCHAR(100) DEFAULT NULL,
  status VARCHAR(30) NOT NULL DEFAULT 'new',
  created_by_member_id BIGINT DEFAULT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_conference_ideas_member (created_by_member_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS conference_sections (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  conference_content_id INT UNSIGNED NOT NULL,
  section_title VARCHAR(255) NOT NULL,
  section_body TEXT DEFAULT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  created_by_member_id BIGINT DEFAULT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_conference_sections_conference (conference_content_id),
  KEY idx_conference_sections_sort (sort_order),
  KEY idx_conference_sections_member (created_by_member_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS conference_section_attachments (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  section_id INT UNSIGNED NOT NULL,
  storage_key VARCHAR(512) NOT NULL,
  bucket VARCHAR(128) NOT NULL,
  original_filename VARCHAR(255) NOT NULL,
  mime_type VARCHAR(120) NOT NULL,
  file_size_bytes BIGINT UNSIGNED NOT NULL,
  file_kind ENUM('image', 'document') NOT NULL,
  width INT NULL,
  height INT NULL,
  thumbnail_storage_key VARCHAR(512) NULL,
  sort_order INT NOT NULL DEFAULT 0,
  status ENUM('active', 'archived', 'deleted') NOT NULL DEFAULT 'active',
  archived_at TIMESTAMP NULL DEFAULT NULL,
  archived_by_member_id BIGINT NULL,
  created_by_member_id BIGINT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_conf_attach_section_status (section_id, status),
  KEY idx_conf_attach_section_sort (section_id, sort_order),
  KEY idx_conf_attach_created_by (created_by_member_id),
  CONSTRAINT fk_conf_attach_section FOREIGN KEY (section_id)
    REFERENCES conference_sections (id)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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

ALTER TABLE conference_sections
  ADD COLUMN IF NOT EXISTS parent_id BIGINT NULL DEFAULT NULL AFTER sort_order;

ALTER TABLE conference_sections
  ADD INDEX IF NOT EXISTS idx_conference_sections_parent (parent_id, sort_order);

-- Optional verification queries
SELECT 'conference_content' AS table_name, COUNT(*) AS row_count FROM conference_content
UNION ALL
SELECT 'conference_ideas' AS table_name, COUNT(*) AS row_count FROM conference_ideas
UNION ALL
SELECT 'conference_sections' AS table_name, COUNT(*) AS row_count FROM conference_sections
UNION ALL
SELECT 'conference_section_attachments' AS table_name, COUNT(*) AS row_count FROM conference_section_attachments;

SHOW COLUMNS FROM members LIKE 'is_conference_member';
SHOW COLUMNS FROM conference_sections LIKE 'status';
SHOW COLUMNS FROM conference_sections LIKE 'parent_id';
