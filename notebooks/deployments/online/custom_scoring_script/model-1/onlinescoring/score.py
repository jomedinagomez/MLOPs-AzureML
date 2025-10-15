import os
import logging
import json
import numpy
import pandas as pd
from azureml.ai.monitoring import Collector
import joblib


def init():
    """
    This function is called when the container is initialized/started, typically after create/update of the deployment.
    You can write the logic here to perform init operations like caching the model in memory
    """
    global model, model_path, inputs_collector, outputs_collector
    
    # AZUREML_MODEL_DIR is an environment variable created during deployment.
    # It is the path to the model folder (./azureml-models/$MODEL_NAME/$VERSION)
    model_path = os.getenv("AZUREML_MODEL_DIR")
    model_path = os.path.join(
        os.getenv("AZUREML_MODEL_DIR"), "sklearn_regression_model.pkl"
    )
    
    # Initialize data collectors for production inference logging
    # Using standard names 'model_inputs' and 'model_outputs' for seamless model monitoring
    inputs_collector = Collector(name='model_inputs')
    outputs_collector = Collector(name='model_outputs')
    
    # deserialize the model file back into a sklearn model
    model = joblib.load(model_path)
    logging.info("Init complete")


def run(raw_data):
    """
    This function is called for every invocation of the endpoint to perform the actual scoring/prediction.
    In the example we extract the data from the json input and call the scikit-learn model's predict()
    method and return the result back
    """
    logging.info("Request received")
    
    # Parse incoming data
    data = json.loads(raw_data)["data"]
    data_array = numpy.array(data)
    
    # Convert input to DataFrame for data collection
    # The collector requires pandas DataFrames
    input_df = pd.DataFrame(data_array)
    
    # Collect input data and get correlation context
    context = inputs_collector.collect(input_df)
    
    # Perform prediction
    result = model.predict(data_array)
    
    # Convert output to DataFrame for data collection
    output_df = pd.DataFrame(result, columns=["prediction"])
    
    # Collect output data with correlation context to link inputs and outputs
    outputs_collector.collect(output_df, context)
    
    logging.info("Request processed")
    return result.tolist()
