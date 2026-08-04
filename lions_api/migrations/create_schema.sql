-- Full schema for Lions App local development
-- Run with: mysql -u <user> -p <database> < create_schema.sql

SET FOREIGN_KEY_CHECKS = 0;

CREATE TABLE IF NOT EXISTS `lions_club` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(255) NOT NULL,
  `email_subdomain` VARCHAR(100) DEFAULT NULL,
  `reply_to_email` VARCHAR(255) DEFAULT NULL,
  `from_name` VARCHAR(255) DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `members` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(255) NOT NULL,
  `email` VARCHAR(255) DEFAULT NULL,
  `phone_number` VARCHAR(50) DEFAULT NULL,
  `lions_club_id` INT UNSIGNED DEFAULT NULL,
  `is_admin` TINYINT(1) NOT NULL DEFAULT 0,
  `is_super` TINYINT(1) NOT NULL DEFAULT 0,
  `is_conference_member` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `fk_members_club` (`lions_club_id`),
  CONSTRAINT `fk_members_club` FOREIGN KEY (`lions_club_id`) REFERENCES `lions_club` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `conference_content` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `title` VARCHAR(255) NOT NULL DEFAULT 'Conference',
  `conference_date` DATE DEFAULT NULL,
  `theme` VARCHAR(255) DEFAULT NULL,
  `locations_notes` TEXT DEFAULT NULL,
  `breakout_sessions_notes` TEXT DEFAULT NULL,
  `general_notes` TEXT DEFAULT NULL,
  `last_updated_by_member_id` INT UNSIGNED DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `fk_conference_content_member` (`last_updated_by_member_id`),
  CONSTRAINT `fk_conference_content_member` FOREIGN KEY (`last_updated_by_member_id`) REFERENCES `members` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `conference_ideas` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `title` VARCHAR(255) NOT NULL,
  `description` TEXT DEFAULT NULL,
  `category` VARCHAR(100) DEFAULT NULL,
  `status` VARCHAR(30) NOT NULL DEFAULT 'new',
  `created_by_member_id` INT UNSIGNED DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `fk_conference_ideas_member` (`created_by_member_id`),
  CONSTRAINT `fk_conference_ideas_member` FOREIGN KEY (`created_by_member_id`) REFERENCES `members` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `conference_sections` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `conference_content_id` INT UNSIGNED NOT NULL,
  `section_title` VARCHAR(255) NOT NULL,
  `section_body` TEXT DEFAULT NULL,
  `sort_order` INT NOT NULL DEFAULT 0,
  `created_by_member_id` BIGINT DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_conference_sections_conference` (`conference_content_id`),
  KEY `idx_conference_sections_sort` (`sort_order`),
  KEY `idx_conference_sections_member` (`created_by_member_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `event_types` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(255) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `events` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `event_type_id` INT UNSIGNED DEFAULT NULL,
  `lions_club_id` INT UNSIGNED DEFAULT NULL,
  `event_date` DATE DEFAULT NULL,
  `location` VARCHAR(255) DEFAULT NULL,
  `notes` TEXT DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `fk_events_type` (`event_type_id`),
  KEY `fk_events_club` (`lions_club_id`),
  CONSTRAINT `fk_events_type` FOREIGN KEY (`event_type_id`) REFERENCES `event_types` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_events_club` FOREIGN KEY (`lions_club_id`) REFERENCES `lions_club` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `roles` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `event_id` INT UNSIGNED DEFAULT NULL,
  `event_type_id` INT UNSIGNED DEFAULT NULL,
  `role_name` VARCHAR(255) NOT NULL,
  `time_in` VARCHAR(20) DEFAULT NULL,
  `time_out` VARCHAR(20) DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `fk_roles_event` (`event_id`),
  KEY `fk_roles_event_type` (`event_type_id`),
  CONSTRAINT `fk_roles_event` FOREIGN KEY (`event_id`) REFERENCES `events` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_roles_event_type` FOREIGN KEY (`event_type_id`) REFERENCES `event_types` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `event_volunteers` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `event_id` INT UNSIGNED NOT NULL,
  `role_id` INT UNSIGNED NOT NULL,
  `member_id` INT UNSIGNED DEFAULT NULL,
  `meal_choice` VARCHAR(100) DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_event_role` (`event_id`, `role_id`),
  KEY `fk_ev_event` (`event_id`),
  KEY `fk_ev_role` (`role_id`),
  KEY `fk_ev_member` (`member_id`),
  CONSTRAINT `fk_ev_event` FOREIGN KEY (`event_id`) REFERENCES `events` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_ev_role` FOREIGN KEY (`role_id`) REFERENCES `roles` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_ev_member` FOREIGN KEY (`member_id`) REFERENCES `members` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `dinner_meal_options` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `option_name` VARCHAR(100) NOT NULL,
  `sort_order` INT NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `audit_log` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `entity_type` VARCHAR(50) DEFAULT NULL,
  `entity_id` INT DEFAULT NULL,
  `action` VARCHAR(50) DEFAULT NULL,
  `changed_by_member_id` INT DEFAULT NULL,
  `old_value` TEXT DEFAULT NULL,
  `new_value` TEXT DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

SET FOREIGN_KEY_CHECKS = 1;

-- Seed data: one club, one super-admin member, and a Dinner Meeting event type
INSERT IGNORE INTO `lions_club` (id, name) VALUES (1, 'Test Club');

INSERT IGNORE INTO `members` (id, name, email, lions_club_id, is_admin, is_super, is_conference_member)
VALUES (1, 'Admin User', 'admin@test.com', 1, 1, 1, 1);

INSERT IGNORE INTO `event_types` (id, name) VALUES (1, 'Dinner Meeting');
