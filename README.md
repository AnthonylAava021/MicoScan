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
|---|---|
| Commit | `1c7584d` |
| Tag | v1.0.0 |
| DOI | https://doi.org/10.5281/zenodo.22293663 |
| On-device latency | 120 ms (Samsung Galaxy A14, Android 14) |
| Backend | https://github.com/AnthonylAava021/micoscan_backend |
| Dataset | https://www.kaggle.com/datasets/oscarchancay67/dataset-micoscan |

## Model Performance

| Class | F1 | mIoU |
|---|---|---|
| Arbuscule | **0.863** | 0.972 |
| Vesicle | 0.521 | 0.961 |
| Hypha | 0.146 | 0.798 |
| **Macro** | **0.510** | **0.910** |

## License

MIT
