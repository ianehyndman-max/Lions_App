// SMTP Server Configuration Change
// Replace the gmail() line in lions_api.dart with one of these:

// ============================================
// OPTION 1: AWS SES (RECOMMENDED)
// ============================================
// Find this line in lions_api.dart (around line 118):
//   final smtpServer = gmail(_smtpUser, _smtpPass);
//
// Replace with:

final smtpServer = SmtpServer(
  'email-smtp.ap-southeast-2.amazonaws.com',  // Sydney region
  port: 587,
  username: _smtpUser,
  password: _smtpPass,
  ssl: false,
  allowInsecure: false,
);

// Other AWS SES regions:
// US East (N. Virginia): email-smtp.us-east-1.amazonaws.com
// US West (Oregon): email-smtp.us-west-2.amazonaws.com
// Europe (Ireland): email-smtp.eu-west-1.amazonaws.com

// ============================================
// OPTION 2: SendGrid
// ============================================

final smtpServer = SmtpServer(
  'smtp.sendgrid.net',
  port: 587,
  username: _smtpUser,  // Will be "apikey"
  password: _smtpPass,  // Will be your SendGrid API key
  ssl: false,
  allowInsecure: false,
);

// ============================================
// OPTION 3: Mailgun
// ============================================

final smtpServer = SmtpServer(
  'smtp.mailgun.org',
  port: 587,
  username: _smtpUser,  // postmaster@your-domain.mailgun.org
  password: _smtpPass,
  ssl: false,
  allowInsecure: false,
);

// ============================================
// KEEP Gmail for testing (current setup)
// ============================================
// If you want to keep testing with Gmail first, no changes needed!
// The gmail() helper is already configured correctly.
// Just make sure SMTP_USER and SMTP_PASS are set.
