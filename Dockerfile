FROM node:24-alpine AS builder

WORKDIR /app

# Install pnpm
RUN npm install -g pnpm

# Copy package files
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY scripts/ ./scripts/

# Install dependencies
RUN pnpm install --frozen-lockfile

# Copy source files
COPY . .

# Build the static site with /docs base path
ENV SITE_BASE=/docs
RUN pnpm run build

# Production stage with nginx + brotli
FROM alpine

# Install nginx with brotli module
RUN apk add --no-cache nginx nginx-mod-http-brotli

# Redirect logs to stdout/stderr
RUN ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

# Copy built files to nginx html directory
COPY --from=builder /app/dist /usr/share/nginx/html/docs

# Copy custom nginx config (Alpine uses http.d/ not conf.d/)
COPY nginx.conf /etc/nginx/http.d/default.conf

# Create necessary directories
RUN mkdir -p /run/nginx

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
