# Server — Shore-side Data Store and Viewer

> Runs on DigitalOcean at `157.230.47.109`. SSH: `root@157.230.47.109`.

## What this component does

Central data store and visualization for all three workstreams:
- Receives telemetry from the RPi gateway (measurements, link_stats, tier_traffic)
- Receives predictions from the Jetson (predicted_maps)
- Serves Grafana dashboards and the M-AIRMap web viewer

## Services

| Service | Port | Purpose |
|---|---|---|
| Flask API | 5000 | Data ingest + M-AIRMap viewer |
| Grafana | 3000 | Operational dashboards |
| SQLite | file | `/var/lib/grafana/maritime.db` |

## Database schema

See `schema.sql` for the full reference. Key tables:

- `measurements` — RF telemetry (device_id, RSRP, SINR, PCI, cell_id, band)
- `link_stats` — per-interface connectivity (up/down, RTT, loss)
- `tier_traffic` — nftables counter snapshots per tier
- `predicted_maps` — M-AIRMap grid predictions

## Grafana

- Main dashboard: `maritime-v3`
- Demo: `jason-marine-demo-v2`
- Datasource: `frser-sqlite-datasource` with `timeColumns: ["time","ts"]`

Dashboard JSON exports should be saved in `grafana/` for version control.

## File layout on server

```
/home/maritime/app.py              # Flask application
/home/maritime/static/             # M-AIRMap viewer HTML
/var/lib/grafana/maritime.db       # SQLite database
```

## Gotchas

- Grafana password is in plaintext in `add_tier_panels.py` — rotate if shared
- `timeColumns` in datasource config is critical and non-obvious
- M-AIRMap viewer must be same-origin (HTTP) — external HTTPS hosting fails on
  mixed-content blocking
