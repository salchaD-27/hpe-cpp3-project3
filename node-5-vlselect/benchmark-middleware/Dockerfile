FROM python:3.11-slim

WORKDIR /app

RUN pip install flask requests prometheus-client

COPY middleware.py .

EXPOSE 8080

CMD ["python", "middleware.py"]