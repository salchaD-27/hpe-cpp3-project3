# Use lightweight Python image
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Copy script
COPY log_generator.py .

# Create logs directory (important)
RUN mkdir -p /logs

# Run script
CMD ["python", "log_generator.py"]