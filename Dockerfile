# syntax=docker/dockerfile:1

# --- build: bundle the UI (dist/mcp-app.html) and compile the server (dist/*.js)
FROM node:22-bookworm-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build && npm run build:server

# --- runtime: prod deps + headless Chromium and its system libraries
FROM node:22-bookworm-slim
ENV NODE_ENV=production \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    HEADLESS=1 \
    PORT=8080
WORKDIR /app
COPY package.json package-lock.json ./
# The headless shell is all `chromium.launch({ headless: true })` needs; the
# Playwright version (and so the browser build) comes from package-lock.json.
RUN npm ci --omit=dev \
    && npx playwright install --with-deps --only-shell chromium \
    && npm cache clean --force \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/dist ./dist
ARG VERSION=dev
ARG GIT_COMMIT=unknown
LABEL org.opencontainers.image.version=$VERSION \
      org.opencontainers.image.revision=$GIT_COMMIT
# uid/gid 1000, matching the pod security context of the kitabisa `app` chart.
USER node
EXPOSE 8080
CMD ["node", "dist/main.js"]
