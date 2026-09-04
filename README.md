# MicoScan

Android mobile application for arbuscular mycorrhizal fungi (AMF) 
detection as a binary colonisation indicator (colonised / not colonised).
Built with Flutter and TensorFlow Lite for offline inference.

## Features

- Local offline inference via TFLite (25 MB model)
- Remote inference via REST API (FastAPI backend)
- Grad-CAM explainability heatmaps
- Binary colonisation report (SI/NO)
- Per-class structure count (arbuscules, vesicles, hyphae)
- Analysis history

## Architecture

- **Framework:** Flutter (Android)
- **Inference (offline):** TensorFlow Lite — dynamic-range quantisation
- **Inference (remote):** REST API → micoscan_backend
- **Minimum Android version:** Android 8.0
- **Tested device:** Samsung Galaxy A14, Android 14

## Paper

This repository was used in the following LNCS submission:

> *Deep Learning-Based Model for the Classification and Segmentation
> of Microscopic Images of Arbuscular Mycorrhizae in a Mobile
> Application*

| Item | Value |
|---
