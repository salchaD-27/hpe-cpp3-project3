# FROM node:20-alpine

# WORKDIR /app

# COPY package*.json ./
# COPY tsconfig.json ./


# RUN npm install
# COPY src/ ./src/
# RUN npm run build

# RUN mkdir -p /1-logs-storage
# RUN mkdir -p /1-logs-storage/error-logs

# ENV NORMAL_LOG_DIR=/1-logs-storage
# ENV ERROR_LOG_DIR=/1-logs-storage/error-logs
# ENV ERROR_INTERVAL_SECONDS=10

# RUN echo '#!/bin/sh\n\
# node dist/normal-generator.js &\n\
# node dist/error-generator.js &\n\
# wait' > /app/start.sh && chmod +x /app/start.sh

# CMD ["/app/start.sh"]


FROM node:20-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./
COPY tsconfig.json ./

# Install dependencies including ts-node
RUN npm install

# Copy source code
COPY src/ ./src/

# Create logs directories
RUN mkdir -p /1-logs-storage
RUN mkdir -p /1-logs-storage/error-logs

# Environment variables
ENV NORMAL_LOG_DIR=/1-logs-storage
ENV ERROR_LOG_DIR=/1-logs-storage/error-logs
ENV ERROR_INTERVAL_SECONDS=10

# Run both generators using ts-node
CMD ["sh", "-c", "npx ts-node src/1-logs-generation-simulation.ts & npx ts-node src/2-error-logs-generation-simulation.ts & wait"]