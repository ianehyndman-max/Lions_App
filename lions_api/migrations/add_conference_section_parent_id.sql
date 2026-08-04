-- Migration: add parent_id to conference_sections for nested sections
ALTER TABLE conference_sections
  ADD COLUMN IF NOT EXISTS parent_id BIGINT NULL DEFAULT NULL AFTER sort_order;

ALTER TABLE conference_sections
  ADD INDEX IF NOT EXISTS idx_conference_sections_parent (parent_id, sort_order);
