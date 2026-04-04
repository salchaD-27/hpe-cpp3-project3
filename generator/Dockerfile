# Use lightweight Python image
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Copy all required files
COPY log_forwarder.py .
COPY cleaned_logs.json .

# Create logs directory (Fluent Bit will read from here)
RUN mkdir -p /logs

# Ensure Python output is unbuffered (important for real-time logs)
ENV PYTHONUNBUFFERED=1

# Default command → run forwarder
CMD ["python", "log_forwarder.py"]