# ---- Build/verify stage (kept separate so we never ship build tooling) ----
FROM node:20-alpine AS lint
WORKDIR /app
COPY app/ .
# Placeholder for real build tooling (webpack/vite) if the app grows later.
RUN echo "static app - nothing to compile"

# ---- Runtime stage ----
FROM nginxinc/nginx-unprivileged:alpine-slim

USER root

# Apply security updates to clear OS-level vulnerabilities
RUN apk update && apk upgrade --no-cache && \
    rm -rf /var/cache/apk/*

# Run as non-root user (nginx-unprivileged uses UID 101)
USER 101

# Copy static assets and Nginx configuration
COPY --chown=101:101 app/index.html app/style.css app/script.js /usr/share/nginx/html/
COPY --chown=101:101 app/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1

LABEL org.opencontainers.image.source="https://github.com/ADITYASURVE123/tetris-devsecops" \
      org.opencontainers.image.description="K8s Tetris DevSecOps demo" \
      org.opencontainers.image.licenses="MIT"
