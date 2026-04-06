# Use lightweight Python image
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Copy full project
COPY . .

# Create output directory (Fluent Bit will read from here)
RUN mkdir -p /app/output

# Ensure real-time logging
ENV PYTHONUNBUFFERED=1

# Default command (can be overridden)
CMD ["python", "-m", "core.run_generate"]