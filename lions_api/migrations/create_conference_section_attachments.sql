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
