# Email Architecture Diagram

## Current vs New System

### BEFORE (Current Gmail Setup)
```
┌─────────────────────────────────────────────────────────────┐
│                    Lions App Backend                         │
│                                                              │
│  Send Email ──────────────────────────────────────────────> │
│     ↓                                                        │
│  Your Gmail Account                                          │
│  (yourname@gmail.com)                                       │
└──────────────────────────────────────────────────────────────┘
                          │
                          ↓
┌──────────────────────────────────────────────────────────────┐
│                     Member Receives                           │
│                                                              │
│  From: yourname@gmail.com                                    │
│  Subject: New Lions Club Event                               │
└──────────────────────────────────────────────────────────────┘
                          │
                          ↓
                    Member Replies
                          │
                          ↓
           Reply goes to YOUR Gmail ❌
           (You forward manually)
```

### AFTER (Per-Club Email System)
```
┌──────────────────────────────────────────────────────────────┐
│                    Lions App Backend                          │
│                                                              │
│  1. Fetch club email config from DB                          │
│     - email_subdomain: "mudgeeraba"                          │
│     - reply_to_email: "secretary@mudgeerabalions.org.au"    │
│     - from_name: "Mudgeeraba Lions Club"                    │
│                                                              │
│  2. Build email with club-specific addresses                 │
│     From: noreply@mudgeeraba.thelionsapp.com                │
│     Reply-To: secretary@mudgeerabalions.org.au              │
│                                                              │
│  3. Send via AWS SES / SendGrid                             │
└──────────────────────────────────────────────────────────────┘
                          │
                          ↓
┌──────────────────────────────────────────────────────────────┐
│                     Member Receives                           │
│                                                              │
│  From: Mudgeeraba Lions Club                                 │
│        <noreply@mudgeeraba.thelionsapp.com>                 │
│  Reply-To: secretary@mudgeerabalions.org.au                 │
│  Subject: 🦁 New Mudgeeraba Lions Club Event                │
└──────────────────────────────────────────────────────────────┘
                          │
                          ↓
                    Member Replies
                          │
                          ↓
    Reply AUTOMATICALLY goes to club's email ✅
    secretary@mudgeerabalions.org.au
    (No forwarding needed!)
```

## Multi-Club Architecture
```
┌─────────────────────────────────────────────────────────────┐
│                     Domain: thelionsapp.com                  │
│                                                             │
│  Verified with AWS SES / SendGrid                           │
│  All subdomains authorized to send                          │
└─────────────────────────────────────────────────────────────┘
                          │
          ┌───────────────┼───────────────┐
          │               │               │
          ↓               ↓               ↓
┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
│  Mudgeeraba Club │ │    Robina Club   │ │  Southport Club  │
│                  │ │                  │ │                  │
│ From:            │ │ From:            │ │ From:            │
│ noreply@         │ │ noreply@         │ │ noreply@         │
│ mudgeeraba       │ │ robina           │ │ southport        │
│ .thelionsapp.com │ │ .thelionsapp.com │ │ .thelionsapp.com │
│                  │ │                  │ │                  │
│ Reply-To:        │ │ Reply-To:        │ │ Reply-To:        │
│ secretary@       │ │ info@            │ │ contact@         │
│ mudgeerabalions  │ │ robinalions      │ │ southportlions   │
│ .org.au          │ │ .org.au          │ │ .org.au          │
└──────────────────┘ └──────────────────┘ └──────────────────┘
```

## DNS Configuration
```
Domain Registrar (e.g., Namecheap, GoDaddy)
for: thelionsapp.com

┌─────────────────────────────────────────────────────────────┐
│                       DNS Records                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  DKIM Authentication (3 records)                            │
│  ├─ abc123._domainkey.thelionsapp.com → CNAME → AWS         │
│  ├─ def456._domainkey.thelionsapp.com → CNAME → AWS         │
│  └─ ghi789._domainkey.thelionsapp.com → CNAME → AWS         │
│                                                             │
│  SPF Record (prevents spoofing)                             │
│  └─ @ TXT "v=spf1 include:amazonses.com ~all"              │
│                                                             │
│  DMARC Record (policy)                                      │
│  └─ _dmarc TXT "v=DMARC1; p=none; rua=mailto:you@..."      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                          │
                          ↓
                  Verified ✅
                          │
                          ↓
        Emails from *.thelionsapp.com
        authenticated and trusted
```

## Data Flow
```
1. Admin creates event in app
         │
         ↓
2. App queries database for club info
         │
         ↓
3. Database returns:
   - Club name: "Mudgeeraba Lions Club"
   - Email subdomain: "mudgeeraba"
   - Reply-to: "secretary@mudgeerabalions.org.au"
         │
         ↓
4. App builds email:
   FROM: noreply@mudgeeraba.thelionsapp.com
   REPLY-TO: secretary@mudgeerabalions.org.au
   SUBJECT: 🦁 New Event
         │
         ↓
5. Send via AWS SES SMTP:
   Server: email-smtp.ap-southeast-2.amazonaws.com
   Port: 587 (TLS)
   Auth: SMTP credentials
         │
         ↓
6. AWS SES delivers to club members
         │
         ↓
7. Member receives:
   Shows: "Mudgeeraba Lions Club"
   From: noreply@mudgeeraba.thelionsapp.com
         │
         ↓
8. Member clicks REPLY
         │
         ↓
9. Email client automatically addresses to:
   secretary@mudgeerabalions.org.au ✅
```

## Cost Breakdown
```
┌─────────────────────────────────────────────────────────────┐
│                    Annual Cost Estimate                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Domain Registration                                        │
│  └─ thelionsapp.com         $12-15/year  ✅ Already owned!  │
│                                                             │
│  Email Service (Choose ONE):                                │
│  ├─ AWS SES                                                 │
│  │  ├─ Year 1: FREE (52,000 emails)                        │
│  │  └─ Year 2+: ~$1-5/month for typical use               │
│  │                                                          │
│  └─ SendGrid                                                │
│     └─ FREE forever (100 emails/day = 3,000/month)         │
│                                                             │
│  ────────────────────────────────────────────────────────   │
│  TOTAL:           $12-30/year for UNLIMITED clubs!          │
│  Per Club Cost:   $0 (no additional cost per club)          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Setup Timeline
```
Week 1: Infrastructure Setup
├─ Day 1-2: Sign up for AWS SES / SendGrid
├─ Day 2-3: Verify domain (add DNS records)
└─ Day 3-4: Wait for verification (automatic)

Week 2: Configuration
├─ Day 1: Request production access (AWS SES)
├─ Day 2: Get SMTP credentials
├─ Day 3: Update code (SMTP server config)
├─ Day 4: Set environment variables
└─ Day 5: Run database migration

Week 3: Club Setup & Testing
├─ Day 1-2: Configure clubs in app
├─ Day 3-4: Send test emails
└─ Day 5: Go live! 🚀

Total Time: ~2-3 weeks (mostly waiting for verification)
Active Work: ~4-6 hours
```
