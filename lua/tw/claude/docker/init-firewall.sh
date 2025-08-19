#!/bin/bash
set -euo pipefail

echo "Setting up firewall rules..."

# First, flush all existing rules to ensure clean state
echo "Flushing existing rules..."
iptables -F INPUT
iptables -F FORWARD
iptables -F OUTPUT

# Set default policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Allow established and related connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow loopback - IMPORTANT: Must specify interface with -i lo
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Allow DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# Allow SSH (for git operations)
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT

# Allow access to host machine (for local development servers)
if [[ -f /.dockerenv ]]; then
    # We're inside Docker
    if [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$(uname -s)" == "Linux" ]]; then
        # On Linux with --network host, no special rules needed
        echo "Running on Linux - host network access configured"
    else
        # On macOS/Windows, allow access to host.docker.internal
        HOST_IP=$(getent hosts host.docker.internal 2>/dev/null | awk '{ print $1 }' || true)
        if [ -n "$HOST_IP" ]; then
            iptables -A OUTPUT -d $HOST_IP -j ACCEPT
            echo "Allowed access to host machine at $HOST_IP"
        else
            echo "Warning: Could not resolve host.docker.internal"
        fi
    fi
fi

# Allow common development ports (customize as needed)
# This allows outbound connections to these ports on any IP
ALLOWED_PORTS=(80 443 1234 3000 3001 3100 4000 4200 5000 5173 5174 8000 8080 8081 8888 9000 9090 43111)
for port in "${ALLOWED_PORTS[@]}"; do
    iptables -A OUTPUT -p tcp --dport $port -j ACCEPT
    echo "Allowed outbound connections to port $port"
done

# Create ipset for allowed IP ranges
ipset create allowed_ips hash:net 2>/dev/null || ipset flush allowed_ips

# Allow common cloud provider IP ranges (GitHub, npm, etc.)
ALLOWED_CIDRS=(
    "140.82.112.0/20"    # GitHub
    "143.55.64.0/20"     # GitHub  
    "192.30.252.0/22"    # GitHub
    "185.199.108.0/22"   # GitHub
    "104.16.0.0/12"      # Cloudflare (npm)
    "172.64.0.0/13"      # Cloudflare
)

# Allow specific domains by resolving them
ALLOWED_DOMAINS=(
    "registry.npmjs.org"
    "github.com"
    "api.github.com"
    "raw.githubusercontent.com"
    "ghcr.io"
    "claude.ai"
    "api.anthropic.com"
    "o1js.anthropic.com"
)

# Add resolved IPs to ipset
for domain in "${ALLOWED_DOMAINS[@]}"; do
    IPS=$(getent hosts "$domain" 2>/dev/null | awk '{print $1}' || true)
    for ip in $IPS; do
        if [ -n "$ip" ]; then
            ipset add allowed_ips "$ip/32" 2>/dev/null || true
            echo "Added $domain ($ip) to allowed IPs"
        fi
    done
done

# Add CIDR ranges to ipset
for cidr in "${ALLOWED_CIDRS[@]}"; do
    ipset add allowed_ips "$cidr" 2>/dev/null || true
    echo "Added $cidr to allowed IPs"
done

# Allow traffic to ipset members
iptables -A OUTPUT -m set --match-set allowed_ips dst -j ACCEPT

# Preserve existing Docker DNS
if [ -f /etc/resolv.conf ]; then
    cp /etc/resolv.conf /etc/resolv.conf.bak
fi

echo "Firewall setup complete!"

# Verify the rules
echo -e "\nCurrent firewall rules:"
iptables -L -n -v

echo -e "\nAllowed IPs:"
ipset list allowed_ips | head -20

echo -e "\nFirewall initialization complete!"
