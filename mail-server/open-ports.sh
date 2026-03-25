#!/bin/bash
# Open mail server ports via UFW
# Run with: sudo ./open-ports.sh

echo "Opening mail server ports..."

# SMTP (incoming mail)
ufw allow 25/tcp comment 'Mail SMTP'

# SMTPS (implicit TLS)
ufw allow 465/tcp comment 'Mail SMTPS'

# Submission (STARTTLS - for clients)
ufw allow 587/tcp comment 'Mail Submission'

# IMAPS (secure IMAP)
ufw allow 993/tcp comment 'Mail IMAPS'

# IMAP (plain - for internal/testing)
ufw allow 143/tcp comment 'Mail IMAP'

# POP3S (optional)
ufw allow 995/tcp comment 'Mail POP3S'

echo "Done! Ports opened:"
echo "  25   - SMTP (incoming mail)"
echo "  465  - SMTPS (implicit TLS)"
echo "  587  - Submission (STARTTLS)"
echo "  993  - IMAPS (secure IMAP)"
echo "  143  - IMAP (plain)"
echo "  995  - POP3S (optional)"
