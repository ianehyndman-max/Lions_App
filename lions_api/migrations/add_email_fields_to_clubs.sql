-- Add email configuration fields to lions_club table
-- Run this migration on your database

ALTER TABLE lions_club 
ADD COLUMN email_subdomain VARCHAR(100) DEFAULT NULL COMMENT 'Email subdomain (e.g., "mudgeeraba" for noreply@mudgeeraba.thelionsapp.com)',
ADD COLUMN reply_to_email VARCHAR(255) DEFAULT NULL COMMENT 'Club''s actual email address for replies',
ADD COLUMN from_name VARCHAR(255) DEFAULT NULL COMMENT 'Display name for email sender (e.g., "Mudgeeraba Lions Club")';

-- Example update for existing clubs:
-- UPDATE lions_club SET 
--   email_subdomain = 'mudgeeraba', 
--   reply_to_email = 'secretary@mudgeerabalions.org.au',
--   from_name = 'Mudgeeraba Lions Club'
-- WHERE id = 1;
