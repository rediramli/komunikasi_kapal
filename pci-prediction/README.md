# PCI Prediction — Maritime Cell Handover Prediction

> Early stage. Files being organized.

## What this component does

Predicts which Physical Cell ID (PCI) a vessel will be served by, using
position and RF history features. Target: proactive handover management for
maritime autonomous surface vessels.

## Key findings so far

- Boundary accuracy (71–80%) is significantly lower than non-boundary (97–99.6%)
- `prev_pci` is the strongest predictor (SHAP 0.049) — memory effect dominates
- Cross-campaign generalization drops to 49% without history features
- Scanner data covers 53–95% of vessel PCI observations depending on campaign

## What changed (Oct 2026)

Gateway operations revealed that **RF-only prediction is insufficient**:
- A RUT241 modem camped on a Malaysian cell (MCC 502) while in Singapore waters
- RSRP/SINR were measurable — a pure RF model would predict this cell as usable
- The cell rejected the SIM: "EPS services not allowed in this PLMN"

**New direction:** PLMN identity, registration state, and reject cause must be
first-class features. This is a maritime-specific insight — land models rarely
encounter cross-border cell selection from within domestic territory.

## Data sources

- Scanner campaigns: MC1, MC2, MC3 (professional R&S TSMA network scanner)
- `scanner_5g.csv`: 199,149 rows, 422 unique PCIs
- `scanner_4g.csv`: 126,141 rows, 226 unique PCIs
- Live drive-test: `measurements` table on the server (device_id: DRIVETEST)

## Status

Files not yet organized into this repo structure. To be developed further
incorporating gateway operational learnings and PLMN state as features.
