from pathlib import Path
import json

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier


ROOT = Path(__file__).resolve().parent
MODEL_PATH = ROOT / "model/customer_model.joblib"
REQUEST_PATH = ROOT / "sample-request.json"

rng = np.random.default_rng(42)
row_count = 1000

training_data = pd.DataFrame(
    {
        "login_ts": rng.integers(0, 2, row_count),
        "device_type": rng.integers(0, 5, row_count),
        "os": rng.integers(0, 7, row_count),
        "browser": rng.integers(0, 6, row_count),
        "location_country": rng.integers(0, 12, row_count),
        "location_region": rng.integers(0, 8, row_count),
        "login_result": rng.integers(0, 2, row_count),
        "prior_fraud_flag": rng.choice([0, 1], row_count, p=[0.9, 0.1]),
        "prior_payments_count": rng.integers(0, 50, row_count),
        "avg_payment_amount": rng.uniform(10, 1000, row_count),
        "device_age_days": rng.integers(0, 1500, row_count),
        "device_changes_count": rng.integers(0, 8, row_count),
        "login_hour": rng.integers(0, 24, row_count),
        "login_dayofweek": rng.integers(0, 7, row_count),
        "device_age_bucket": rng.integers(0, 6, row_count),
    }
)

risk_score = (
    3 * training_data["prior_fraud_flag"]
    + 2 * (training_data["login_result"] == 0)
    + (training_data["device_age_days"] < 30)
    + (training_data["device_changes_count"] >= 4)
    + (training_data["avg_payment_amount"] >= 500)
    + (training_data["login_hour"] < 5)
)
target = (risk_score >= 3).astype(int)

model = RandomForestClassifier(n_estimators=100, random_state=42)
model.fit(training_data, target)
joblib.dump(model, MODEL_PATH, compress=3)

request = json.loads(REQUEST_PATH.read_text(encoding="utf-8"))
sample = pd.DataFrame(request["instances"]).loc[:, model.feature_names_in_]

print(f"Saved: {MODEL_PATH}")
print(f"Features: {model.feature_names_in_.tolist()}")
print(f"Class probabilities: {model.predict_proba(sample).tolist()}")