# Email Setup Guide for Lions App

## Overview
Your Lions App now supports **per-club email addresses** with automatic reply routing! Each club can have emails sent from a professional address like `noreply@mudgeeraba.thelionsapp.com`, with replies automatically going to the club's actual email address.

## What You Need
1. ✅ Domain: **thelionsapp.com** (already purchased!)
2. 📧 Transactional email service (choose one):
   - **AWS SES** (Recommended - cheapest, 52k free emails first year)
   - **SendGrid** (100 emails/day free forever)
   - **Mailgun** (5000 emails/month free)

---

## Implementation Steps

### Phase 1: Run Database Migration ⚙️

1. **Connect to your server** (when AWS RDS is accessible)
2. **Run the migration:**
   ```bash
   cd lions_api
   dart run bin/migrate_add_email_fields.dart
   ```
   
   This adds three new fields to the `lions_club` table:
   - `email_subdomain` - e.g., "mudgeeraba"
   - `reply_to_email` - e.g., "secretary@mudgeerabalions.org.au"
   - `from_name` - e.g., "Mudgeeraba Lions Club"

### Phase 2: Configure Email Service 📧

I recommend **AWS SES** because:
- ✅ 52,000 free emails per year (first year)
- ✅ $0.10 per 1,000 emails after that
- ✅ Excellent deliverability
- ✅ You're already using AWS

#### Option A: AWS SES Setup (Recommended)

1. **Sign in to AWS Console** → Search for "SES" (Simple Email Service)

2. **Verify your domain:**
   - Go to **Verified Identities** → **Create Identity**
   - Choose **Domain**
   - Enter: `thelionsapp.com`
   - Click **Create Identity**

3. **Configure DNS Records:**
   AWS will provide DNS records. Add these to your domain registrar (e.g., Namecheap, GoDaddy):
   
   **DKIM Records** (for email authentication - 3 records):
   ```
   Type: CNAME
   Name: [value from AWS]._domainkey.thelionsapp.com
   Value: [value from AWS].dkim.amazonses.com
   ```
   Repeat for all 3 DKIM records AWS provides.

   **SPF Record** (add to existing TXT record or create new):
   ```
   Type: TXT
   Name: thelionsapp.com
   Value: "v=spf1 include:amazonses.com ~all"
   ```

   **DMARC Record** (optional but recommended):
   ```
   Type: TXT
   Name: _dmarc.thelionsapp.com
   Value: "v=DMARC1; p=none; rua=mailto:your-email@example.com"
   ```

4. **Wait for verification** (usually 1-24 hours)

5. **Request Production Access:**
   - By default, SES starts in "sandbox mode" (can only send to verified emails)
   - Go to **Account Dashboard** → **Request production access**
   - Fill out the form explaining your use case (Lions Club event notifications)
   - Usually approved within 24 hours

6. **Get SMTP Credentials:**
   - Go to **SMTP settings** in SES
   - Click **Create SMTP credentials**
   - **Save these credentials securely!** You'll need them for your server

7. **Note your SMTP endpoint:**
   - Will be something like: `email-smtp.ap-southeast-2.amazonaws.com`
   - Port: `587` (TLS) or `465` (SSL)

#### Option B: SendGrid Setup (Alternative)

1. **Sign up:** https://sendgrid.com (free tier: 100 emails/day)
2. **Verify domain:** Settings → Sender Authentication → Authenticate Your Domain
3. **Add DNS records** (similar to AWS SES)
4. **Create API Key:** Settings → API Keys → Create API Key
5. **SMTP Credentials:**
   - Server: `smtp.sendgrid.net`
   - Port: `587`
   - Username: `apikey`
   - Password: [Your API Key]

### Phase 3: Update Environment Variables 🔐

Update your server environment variables (on AWS EC2 or wherever your API runs):

**For AWS SES:**
```bash
export SMTP_USER="your-smtp-username-from-ses"
export SMTP_PASS="your-smtp-password-from-ses"
```

**For SendGrid:**
```bash
export SMTP_USER="apikey"
export SMTP_PASS="your-sendgrid-api-key"
```

