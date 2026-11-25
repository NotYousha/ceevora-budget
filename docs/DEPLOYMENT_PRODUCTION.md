# Production deployment (OCI, Oracle Linux 9 / Ubuntu 24.04)

**None of these steps has been executed.** Treat this as a runbook to verify in a staging environment first.

## Topology
* Public load balancer or Nginx (443 only) -> backend VM in a private subnet -> customer PDBs over a private
  subnet / Service Gateway. Port 1521 is never exposed publicly (security list / NSG allows only the backend subnet).
* One backend serves all tenants; each tenant entry in `tenants.json` points at its own PDB service.

## Install
```bash
sudo useradd --system --home /opt/ceevora-budget ceevora
sudo mkdir -p /opt/ceevora-budget /etc/ceevora-budget /var/log/ceevora-budget
sudo cp -r backend /opt/ceevora-budget/ && sudo cp -r frontend/build/web /opt/ceevora-budget/web
cd /opt/ceevora-budget/backend && sudo python3.12 -m venv .venv && sudo .venv/bin/pip install -r requirements.txt
sudo cp .env.example /etc/ceevora-budget/env      # fill from OCI Vault; chmod 600, owner ceevora
sudo cp tenants.json /etc/ceevora-budget/tenants.json   # REMOVE the DEMO entry; add real tenants
sudo chown -R ceevora:ceevora /opt/ceevora-budget /var/log/ceevora-budget
sudo cp deployment/systemd/ceevora-budget.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now ceevora-budget
sudo cp deployment/nginx/ceevora-budget.conf /etc/nginx/conf.d/ && sudo nginx -t && sudo systemctl reload nginx
# Oracle Linux: sudo setsebool -P httpd_can_network_connect 1 ; open 443 in firewalld
```

## Database (per customer PDB)
1. Map the adapter views (docs/MAPPING_GUIDE.md), then as the schema owner run `install_production.sql`.
2. DBA creates the least-privilege runtime user, grants `CEEVORA_BUDGET_APP`, adds synonyms.
3. Store that user's password in OCI Vault; reference it by env var in `/etc/ceevora-budget/env`.

## Operations
* **Health:** `curl -s http://127.0.0.1:8000/health` returns 200 with each tenant "ok", 503 if any DB is down.
* **Logs:** `journalctl -u ceevora-budget` (failed logins and permission changes are logged with username).
* **Backups:** budget tables live in the customer PDB, so they are covered by its RMAN / Autonomous backups. Before
  upgrades also take `expdp` of the BUDGET_* tables.
* **Upgrades:** stop the service, back up, run `database/oracle/upgrade/U*.sql` in order, deploy the new backend and
  web build, start, check `/health`. **Rollback:** restore the previous release folder and run the matching
  `rollback/R*.sql` (full removal: `rollback/99_rollback_budget.sql`, which deletes all budget data).
* **Token secret rotation:** change `JWT_SECRET`, restart; all users sign in again.
* Purge `BUDGET_IDEMPOTENCY` rows older than 7 days with a scheduled job.
