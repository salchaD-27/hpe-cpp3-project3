FROM node:20-alpine

WORKDIR /app

# Copy only the JavaScript generator
COPY log-gen.js .

# Create logs directory
RUN mkdir -p /logs-generated

# Run the generator
CMD ["node", "log-gen.js"]
