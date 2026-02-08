#!/bin/bash
set -e

# Select dnsmasq configuration based on PROXY_DHCP environment variable
if [ "$PROXY_DHCP" = "true" ]; then
    echo "=== Starting PXE server in DHCP Proxy mode ==="
    cp /etc/dnsmasq-proxy.conf.template /etc/dnsmasq.conf
else
    echo "=== Starting PXE server in TFTP-only mode ==="
    cp /etc/dnsmasq.conf.template /etc/dnsmasq.conf
fi

# Display configuration
echo "TFTP root: /tftpboot"
echo "HTTP root: /var/www/html/iso"
echo "Configuration: /etc/dnsmasq.conf"

# Start supervisord (manages dnsmasq + nginx)
exec /usr/bin/supervisord -c /etc/supervisord.conf
