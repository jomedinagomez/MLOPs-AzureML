# Customer H2O BYOM Intake

This folder supports the customer bring-your-own-model scenario for two H2O-3 artifact formats:

| Format | Created with | Runtime loader | Version rule |
| --- | --- | --- | --- |
| Native H2O binary | `h2o.save_model()` | `h2o.load_model()` | Producer and scoring-runtime H2O versions must match |
| Portable MOJO ZIP | `model.download_mojo()` | `h2o.upload_mojo()` | Producer and scoring-runtime versions are recorded separately and validated by scoring |

The notebooks never retrain, convert, or silently upgrade a supplied model. The repository-root `.venv` packages metadata only; notebook 03 generates the customer-specific Azure ML environment that actually loads the model.

## Prepopulated Profiles

Notebook `01_package_and_validate_model.ipynb` begins with one selector:

```python
CUSTOMER_MODEL_PROFILE = "mojo"
```

Set it to `"mojo"` or `"binary"`. Each value selects one predefined folder:

```text
customer_bundle/
  README.md
   profiles/
      mojo/
         profile.json
         prostate-gbm.mojo.zip
         golden_input.csv
         golden_expected.csv
      binary/
         profile.json
         taxi-fare-gbm
         golden_input.csv
         golden_expected.csv
```

The MOJO example is an Apache-2.0 H2O-3 test artifact:

- Repository: `https://github.com/h2oai/h2o-3`
- Revision: `ce08492c71e6f2fe9ce902cd82b1e7828ca3b1f6`
- Source path: `h2o-genmodel/src/test/resources/hex/genmodel/algos/gbm/gbm_variable_importance.zip`
- Producer H2O metadata: `3.32.0.99999`
- MOJO format: `1.40`
- Workshop scoring runtime: H2O `3.46.0.12`, Python `3.12`, Java `17`

The retained license is `workshop/licenses/Apache-H2O-3.txt`.

## Replace the Example with Customer Files

Work only in the folder selected in notebook `01`:

1. Remove the example model artifact.
2. Add exactly one native binary or MOJO ZIP.
3. Replace both golden CSVs, or remove both when no golden dataset is available.
4. Update that folder's `profile.json`.
5. Run notebook `01` and review the detected format and staged manifest.

The notebook rejects an empty profile, multiple model artifacts, a format that does not match the selected folder, or only one golden CSV. It copies the selected files to ignored `outputs/h2o_customer_bundle/`; notebooks `02` through `05` consume only that staged bundle.

Customer artifacts and datasets must not be committed. Restore the supplied examples before publishing repository changes.

## Profile Contract

Both `profile.json` files contain:

- `model_name` and `environment_name`: profile-specific Azure ML asset names.
- `endpoint_name` and `deployment_name`: the profile's online serving slot.
- `input_data_name` and `experiment_name`: the profile's batch-scoring resources.
- `model_version`: bundle metadata; Azure ML assigns the asset version.
- `runtime_h2o_version`, `python_version`, and `java_version`.
- `h2o_pip_spec`: optional immutable package requirement; blank defaults to `h2o==<runtime_h2o_version>`.
- `categorical_features`: an optional subset of the model features.

For a MOJO, notebook `01` reads producer H2O version, MOJO version, feature order, and target directly from `model.ini`. Optional `features` and `target` values in `profile.json` are treated as assertions.

For a native binary, `profile.json` must additionally provide:

- `model_h2o_version`
- `features`
- `target`

Native binaries require matching producer and runtime H2O versions. MOJOs may use a separately selected compatible runtime.

## Optional Golden Validation

Golden data is detected by filename. The selected profile must contain both files or neither:

```text
golden_input.csv
golden_expected.csv
```

Only validation policy remains in `workshop/.env`:

```dotenv
H2O_CUSTOMER_RUN_GOLDEN_VALIDATION=true
H2O_CUSTOMER_REQUIRE_GOLDEN_VALIDATION=false
```

Rules:

- When present, `golden_input.csv` must contain the exact ordered feature columns.
- `golden_expected.csv` must contain one `predict` column and the same non-zero row count.
- Notebook 01 validates structure and checksums without importing H2O.
- `H2O_CUSTOMER_RUN_GOLDEN_VALIDATION=false` keeps the fixtures in the bundle but skips runtime parity.
- Notebook 04 runs prediction parity in the generated Azure ML runtime when enabled.
- When golden files are absent, packaging, registration, deployment, and batch scoring remain available.
- Setting `H2O_CUSTOMER_REQUIRE_GOLDEN_VALIDATION=true` requires both files, forces validation to remain enabled, and blocks traffic promotion until parity passes.

The offline scoring input is separate:

```dotenv
H2O_CUSTOMER_SCORING_INPUT_PATH=<csv-to-score>
```

Leave it blank to score the selected profile's golden input. A profile without golden data requires an explicit scoring input path. Production batch data is not validation evidence.

## Notebook-Owned Runtime Files

Run the notebooks in order:

1. `01_package_and_validate_model.ipynb`
   - Selects the `mojo` or `binary` profile.
   - Detects native binary versus MOJO.
   - Detects whether the canonical golden pair exists.
   - Reads MOJO `model.ini` when applicable.
   - Stages and validates `outputs/h2o_customer_bundle/`.
   - Does not import H2O or start Java.
2. `02_register_model.ipynb`
   - Registers the packaged bundle and its validation state.
3. `03_create_environment.ipynb`
   - Generates the Conda file under `outputs/generated/h2o_customer/environment/`.
   - Registers the selected Python, Java, and H2O runtime.
4. `04_deploy_online_endpoint.ipynb`
   - Generates `score.py` under `outputs/generated/h2o_customer/online/`.
   - Uses `h2o.load_model()` for native binaries and `h2o.upload_mojo()` for MOJOs.
   - Runs optional zero-traffic golden parity before promotion.
5. `05_submit_scoring_pipeline.ipynb`
   - Generates the dual-format batch scorer, component YAML, and pipeline YAML under `outputs/generated/h2o_customer/batch/`.
   - Submits the independently versioned scoring input.

Generated runtime files are intentionally ignored by Git.

## Change and Safety Rules

- Replace files only in the selected profile directory.
- Never place credentials in `profile.json`, a model bundle, or `.env`.
- Keep exactly one model artifact in each profile.
- Remove both golden files when the customer has no golden dataset.
- Azure ML assigns immutable asset versions; downstream notebooks resolve the selected profile's latest assets.
- Never store credentials in the bundle or `.env`.
- Review every generated file and Azure safety switch before enabling mutation.
