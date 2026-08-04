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
