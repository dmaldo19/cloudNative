FROM busybox:1.37.0-musl AS healthcheck

FROM us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0

# Supply an HTTP probe
COPY --from=healthcheck /bin/busybox /busybox
RUN ["/busybox", "wget", "--help"]

ENV PORT=8080
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["/busybox", "wget", "-q", "-O", "/dev/null", "http://127.0.0.1:8080/"]
