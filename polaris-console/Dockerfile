FROM node:22-alpine AS builder

ENV VITE_POLARIS_API_URL=http://polaris:8181
ENV VITE_POLARIS_REALM=POLARIS
ENV VITE_POLARIS_PRINCIPAL_SCOPE=PRINCIPAL_ROLE:ALL
ENV VITE_OAUTH_TOKEN_URL=http://polaris:8181/api/catalog/v1/oauth/tokens
ENV VITE_POLARIS_REALM_HEADER_NAME=Polaris-Realm

WORKDIR /app

RUN apk add --no-cache git && \
    git clone --depth 1 https://github.com/apache/polaris-tools.git /tmp/polaris-tools && \
    cp -r /tmp/polaris-tools/console/* . && \
    rm -rf /tmp/polaris-tools

RUN npm install && npm run build

FROM nginx:alpine

COPY --from=builder /app/dist /opt/app-root/src
COPY nginx.conf /etc/nginx/conf.d/default.conf

RUN addgroup -g 10001 polaris && \
    adduser -u 10000 -G polaris -h /opt/app-root -D polaris

RUN chown -R polaris:polaris /opt/app-root /var/log/nginx /var/cache/nginx /etc/nginx/conf.d && \
    touch /var/run/nginx.pid && \
    chown polaris:polaris /var/run/nginx.pid

COPY generate-config.sh /generate-config.sh
RUN chmod +x /generate-config.sh

USER polaris

EXPOSE 4000

ENTRYPOINT ["/generate-config.sh"]
