# Quick Start Checklist

## ✅ Pre-Implementation Complete
- [x] Domain purchased: thelionsapp.com
- [x] Database schema designed
- [x] Code implementation complete
- [x] UI updated
- [x] Documentation created

## 📋 Your To-Do List

### Phase 1: Database Migration (5 minutes)
- [ ] Connect to AWS RDS (when accessible)
- [ ] Run: `dart run lions_api/bin/migrate_add_email_fields.dart`
- [ ] Verify: Check that lions_club table has new columns

### Phase 2: Email Service Setup (30-60 minutes)
Choose ONE:

#### Option A: AWS SES (Recommended)
- [ ] Sign in to AWS Console
- [ ] Navigate to Simple Email Service (SES)
- [ ] Create identity for domain: thelionsapp.com
- [ ] Copy DNS records (DKIM, SPF, DMARC)
- [ ] Add DNS records to domain registrar
- [ ] Wait for verification (check status in AWS)
- [ ] Request production access (form submission)
- [ ] Wait for approval (~24 hours)
- [ ] Create SMTP credentials
- [ ] Save credentials securely

#### Option B: SendGrid (Alternative)
- [ ] Sign up at sendgrid.com
- [ ] Navigate to Sender Authentication
- [ ] Add domain: thelionsapp.com
- [ ] Copy DNS records
- [ ] Add DNS records to domain registrar
- [ ] Wait for verification
- [ ] Create API key
- [ ] Save API key securely

### Phase 3: Code Configuration (10 minutes)
- [ ] Open `lions_api/bin/lions_api.dart`
- [ ] Find line ~118: `final smtpServer = gmail(_smtpUser, _smtpPass);`
- [ ] Replace with AWS SES or SendGrid config (see SMTP_SERVER_CONFIG.dart)
- [ ] Save file

### Phase 4: Environment Variables (5 minutes)
On your server (AWS EC2 / wherever API runs):
- [ ] SSH into server
- [ ] Set `SMTP_USER` environment variable
- [ ] Set `SMTP_PASS` environment variable
- [ ] Restart API server

Commands:
```bash
export SMTP_USER="your-smtp-username"
export SMTP_PASS="your-smtp-password"
# Restart your API (e.g., pm2 restart lions-api)
```

### Phase 5: Configure Clubs (5 minutes per club)
- [ ] Open Lions App as super user
- [ ] Navigate to "Manage Clubs"
- [ ] Click Edit on first club
- [ ] Fill in email configuration:
  - Email Subdomain: (e.g., "mudgeeraba")
  - Reply-To Email: (e.g., "secretary@mudgeerabalions.org.au")
  - From Name: (e.g., "Mudgeeraba Lions Club")
- [ ] Save
- [ ] Repeat for each club

### Phase 6: Testing (10 minutes)
- [ ] Create a test event
- [ ] Assign yourself to a role
- [ ] Send email notification
- [ ] Check your inbox
- [ ] Verify "From" address shows club subdomain
- [ ] Click "Reply"
- [ ] Verify reply goes to club's Reply-To address
- [ ] Celebrate! 🎉

## 📁 Reference Documents

### Setup Guides
- `EMAIL_SETUP_GUIDE.md` - Complete step-by-step instructions
- `SMTP_SERVER_CONFIG.dart` - SMTP server configuration examples
- `EMAIL_ARCHITECTURE_DIAGRAM.md` - Visual architecture overview

### Implementation Details
- `IMPLEMENTATION_SUMMARY.md` - What was changed and why
- `lions_api/migrations/add_email_fields_to_clubs.sql` - SQL migration

### Migration Script
- `lions_api/bin/migrate_add_email_fields.dart` - Database migration tool

## ⏱️ Time Estimates

| Phase | Time | Dependencies |
|-------|------|--------------|
| Database Migration | 5 min | Database accessible |
| Email Service Setup | 30-60 min | Domain access |
| Code Configuration | 10 min | - |
| Environment Variables | 5 min | Server access |
| Configure Clubs | 5 min/club | - |
| Testing | 10 min | All above complete |
| **TOTAL** | **1-2 hours** | (plus verification wait time) |

## 🚨 Common Issues

### Issue: Database connection timeout
**Solution:** 
- Check AWS RDS security group
- Ensure your IP is whitelisted
- Try running from EC2 instance

### Issue: DNS verification pending
**Solution:** 
- DNS changes take 1-48 hours to propagate
- Check status in AWS SES/SendGrid dashboard
- Use DNS checker tools (whatsmydns.net)

### Issue: Emails in sandbox mode (AWS SES)
**Solution:** 
- Request production access in AWS SES
- Fill out form explaining use case
- Usually approved within 24 hours

### Issue: Emails going to spam
**Solution:** 
- Ensure ALL DNS records added (DKIM, SPF, DMARC)
- Wait 48 hours after DNS changes
- Check domain reputation (mxtoolbox.com)
- Verify DKIM signatures passing

## 💡 Tips

1. **Start with one club** - Configure and test with one club before doing all
2. **Keep Gmail as fallback** - Clubs without config will use Gmail (current behavior)
3. **Test thoroughly** - Send test emails to multiple providers (Gmail, Outlook, etc.)
4. **Monitor deliverability** - Check AWS SES/SendGrid dashboards for bounce rates
5. **Document credentials** - Store SMTP credentials in password manager

## 🎯 Success Criteria

You'll know it's working when:
- ✅ Emails send successfully
- ✅ "From" shows: `noreply@subdomain.thelionsapp.com`
- ✅ "From Name" shows: Club name (e.g., "Mudgeeraba Lions Club")
- ✅ Clicking "Reply" addresses to club's Reply-To email
- ✅ No manual forwarding needed
- ✅ Emails arrive in inbox (not spam)

## 📞 Support

If you get stuck:
1. Check the detailed guide: `EMAIL_SETUP_GUIDE.md`
2. Review architecture: `EMAIL_ARCHITECTURE_DIAGRAM.md`
3. Verify implementation: `IMPLEMENTATION_SUMMARY.md`
4. Ask for help - I'm here! 😊

## 🎉 After Setup

Once complete, you'll have:
- ✅ Professional email addresses for each club
- ✅ Automatic reply routing (no more forwarding!)
- ✅ Unlimited clubs at no additional cost
- ✅ Better email deliverability
- ✅ Scalable system for growth

**Happy emailing! 📧🦁**
