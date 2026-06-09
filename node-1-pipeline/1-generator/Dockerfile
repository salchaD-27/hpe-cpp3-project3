FROM python:3.11-slim

WORKDIR /app

COPY generator.py .
COPY logs-original/ /scripts/logs-original/

RUN mkdir -p /generated-logs && \
    ln -s /generated-logs /logs-generated

CMD ["python3", "-u", "generator.py"]