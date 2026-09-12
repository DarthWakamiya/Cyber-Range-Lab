#!/bin/bash
# inject-logs.sh
# Injects a simulated "Cookie Reuse & MFA Bypass" attack sequence into
# /opt/admin/logs so the Blue Team has realistic forensic evidence to
# analyze without needing to actually run the Red Team attack live.

set -e

LOG_DIR="${LOG_DIR:-/opt/admin/logs}"
mkdir -p "$LOG_DIR"

ACCESS_LOG="$LOG_DIR/access.log"
ERROR_LOG="$LOG_DIR/error.log"

DATE="$(date +%d/%b/%Y)"       # e.g. 11/Sep/2026
EXFIL_B64="UEhBTlRPTUdSSUR7QkxVRV9MMGdfSHVudDNyX000c3Qzcn0}"

echo "[*] Injecting baseline (legitimate) admin traffic..."
echo "192.168.1.100 - - [${DATE}:18:49:02 +0700] \"GET /dashboard HTTP/1.1\" 200 \"-\" \"Mozilla/5.0 (X11; Linux x86_64)\"" >> "$ACCESS_LOG"
echo "192.168.1.100 - - [${DATE}:18:49:40 +0700] \"GET /login HTTP/1.1\" 200 \"-\" \"Mozilla/5.0 (X11; Linux x86_64)\"" >> "$ACCESS_LOG"

echo "[*] Injecting attacker recon..."
echo "10.10.14.50 - - [${DATE}:18:49:55 +0700] \"GET / HTTP/1.1\" 200 \"-\" \"Mozilla/5.0\"" >> "$ACCESS_LOG"
echo "10.10.14.50 - - [${DATE}:18:50:02 +0700] \"GET /robots.txt HTTP/1.1\" 200 \"-\" \"Mozilla/5.0\"" >> "$ACCESS_LOG"

echo "[*] Injecting first WAF block (blocked <script> attempt)..."
echo "10.10.14.50 - - [${DATE}:18:50:15 +0700] \"POST /api/feedback HTTP/1.1\" 403 \"-\" \"Mozilla/5.0\"" >> "$ACCESS_LOG"
echo "[${DATE//\//-} 18:50:15] [CRITICAL] WAF blocked <script> payload from 10.10.14.50" >> "$ERROR_LOG"

echo "[*] Injecting successful WAF bypass (svg onload XSS) + exfiltration..."
echo "10.10.14.50 - - [${DATE}:18:50:47 +0700] \"POST /api/feedback HTTP/1.1\" 200 \"-\" \"Mozilla/5.0\"" >> "$ACCESS_LOG"
echo "10.10.14.50 - - [${DATE}:18:51:55 +0700] \"GET /dashboard HTTP/1.1\" 200 \"-\" \"Mozilla/5.0\" xff=\"${EXFIL_B64}\"" >> "$ACCESS_LOG"
echo "[${DATE//\//-} 18:51:55] [CRITICAL] Cookie reuse detected: adm_sess_* replayed from untrusted source IP 10.10.14.50" >> "$ERROR_LOG"

echo "[*] Injecting anomaly / bypass detection entry..."
echo "[${DATE//\//-} 18:53:10] [CRITICAL] Authentication bypass anomaly - /api/verify-mfa was never reached by session-bearing request from 10.10.14.50" >> "$ERROR_LOG"

echo "[+] Log injection complete."
echo "    Access log: $ACCESS_LOG"
echo "    Error log:  $ERROR_LOG"
