#!/bin/bash
# Verify migration was successful
# Run on: local machine (after DNS propagation)
# Usage: bash scripts/6-verify-migration.sh

set -e

NEW_SERVER="polaris2"
DOMAIN="cativo.dev"

echo "=== Migration Verification Script ==="
echo ""

# 1. Check DNS propagation
echo "1. Checking DNS propagation..."
RESOLVED_IP=$(dig +short "$DOMAIN" | head -1)
echo "   $DOMAIN resolves to: $RESOLVED_IP"

if [ "$RESOLVED_IP" = "167.235.52.161" ]; then
    echo "   ✓ DNS updated correctly"
else
    echo "   ⚠ DNS still pointing to old IP or not propagated yet"
    echo "   Wait a few more minutes and try again"
fi

# 2. Check SSL certificates
echo ""
echo "2. Checking SSL certificates..."
SERVICES=(
    "cativo.dev"
    "blog.cativo.dev"
    "mail.cativo.dev"
    "traefik.cativo.dev"
    "grafana.cativo.dev"
    "prometheus.cativo.dev"
)

for service in "${SERVICES[@]}"; do
    echo "   Testing $service..."
    if curl -sI "https://$service" | head -1 | grep -q "200\|301\|302"; then
        echo "   ✓ $service responding"
    else
        echo "   ⚠ $service not responding correctly"
    fi
done

# 3. Check mail server ports
echo ""
echo "3. Checking mail server ports..."
MAIL_PORTS=(25 465 587 993 143)

for port in "${MAIL_PORTS[@]}"; do
    if nc -zv mail.cativo.dev "$port" 2>&1 | grep -q "succeeded\|open"; then
        echo "   ✓ Port $port open"
    else
        echo "   ⚠ Port $port not accessible"
    fi
done

# 4. Check container status on new server
echo ""
echo "4. Checking container status on $NEW_SERVER..."
ssh "$NEW_SERVER" "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -v 'Up' || echo 'All containers running'"

# 5. Check for errors in logs
echo ""
echo "5. Checking for errors in Traefik logs..."
ssh "$NEW_SERVER" "docker logs traefik --tail 50 2>&1 | grep -i error || echo '   No errors found'"

# 6. Test Ghost admin
echo ""
echo "6. Testing Ghost blog..."
if curl -sI "https://blog.cativo.dev" | head -1 | grep -q "200"; then
    echo "   ✓ Ghost blog accessible"
    echo "   Test admin: https://blog.cativo.dev/ghost/"
else
    echo "   ⚠ Ghost blog not responding"
fi

# 7. Test webmail
echo ""
echo "7. Testing webmail..."
if curl -sI "https://mail.cativo.dev" | head -1 | grep -q "200"; then
    echo "   ✓ Webmail accessible"
    echo "   Test login: https://mail.cativo.dev"
else
    echo "   ⚠ Webmail not responding"
fi

# 8. Check monitoring
echo ""
echo "8. Testing monitoring stack..."
if curl -sI "https://grafana.cativo.dev" | head -1 | grep -q "200\|302"; then
    echo "   ✓ Grafana accessible"
else
    echo "   ⚠ Grafana not responding"
fi

if curl -sI "https://prometheus.cativo.dev" | head -1 | grep -q "200\|401"; then
    echo "   ✓ Prometheus accessible"
else
    echo "   ⚠ Prometheus not responding"
fi

echo ""
echo "=== Verification Complete ==="
echo ""
echo "Next steps:"
echo "1. Test sending/receiving emails"
echo "2. Check Grafana dashboards"
echo "3. Monitor logs for 24-48 hours"
echo "4. Keep old server running for 1 week as backup"
echo ""
echo "Monitoring commands:"
echo "  ssh $NEW_SERVER 'docker stats'"
echo "  ssh $NEW_SERVER 'docker logs -f traefik'"
echo "  ssh $NEW_SERVER 'docker logs -f mail'"
