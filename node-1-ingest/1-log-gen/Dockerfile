FROM node:20-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./
COPY tsconfig.json ./

# Install dependencies
RUN npm install

# Copy source code
COPY log-gen.ts .
COPY logs-original ./logs-original

# Build TypeScript
RUN npm run build

# Create logs directory
RUN mkdir -p /logs-generated

# Run the generator
CMD ["npm", "start"]