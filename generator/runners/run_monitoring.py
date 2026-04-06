import os
import sys


# Allow running this file directly from the hpcm_generator directory.
sys.path.append(os.path.dirname(os.path.dirname(__file__)))

from core.log_forwarder import stream_logs


RATE = 10

stream_logs(
    "data/cleaned_logs_monitoring.json",
    "output/monitoring.json",
    1.0 / RATE,
)