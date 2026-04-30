#!/bin/bash
# =============================================================================
# RPi k3s Cluster Performance Tuning Script
# Tested on: Debian Trixie, latest bootloader, RPi 4B
#
# Node layout:
#   headnode-ip — 8GB head node (k3s server + NFS) — conservative 1800MHz
#   node01-ip — 8GB worker — full 2000MHz
#   node02-ip — 8GB worker — full 2000MHz
#   node03-ip — 8GB worker — full 2000MHz
#   node04-ip — 8GB worker — full 2000MHz
#   node05-ip — 4GB worker — full 2000MHz
#   node06-ip — 4GB worker — full 2000MHz
#   node08-ip — 4GB worker — full 2000MHz
#   node09-ip — 4GB worker — full 2000MHz
#   node10-ip — 4GB worker — full 2000MHz
#   node11-ip — 2GB worker (capacity: min) — conservative 1800MHz
#
# Run AFTER cordoning and draining the cluster.
# Script ends by rebooting all nodes — head node last.
# =============================================================================

set -e

WORKERS="node01-ip node02-ip node02-ip node03-ip ......"
MIN_NODE="node11-ip"
HEAD="headnode-ip"

# =============================================================================
echo "=== [1/7] Applying boot config to 4GB/8GB workers (2000MHz) ==="
# =============================================================================
for ip in $WORKERS; do
  echo "  Configuring $ip..."
  sh pi@$ip "sudo tee -a /boot/firmware/config.txt << 'CONF'

# Performance tuning — Trixie + latest bootloader
arm_freq=2000
arm_freq_min=600
over_voltage_delta=50000
gpu_mem=16
dtoverlay=disable-wifi
dtoverlay=disable-bt
hdmi_blanking=2
CONF"
done

# =============================================================================
echo "=== [2/7] Applying boot config to 2GB worker (1800MHz) ==="
# =============================================================================
ssh pi@$MIN_NODE "sudo tee -a /boot/firmware/config.txt << 'CONF'

# Performance tuning — Trixie + latest bootloader (conservative)
arm_freq=1800
arm_freq_min=600
over_voltage_delta=25000
gpu_mem=16
dtoverlay=disable-wifi
dtoverlay=disable-bt
hdmi_blanking=2
CONF"

# =============================================================================
echo "=== [3/7] Applying boot config to head node (1800MHz) ==="
# =============================================================================
sudo tee -a /boot/firmware/config.txt << 'CONF'

# Performance tuning — Trixie + latest bootloader (conservative)
arm_freq=1800
arm_freq_min=600
over_voltage_delta=25000
gpu_mem=16
dtoverlay=disable-wifi
dtoverlay=disable-bt
hdmi_blanking=2
CONF

# =============================================================================
echo "=== [4/7] Applying kernel parameters to all nodes ==="
# =============================================================================
SYSCTL_CONF="net.core.rmem_max=2500000
net.core.wmem_max=2500000
net.core.netdev_max_backlog=5000
net.ipv4.tcp_fastopen=3
vm.dirty_ratio=15
vm.dirty_background_ratio=5
vm.swappiness=1
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=512"

for ip in $WORKERS $MIN_NODE; do
  echo "  Applying sysctl to $ip..."
  ssh pi@$ip "echo '$SYSCTL_CONF' | sudo tee /etc/sysctl.d/99-k3s.conf && sudo sysctl -p /etc/sysctl.d/99-k3s.conf"
done

echo "  Applying sysctl to head node..."
echo "$SYSCTL_CONF" | sudo tee /etc/sysctl.d/99-k3s.conf
sudo sysctl -p /etc/sysctl.d/99-k3s.conf

# =============================================================================
echo "=== [5/7] Disabling unused services on all nodes ==="
# =============================================================================
for ip in $WORKERS $MIN_NODE; do
  echo "  Disabling services on $ip..."
  ssh pi@$ip "sudo systemctl disable --now avahi-daemon bluetooth wpa_supplicant nfs-blkmap 2>/dev/null || true"
done

echo "  Disabling services on head node..."
sudo systemctl disable --now avahi-daemon bluetooth wpa_supplicant nfs-blkmap 2>/dev/null || true

# =============================================================================
echo "=== [6/7] Configuring journals ==="
# =============================================================================
# Workers — volatile (no persistent logs, saves SD card writes)
for ip in $WORKERS $MIN_NODE; do
  echo "  Setting volatile journal on $ip..."
  ssh pi@$ip "sudo mkdir -p /etc/systemd/journald.conf.d && \
    echo '[Journal]
Storage=volatile
RuntimeMaxUse=64M
RuntimeMaxFileSize=16M
Compress=yes' | sudo tee /etc/systemd/journald.conf.d/99-volatile.conf && \
    sudo systemctl restart systemd-journald"
done

# Head node — persistent (keeps logs for debugging)
echo "  Setting persistent journal on head node..."
sudo mkdir -p /etc/systemd/journald.conf.d
echo '[Journal]
Storage=persistent
SystemMaxUse=200M
SystemMaxFileSize=50M
Compress=yes' | sudo tee /etc/systemd/journald.conf.d/99-persistent.conf
sudo systemctl restart systemd-journald

# =============================================================================
echo "=== Verifying config on sample nodes ==="
# =============================================================================
echo "--- node01 (expect arm_freq=2000) ---"
ssh pi@node01-ip "tail -10 /boot/firmware/config.txt"
echo "--- node11 (expect arm_freq=1800) ---"
ssh pi@node11-ip "tail -10 /boot/firmware/config.txt"
echo "--- Head node (expect arm_freq=1800) ---"
tail -10 /boot/firmware/config.txt

# =============================================================================
echo "=== [7/7] Rebooting cluster (workers first, head node last) ==="
# =============================================================================
for ip in $WORKERS $MIN_NODE; do
  echo "  Rebooting $ip..."
  ssh pi@$ip "sudo reboot" 2>/dev/null || true
done

echo "  Waiting 90 seconds for workers to come back up..."
sleep 90

echo "  Rebooting head node now..."
sudo reboot
