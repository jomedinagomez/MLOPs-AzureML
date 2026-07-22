FROM python:3.11-slim-trixie

# Install the scoring script's native and Python runtime dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends libgomp1 \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir --upgrade \
    pip \
    setuptools \
    "wheel>=0.46.2" \
    "jaraco.context>=6.1.0"

RUN pip install --no-cache-dir \
    azureml-inference-server-http==1.5.1 \
    scikit-learn==1.2.2 \
    joblib==1.5.2 \
    numpy==1.26.4 \
    pandas

# Clear the base image entrypoint so our CMD runs directly
ENTRYPOINT []

# Start the AzureML inference server against the scoring script that lives INSIDE
# the mounted model asset ($AZUREML_MODEL_DIR). The if/else handles both mount
# layouts: folder name preserved (model-1/...) vs flattened (...).
CMD ["sh", "-c", "if [ -f \"$AZUREML_MODEL_DIR/model-1/onlinescoring/score_original.py\" ]; then exec azmlinfsrv --entry_script \"$AZUREML_MODEL_DIR/model-1/onlinescoring/score_original.py\" --model_dir \"$AZUREML_MODEL_DIR/model-1/model\" --port 5001; else exec azmlinfsrv --entry_script \"$AZUREML_MODEL_DIR/onlinescoring/score_original.py\" --model_dir \"$AZUREML_MODEL_DIR/model\" --port 5001; fi"]
