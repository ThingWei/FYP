FROM node:20-alpine AS contracts
WORKDIR /contracts
COPY blockchain/package*.json ./
RUN npm ci
COPY blockchain/ ./
RUN npm run compile

FROM node:20-alpine
WORKDIR /app
COPY services/api/package*.json ./
RUN npm ci --omit=dev
COPY services/api/ ./
COPY --from=contracts /contracts/artifacts /blockchain-artifacts
CMD ["npm", "start"]

