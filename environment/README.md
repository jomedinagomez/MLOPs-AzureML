# Environments

Conda environment specifications for scoring and training runs reside here. Both environments target Python 3.9 today—keep dependencies compatible with the Azure ML base images and update the CI tooling only if you intentionally change that major version.

- `train/` contains the training conda spec and the `additional_req.txt` file used by pipelines.
- `score/` defines the online inference environment.
