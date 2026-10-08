# M-AIRMap — Maritime AI-driven RF Map

> Runs on the Jetson Orin Nano (lab). Code at `~/m-airmap/` on the device.
> Full context briefing: see `docs/m-airmap-context-briefing.md`

## What this component does

Predicts cellular RSRP coverage over Singapore's southern waters using a U-Net
trained on synthetic 3-ray propagation data, calibrated against real scanner
measurements from a professional campaign (17 Jan 2025).

## Research contribution

First application of deep-learning radio-map prediction to **maritime**
environments. All prior work (AIRMap, RadioUNet, DeepREM) targets urban.

## Current accuracy

- MAE: 7.28 dB · Median error: 5.9% · Test points: 159,320
- Calibration: `RSRP_cal = 4.592 × RSRP_pred + 127.20`
- Platform: Jetson Orin Nano GPU, ~4.5 min training

## Critical: known issues before presenting

1. Synthetic BS positions include open sea (should be coastline-only)
2. Training uses 1 BS per sample; inference uses 30
3. BS locations are heuristic, not surveyed
4. Weather module is a stub (static 28°C/80%/calm)
5. Sionna RT needs x86_64 (Jetson is aarch64)

Read the full list in the main README section 5 or `docs/m-airmap-context-briefing.md` section 7.

## Design principle

Every module is swappable. `ModuleState.is_placeholder` propagates to the UI.
**Never present placeholder-derived output as measured data.**

## How to run

```bash
cd ~/m-airmap
rm data/synthetic/dataset.npz   # if propagation params changed
python3 -m model.train
python3 push_prediction.py      # pushes to server viewer
```