**Important:** The code currently uses Gmail SMTP. You'll need to update this line in `lions_api.dart`:

Change:
```dart
final smtpServer = gmail(_smtpUser, _smtpPass);
```

To:
```dart
// For AWS SES (Sydney region)
final smtpServer = SmtpServer(
  'email-smtp.ap-southeast-2.amazonaws.com',
  port: 587,
  username: _smtpUser,
  password: _smtpPass,
);

// For SendGrid
// final smtpServer = SmtpServer(
//   'smtp.sendgrid.net',
//   port: 587,
//   username: _smtpUser,
//   password: _smtpPass,
// );
```

### Phase 4: Configure Clubs in the App 🦁

1. **Open the Lions App**
2. **Go to:** Manage Clubs (super user only)
3. **For each club, click Edit:**
   
   **Example for Mudgeeraba Lions:**
   - **Club Name:** Mudgeeraba Lions Club
   - **Email Subdomain:** `mudgeeraba`
   - **Reply-To Email:** `secretary@mudgeerabalions.org.au`
   - **From Name:** `Mudgeeraba Lions Club`

4. **Save** - you should see a green email icon indicating email is configured!

### Phase 5: Test! 🧪

1. Create a test event
2. Send email notifications
3. Check that emails arrive from: `noreply@mudgeeraba.thelionsapp.com`
4. Reply to the email - it should go to the club's Reply-To address

---

## How It Works

### Email Flow

```
App sends email
    ↓
Email appears FROM: noreply@mudgeeraba.thelionsapp.com
Reply-To: secretary@mudgeerabalions.org.au
    ↓
Member receives email
    ↓
Member clicks "Reply"
    ↓
Reply automatically goes to: secretary@mudgeerabalions.org.au ✅
```

### What Members See

**Email Header:**
```
From: Mudgeeraba Lions Club <noreply@mudgeeraba.thelionsapp.com>
Reply-To: secretary@mudgeerabalions.org.au
Subject: 🦁 New Mudgeeraba Lions Club Event
```

When they hit Reply, their email client automatically addresses it to the club's actual email!

---

## Fallback Behavior

If a club **doesn't have email configured**:
- Emails send from your current Gmail account (as before)
- No Reply-To header is added
- Works exactly as it does now

This means you can gradually configure clubs without breaking existing functionality!

---

## Cost Estimates

### AWS SES
- **Year 1:** FREE (up to 52,000 emails)
- **After Year 1:** ~$1-5/month for typical use
- Example: 5,000 emails/month = $0.50/month

### SendGrid
- **Forever:** FREE (up to 100 emails/day = 3,000/month)
- If you exceed: $19.95/month for 50,000 emails

### Domain
- **thelionsapp.com:** ~$12-15/year (already purchased!)

**Total: ~$12-30/year** for unlimited clubs! 🎉

---

## Troubleshooting

### Emails not sending
1. Check environment variables are set correctly
2. Verify domain in email service (AWS SES/SendGrid)
3. Check you're out of sandbox mode (AWS SES)
4. Verify SMTP credentials

### Emails going to spam
1. Ensure all DNS records are added (DKIM, SPF, DMARC)
2. Wait 48 hours after adding DNS records
3. Check domain reputation (mxtoolbox.com/SuperTool.aspx)

### Database migration fails
- Ensure your AWS RDS instance is accessible
- Check security group allows connections from your IP
- Try running from EC2 instance if local connection fails

---

## Next Steps

1. ✅ Database migration created - ready to run
2. ✅ Code updated - supports per-club emails
3. ✅ UI updated - configure email settings in app
4. ⏳ Choose email service (AWS SES recommended)
5. ⏳ Configure domain DNS records
6. ⏳ Update SMTP server code in lions_api.dart
7. ⏳ Set environment variables
8. ⏳ Configure clubs in the app
9. ⏳ Test and celebrate! 🎉

---

## Questions?

Feel free to ask! The implementation is complete and ready - you just need to:
1. Run the migration when database is accessible
2. Set up your email service
3. Configure the clubs in the app

**Happy emailing! 📧🦁**
