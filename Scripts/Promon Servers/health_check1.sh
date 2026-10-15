#!/usr/bin/env bash

# Linux System Details / Health Check
# Supports Ubuntu, Oracle Linux, and RHEL
# Usage: ./health_check.sh [-n|--dry-run]

set -u

DRY_RUN=false
REPORT_DIR="./reports"

usage() {
    echo "Usage: $0 [-n|--dry-run] [-h|--help]"
    echo "  -n, --dry-run  Display planned checks without executing them"
    echo "  -h, --help     Display usage"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: Unknown option: $1"; usage; exit 2 ;;
    esac
    shift
done

HOST=$(hostname -s 2>/dev/null || echo "unknown")
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
REPORT="${REPORT_DIR}/${HOST}_health_${TIMESTAMP}.txt"

if [[ "$DRY_RUN" == false ]]; then
    mkdir -p "$REPORT_DIR" || {
        echo "ERROR: Cannot create report directory: $REPORT_DIR"
        exit 1
    }
    # Keep output visible in Semaphore and save it to a report.
    exec > >(tee "$REPORT") 2>&1
fi

echo "=================================================="
echo "        LINUX SYSTEM HEALTH CHECK"
echo "=================================================="
echo "Hostname : $HOST"
echo "Date     : $(date)"
echo "Dry Run  : $DRY_RUN"
echo "Report   : $REPORT"
echo "=================================================="

run_check() {
    local description="$1"
    shift

    echo
    echo "--------------------------------------------------"
    echo "CHECK: $description"
    echo "COMMAND:"

    printf '%q ' "$@"
    echo

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] Command not executed."
        return 0
    fi

    "$@" 2>&1 || {
        local rc=$?
        echo "[WARNING] Check returned exit code: $rc"
    }
}

run_check "Operating system" \
    bash -c 'cat /etc/os-release'

run_check "Hostname and kernel" \
    bash -c 'hostnamectl 2>/dev/null || uname -a'

run_check "Uptime and load average" \
    bash -c 'uptime; cat /proc/loadavg'

run_check "CPU details" \
    lscpu

run_check "Memory and swap usage" \
    free -h

run_check "Filesystem usage" \
    df -hT

run_check "Block devices and mount points" \
    lsblk

run_check "Inode usage" \
    df -ih

run_check "Network interfaces and IP addresses" \
    ip -br address

run_check "Network routes" \
    ip route

run_check "Listening ports" \
    ss -lntup

run_check "Failed systemd services" \
    systemctl --failed --no-pager

run_check "Running services" \
    systemctl list-units --type=service --state=running --no-pager

run_check "Top CPU-consuming processes" \
    bash -c 'ps -eo pid,ppid,user,%cpu,%mem,comm --sort=-%cpu | head -16'

run_check "Top memory-consuming processes" \
    bash -c 'ps -eo pid,ppid,user,%cpu,%mem,comm --sort=-%mem | head -16'

run_check "Recent system journal messages" \
    journalctl -n 50 --no-pager

run_check "Recent kernel messages" \
    bash -c 'dmesg --ctime 2>&1 | tail -30'

run_check "Important agent service status" \
    bash -c '
    for service in \
        ssh sshd \
        zabbix-agent zabbix-agent2 \
        rapid7-insight-agent \
        mdatp \
        azcmagent \
        prometheus-node-exporter
    do
        if systemctl list-unit-files "$service.service" \
            --no-legend 2>/dev/null | grep -q "$service.service"; then
            systemctl is-active "$service.service" 2>/dev/null \
                || true
            printf "%s: " "$service"
            systemctl is-active "$service.service" 2>/dev/null \
                || true
        fi
    done
    '

echo
echo "=================================================="
echo "SYSTEM HEALTH CHECK COMPLETED"
echo "=================================================="

if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run completed. No checks were executed."
    echo "No report file was created."
else
    echo "Report saved to: $REPORT"
fi
