# syntax=docker/dockerfile:1
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY src/ src/

FROM node:20-alpine AS runtime
LABEL org.opencontainers.image.source="https://github.com/hknisci/k8s-creating_cluster_with_ansible"
LABEL org.opencontainers.image.description="Node.js Express sample app"

RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 appuser

WORKDIR /app

COPY --from=deps --chown=appuser:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=appuser:nodejs /app/src ./src
COPY --chown=appuser:nodejs package*.json ./

USER appuser

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/health/live || exit 1

CMD ["node", "src/index.js"]
