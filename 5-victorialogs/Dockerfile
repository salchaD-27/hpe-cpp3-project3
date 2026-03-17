FROM alpine:3.20

RUN apk add --no-cache wget ca-certificates tar && \
    wget -q https://github.com/VictoriaMetrics/VictoriaLogs/releases/download/v0.4.0/victoria-logs-0.4.0-linux-amd64.tar.gz && \
    tar xzf victoria-logs-0.4.0-linux-amd64.tar.gz && \
    mv victoria-logs-0.4.0-linux-amd64/victoria-logs /usr/local/bin/ && \
    chmod +x /usr/local/bin/victoria-logs && \
    rm -rf victoria-logs-0.4.0-linux-amd64* && \
    apk del wget tar

VOLUME /var/lib/victoria-logs/data

EXPOSE 9428

USER 1000:1000

ENTRYPOINT ["/usr/local/bin/victoria-logs"]
CMD ["-storageDataPath=/var/lib/victoria-logs/data", "-retentionPeriod=30d", "-httpListenAddr=:9428", "-logNewStreams", "-logIngestedRows"]
