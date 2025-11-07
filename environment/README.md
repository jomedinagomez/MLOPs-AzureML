# Environments

Conda environment specifications for scoring and training runs reside here. Keep dependency versions aligned with the Python runtime used in GitHub Actions (currently 3.13) and the Azure ML compute images.

- `train/` contains the training conda spec and extra requirements file.
- `score/` defines the online inference environment.
