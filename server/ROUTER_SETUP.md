# OpenWrt Router Setup Guide (v2.0.0)

This guide provides complete instructions for configuring an OpenWrt router to serve as the network perimeter for the remote-ollama-proxy infrastructure.

---

## Prerequisites

- OpenWrt-compatible router hardware
- OpenWrt 23.05 LTS or later installed
- Physical wired network connection to router (no Wi-Fi for administration)
- Basic understanding of networking concepts (IP addresses, subnets, firewall rules)

**Note**: This guide assumes OpenWrt is already installed on your router. For router-specific installation instructions, see [OpenWrt Table of Hardware](https://openwrt.org/toh/start).

---

## Architecture Overview

```
Internet
   ↓
WAN (eth0) - Public IP
   ↓
OpenWrt Router
   ├─ LAN (br-lan) - 192.168.1.0/24 (admin only)
   ├─ DMZ (br-dmz) - 192.168.100.0/24 (AI server)
   └─ VPN (wg0) - 10.10.10.0/24 (VPN clients)

Firewall zones:
- wan → all: deny (except WireGuard UDP)
- vpn → dmz: allow (port 11434 only)
- vpn → lan: deny
- vpn → wan: deny
- dmz → lan: deny
- dmz → wan: allow (outbound internet)
- lan → dmz: allow (admin access)
```

---

## Part 1: Initial Router Access

### Connect to Router

```bash
# Connect via Ethernet cable to LAN port
# Default IP: 192.168.1.1
# Access via web browser: http://192.168.1.1

# Or via SSH (if enabled):
ssh root@192.168.1.1
```

**Default credentials:**
- Username: `root`
- Password: (blank or set during first setup)

**IMPORTANT**: Set a strong root password immediately:
```bash
passwd
```

---

## Part 2: Network Interface Configuration

### Option A: Via LuCI Web Interface

1. Navigate to **Network → Interfaces**
2. Configure existing interfaces:

**WAN Interface:**
- Protocol: DHCP Client (or Static IP if ISP provided)
- Physical Settings: WAN port (typically eth0)

**LAN Interface:**
- Protocol: Static Address
- IPv4 Address: `192.168.1.1`
- IPv4 Netmask: `255.255.255.0` (/24)
- DHCP Server: Enabled (for admin devices)

3. Create **DMZ Interface**:
- Click "Add new interface"
- Name: `dmz`
- Protocol: Static Address
- IPv4 Address: `192.168.100.1`
- IPv4 Netmask: `255.255.255.0` (/24)
- Physical Settings: Create VLAN or use dedicated physical interface

### Option B: Via UCI Command Line

```bash
# DMZ interface configuration
uci set network.dmz=interface
uci set network.dmz.proto='static'
uci set network.dmz.ipaddr='192.168.100.1'
uci set network.dmz.netmask='255.255.255.0'

# If using VLAN (adjust device name as needed):
uci set network.dmz.device='eth1'  # Or 'eth0.100' for VLAN tagging

# Commit changes
uci commit network
/etc/init.d/network restart
```

### Verify Interfaces

```bash
# List all interfaces
ip addr show

# Should see:
# - br-lan (192.168.1.1/24)
# - br-dmz (192.168.100.1/24)
# - eth0 (WAN)
```

---

## Part 3: DHCP Configuration for DMZ

### Static IP for AI Server

**Via LuCI:**
1. Navigate to **Network → DHCP and DNS**
2. Go to **Static Leases** tab
3. Add static lease:
   - Hostname: `remote-ollama-proxy`
   - MAC Address: (AI server's MAC address)
   - IPv4 Address: `192.168.100.10`

**Via UCI:**
```bash
# Add static DHCP lease
uci add dhcp host
uci set dhcp.@host[-1].name='remote-ollama-proxy'
uci set dhcp.@host[-1].mac='XX:XX:XX:XX:XX:XX'  # Replace with actual MAC
uci set dhcp.@host[-1].ip='192.168.100.10'

uci commit dhcp
/etc/init.d/dnsmasq restart
```

**Alternative: Configure static IP on server directly** (recommended for stability)
- See server installation guide for macOS static IP configuration

---

## Part 4: WireGuard VPN Setup

### Install WireGuard Packages

```bash
# Update package lists
opkg update

# Install WireGuard and tools
opkg install wireguard-tools luci-proto-wireguard luci-app-wireguard kmod-wireguard

# Reboot to load kernel module
reboot
```

### Generate Server Keys

```bash
# Generate server private key
umask 077
wg genkey > /etc/wireguard/server_private.key

# Generate server public key
wg pubkey < /etc/wireguard/server_private.key > /etc/wireguard/server_public.key

# Display keys (save these securely)
echo "Server Private Key:"
cat /etc/wireguard/server_private.key
echo "Server Public Key:"
cat /etc/wireguard/server_public.key
```

### Configure WireGuard Interface

**Via UCI:**
```bash
# WireGuard interface
uci set network.wg0=interface
uci set network.wg0.proto='wireguard'
uci set network.wg0.private_key="$(cat /etc/wireguard/server_private.key)"
uci set network.wg0.listen_port='51820'  # Or choose your own UDP port
uci add_list network.wg0.addresses='10.10.10.1/24'

# Commit changes
uci commit network
/etc/init.d/network restart
```

**Via LuCI:**
1. Navigate to **Network → Interfaces**
2. Click "Add new interface"
3. Name: `wg0`
4. Protocol: WireGuard VPN
5. Private Key: (paste from `/etc/wireguard/server_private.key`)
6. Listen Port: `51820`
7. IP Addresses: `10.10.10.1/24`
8. Save and Apply

### Add WireGuard Peer (Client)

**Client generates their own keypair** (during client installation).

When client sends you their **public key**, add peer to router:

**Via UCI:**
```bash
# Add peer
uci add network wireguard_wg0
uci set network.@wireguard_wg0[-1].public_key='CLIENT_PUBLIC_KEY_HERE'
uci set network.@wireguard_wg0[-1].description='client-laptop'
uci add_list network.@wireguard_wg0[-1].allowed_ips='10.10.10.2/32'

# Commit changes
uci commit network
/etc/init.d/network restart
```

**Via LuCI:**
1. Navigate to **Network → Interfaces → wg0**
2. Go to **Peers** tab
3. Add peer:
   - Description: `client-laptop`
   - Public Key: (client's public key)
   - Allowed IPs: `10.10.10.2/32`
   - Persistent Keepalive: `25` (optional, helps with NAT traversal)
4. Save and Apply

**Repeat for each client**, incrementing the IP address (`10.10.10.3`, `10.10.10.4`, etc.).

---

## Part 5: Firewall Configuration

### Create Firewall Zones

**Via LuCI:**
1. Navigate to **Network → Firewall**
2. Go to **General Settings** tab
3. Ensure zones exist:
   - **wan**: Input: reject, Output: accept, Forward: reject
   - **lan**: Input: accept, Output: accept, Forward: accept
4. Add **dmz** zone:
   - Name: `dmz`
   - Input: reject
   - Output: accept
   - Forward: reject
   - Masquerading: disabled
   - Covered networks: `dmz`
5. Add **vpn** zone:
   - Name: `vpn`
   - Input: reject
   - Output: accept
   - Forward: reject
   - Masquerading: disabled
   - Covered networks: `wg0`

**Via UCI:**
```bash
# DMZ zone
uci add firewall zone
uci set firewall.@zone[-1].name='dmz'
uci set firewall.@zone[-1].input='REJECT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='REJECT'
uci add_list firewall.@zone[-1].network='dmz'

# VPN zone
uci add firewall zone
uci set firewall.@zone[-1].name='vpn'
uci set firewall.@zone[-1].input='REJECT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='REJECT'
uci add_list firewall.@zone[-1].network='wg0'

uci commit firewall
/etc/init.d/firewall restart
```

### Configure Firewall Forwardings

**Via UCI:**
```bash
# vpn → dmz (port 11434 only)
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='vpn'
uci set firewall.@forwarding[-1].dest='dmz'

# dmz → wan (outbound internet)
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='dmz'
uci set firewall.@forwarding[-1].dest='wan'

# lan → dmz (admin access)
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='dmz'

uci commit firewall
/etc/init.d/firewall restart
```

**Via LuCI:**
1. Navigate to **Network → Firewall → General Settings**
2. Go to **Zones** section, then **Forwardings** tab
3. Add forwardings:
   - Source: `vpn`, Destination: `dmz`
   - Source: `dmz`, Destination: `wan`
   - Source: `lan`, Destination: `dmz` (optional, admin access)

### Configure Traffic Rules

**Allow WireGuard from WAN:**
```bash
# Via UCI
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-WireGuard'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].dest_port='51820'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].target='ACCEPT'

uci commit firewall
/etc/init.d/firewall restart
```

**Allow VPN → DMZ port 11434:**
```bash
# Via UCI
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-VPN-to-Ollama'
uci set firewall.@rule[-1].src='vpn'
uci set firewall.@rule[-1].dest='dmz'
uci set firewall.@rule[-1].dest_ip='192.168.100.10'
uci set firewall.@rule[-1].dest_port='11434'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].target='ACCEPT'

uci commit firewall
/etc/init.d/firewall restart
```

**Block all other VPN → DMZ traffic** (implicit, zone default is REJECT)

---

## Part 6: Port Forwarding (WAN → Router)

**CRITICAL**: Do NOT forward port 11434 from WAN to DMZ.

Only WireGuard UDP port should be forwarded:

**Via UCI:**
```bash
# This is already handled by the "Allow-WireGuard" rule above
# No additional port forwarding needed
```

Verify no unexpected port forwards:
```bash
# List all port forwards
uci show firewall | grep redirect
```

Should show NO redirects to port 11434.

---

## Part 7: DNS Configuration

### Option A: Use Router as DNS for VPN Clients

**Via UCI:**
```bash
# Advertise router as DNS server to VPN clients
# This happens automatically via DHCP options

# Optional: Configure upstream DNS servers
uci add_list dhcp.@dnsmasq[0].server='1.1.1.1'
uci add_list dhcp.@dnsmasq[0].server='1.0.0.1'

uci commit dhcp
/etc/init.d/dnsmasq restart
```

### Option B: Let Clients Use Their Own DNS

No additional configuration needed. Clients will use their system DNS.

---

## Part 8: Verification and Testing

### Verify WireGuard is Running

```bash
# Check WireGuard interface status
wg show wg0

# Should show:
# - interface: wg0
# - public key: (server public key)
# - private key: (hidden)
# - listening port: 51820
# - peers: (list of configured peers)
```

### Verify Firewall Rules

```bash
# List all firewall rules
iptables -L -n -v

# Check for:
# - WAN → WireGuard UDP port: ACCEPT
# - VPN → DMZ port 11434: ACCEPT
# - VPN → LAN: DROP/REJECT
# - DMZ → LAN: DROP/REJECT
```

### Test from VPN Client

**After client is configured with WireGuard:**

```bash
# Connect to VPN
# (varies by client OS)

# Test connectivity to DMZ server
ping 192.168.100.10  # Should succeed

# Test connectivity to inference port
nc -zv 192.168.100.10 11434  # Should succeed (if server is running)

# Test connectivity to LAN (should fail)
ping 192.168.1.1  # Should timeout or fail

# Test internet access (should fail)
ping 8.8.8.8  # Should timeout or fail
```

### Test from DMZ Server

```bash
# On the AI server (192.168.100.10)

# Test outbound internet (should succeed)
ping 8.8.8.8

# Test access to LAN (should fail)
ping 192.168.1.1  # Should timeout or fail

# Test access to router
ping 192.168.100.1  # Should succeed
```

---

## Part 9: UCI Batch Script (Advanced)

For automated configuration, save this as `/root/setup-ai-router.sh`:

```bash
#!/bin/sh
#
# OpenWrt Router Setup for remote-ollama-proxy
# Usage: ./setup-ai-router.sh
#

set -e

echo "=== OpenWrt Router Setup for remote-ollama-proxy ==="

# 1. Install WireGuard
echo "[1/7] Installing WireGuard packages..."
opkg update
opkg install wireguard-tools luci-proto-wireguard luci-app-wireguard kmod-wireguard

# 2. Generate WireGuard keys
echo "[2/7] Generating WireGuard keys..."
umask 077
wg genkey > /etc/wireguard/server_private.key
wg pubkey < /etc/wireguard/server_private.key > /etc/wireguard/server_public.key

echo "Server Public Key (share with clients):"
cat /etc/wireguard/server_public.key

# 3. Configure DMZ interface
echo "[3/7] Configuring DMZ interface..."
uci set network.dmz=interface
uci set network.dmz.proto='static'
uci set network.dmz.ipaddr='192.168.100.1'
uci set network.dmz.netmask='255.255.255.0'
uci set network.dmz.device='eth1'  # Adjust as needed

# 4. Configure WireGuard interface
echo "[4/7] Configuring WireGuard interface..."
uci set network.wg0=interface
uci set network.wg0.proto='wireguard'
uci set network.wg0.private_key="$(cat /etc/wireguard/server_private.key)"
uci set network.wg0.listen_port='51820'
uci add_list network.wg0.addresses='10.10.10.1/24'

# 5. Configure firewall zones
echo "[5/7] Configuring firewall zones..."
uci add firewall zone
uci set firewall.@zone[-1].name='dmz'
uci set firewall.@zone[-1].input='REJECT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='REJECT'
uci add_list firewall.@zone[-1].network='dmz'

uci add firewall zone
uci set firewall.@zone[-1].name='vpn'
uci set firewall.@zone[-1].input='REJECT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='REJECT'
uci add_list firewall.@zone[-1].network='wg0'

# 6. Configure firewall forwardings
echo "[6/7] Configuring firewall forwardings..."
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='vpn'
uci set firewall.@forwarding[-1].dest='dmz'

uci add firewall forwarding
uci set firewall.@forwarding[-1].src='dmz'
uci set firewall.@forwarding[-1].dest='wan'

uci add firewall forwarding
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='dmz'

# 7. Configure firewall rules
echo "[7/7] Configuring firewall rules..."
uci add firewall rule
uci set firewall.@rule[-1].name='Allow-WireGuard'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].dest_port='51820'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].target='ACCEPT'

uci add firewall rule
uci set firewall.@rule[-1].name='Allow-VPN-to-Ollama'
uci set firewall.@rule[-1].src='vpn'
uci set firewall.@rule[-1].dest='dmz'
uci set firewall.@rule[-1].dest_ip='192.168.100.10'
uci set firewall.@rule[-1].dest_port='11434'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].target='ACCEPT'

# Commit all changes
echo "Committing changes..."
uci commit
/etc/init.d/network restart
/etc/init.d/firewall restart

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Server Public Key (share with clients):"
cat /etc/wireguard/server_public.key
echo ""
echo "Next steps:"
echo "1. Add client peers to WireGuard (see guide)"
echo "2. Configure AI server with static IP 192.168.100.10"
echo "3. Reboot router: reboot"
```

Make executable and run:
```bash
chmod +x /root/setup-ai-router.sh
./root/setup-ai-router.sh
```

---

## Part 10: Maintenance and Troubleshooting

### View Logs

```bash
# System log
logread

# Firewall log
logread | grep firewall

# WireGuard log
logread | grep wireguard

# Real-time log
logread -f
```

### Check WireGuard Status

```bash
# Show WireGuard interface status
wg show

# Show peers with handshake times
wg show wg0

# Show specific peer
wg show wg0 peers
```

### Check Firewall Rules

```bash
# List all rules
iptables -L -v -n

# List NAT rules
iptables -t nat -L -v -n

# Check zone forwardings
uci show firewall | grep zone
uci show firewall | grep forwarding
```

### Test Connectivity

```bash
# From router to DMZ server
ping 192.168.100.10

# From router to internet
ping 8.8.8.8

# Check if port 11434 is open on DMZ server (from router)
nc -zv 192.168.100.10 11434
```

### Common Issues

**Issue: VPN clients cannot connect**
- Check WireGuard UDP port is open on WAN firewall
- Verify client has correct server public key
- Check router WAN IP hasn't changed (use DDNS if dynamic)
- Verify WireGuard service is running: `/etc/init.d/network status`

**Issue: VPN clients cannot reach DMZ server**
- Check firewall rule allows VPN → DMZ port 11434
- Verify DMZ server is running and bound to 192.168.100.10
- Check routing: `ip route` on router
- Test from router: `nc -zv 192.168.100.10 11434`

**Issue: DMZ server cannot reach internet**
- Check firewall forwarding: DMZ → WAN
- Check NAT masquerading on WAN zone
- Test from router: `ping 8.8.8.8`
- Check upstream DNS

**Issue: VPN clients can reach LAN (should not happen)**
- Check firewall: VPN → LAN should be REJECT
- Verify no accidental forwarding rules
- Check zone assignments: `uci show firewall.@zone`

---

## Security Best Practices

1. **Change default passwords** - Set strong root password immediately
2. **Disable WAN SSH** - Only allow SSH from LAN
3. **Keep OpenWrt updated** - Apply security patches regularly
4. **Use strong WireGuard keys** - Never share private keys
5. **Monitor logs** - Regularly check for unexpected activity
6. **Rotate keys periodically** - Generate new WireGuard keys every 6-12 months
7. **Limit LAN → DMZ** - Only allow admin access when needed
8. **Document changes** - Keep a log of configuration modifications
9. **Backup configuration** - Save UCI config regularly: `sysupgrade -b /tmp/backup.tar.gz`
10. **Test after changes** - Always verify firewall rules after modifications

---

## Backup and Restore

### Backup Configuration

```bash
# Create backup
sysupgrade -b /tmp/backup-$(date +%Y%m%d).tar.gz

# Download backup (from admin machine)
scp root@192.168.1.1:/tmp/backup-*.tar.gz ~/openwrt-backups/
```

### Restore Configuration

```bash
# Upload backup
scp backup.tar.gz root@192.168.1.1:/tmp/

# Restore (preserves installed packages)
sysupgrade -r /tmp/backup.tar.gz

# Reboot
reboot
```

---

## Appendix: Configuration Summary

**Network Interfaces:**
- WAN: DHCP or static (ISP-provided)
- LAN: 192.168.1.1/24
- DMZ: 192.168.100.1/24
- VPN: 10.10.10.1/24 (WireGuard)

**AI Server:**
- IP: 192.168.100.10 (static)
- Service: Ollama on port 11434

**Firewall Zones:**
- wan: reject all except WireGuard UDP
- lan: accept (admin access)
- dmz: reject inbound, allow outbound
- vpn: reject except to DMZ port 11434

**WireGuard:**
- Server: 10.10.10.1
- Listen Port: 51820 (UDP)
- Clients: 10.10.10.2, 10.10.10.3, ... (increment for each peer)

---

## Support and Further Reading

- **OpenWrt Documentation**: https://openwrt.org/docs/start
- **WireGuard Documentation**: https://www.wireguard.com/
- **OpenWrt Firewall Guide**: https://openwrt.org/docs/guide-user/firewall/start
- **OpenWrt UCI Documentation**: https://openwrt.org/docs/guide-user/base-system/uci

For project-specific issues, see main repository documentation.
