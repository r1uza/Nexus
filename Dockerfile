FROM dart:3.12.2 AS build
WORKDIR /src
COPY pubspec.yaml analysis_options.yaml ./
COPY bin ./bin
COPY lib ./lib
COPY test ./test
COPY tool ./tool
RUN dart pub get && dart analyze && dart run tool/verify.dart
RUN mkdir -p /out && dart compile exe bin/nexus_sf.dart -o /out/nexus-sf

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 --home /nonexistent --shell /usr/sbin/nologin nexus
COPY --from=build /out/nexus-sf /opt/nexus-sf
RUN mkdir -p /data && chown 10001:10001 /data
USER 10001:10001
ENV NEXUS_BIND=0.0.0.0 NEXUS_PORT=8787 NEXUS_DATA_DIR=/data
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD ["/opt/nexus-sf", "healthcheck", "--bind", "127.0.0.1", "--port", "8787"]
ENTRYPOINT ["/opt/nexus-sf"]
CMD ["serve"]

