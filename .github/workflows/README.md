# GitHub Workflows

Reusable automation lives here. Each YAML file describes a GitHub Actions pipeline:

- `integration-ml-ci.yml` validates changes on the integration branch, running unit tests, compare, and optional dev deployment jobs.
- `prod-ml-release.yml` promotes vetted models into the production workspace and gates merges into `main`.

When creating new workflows, follow the existing login pattern (service principal JSON) and document any new repository secrets or variables in the main repository README (CI/CD section).
