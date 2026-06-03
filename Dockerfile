# Static site built on host (pnpm run build), see build.sh
FROM alpine

# Install nginx with brotli module
RUN apk add --no-cache nginx nginx-mod-http-brotli

# Redirect logs to stdout/stderr
RUN ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

# Copy built files to nginx html directory
COPY dist /usr/share/nginx/html/docs

# Copy custom nginx config (Alpine uses http.d/ not conf.d/)
COPY nginx.conf /etc/nginx/http.d/default.conf

# Create necessary directories
RUN mkdir -p /run/nginx

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
