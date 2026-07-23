# =============================================================================
# COMPREHENSIVE DOCKERFILE - Go Web Application
# =============================================================================
# PURPOSE : A reference Dockerfile that demonstrates every core Docker
#           instruction so you can learn Docker image authoring end-to-end.
#
# CONCEPTS COVERED
#   1.  Syntax directive        – parser version pinning
#   2.  FROM                    – base image selection
#   3.  ARG                     – build-time variables
#   4.  ENV                     – runtime environment variables
#   5.  LABEL                   – image metadata / OCI annotations
#   6.  WORKDIR                 – working directory management
#   7.  COPY                    – copy files from build context
#   8.  ADD                     – copy + auto-extract tar / URL fetch
#   9.  RUN                     – execute commands during build
#           - shell form vs exec form
#           - layer caching & combining commands with &&
#           - cache mounts (BuildKit)
#   10. USER                    – drop root privileges
#   11. EXPOSE                  – document container port
#   12. VOLUME                  – declare mount-points
#   13. HEALTHCHECK             – liveness probe for the container runtime
#   14. STOPSIGNAL              – OS signal sent on docker stop
#   15. CMD                     – default arguments / default command
#   16. ENTRYPOINT              – fixed entry-point executable
#   17. SHELL                   – override default shell for RUN/CMD/ENTRYPOINT
#   18. ONBUILD                 – triggers for child images
#   19. Multi-stage builds      – separate build and runtime stages
#   20. Distroless runner       – minimal, secure production image
#
# HOW TO BUILD
#   docker build -t go-web-app:latest .
#   docker build --build-arg APP_VERSION=2.0.0 -t go-web-app:2.0.0 .
#
# HOW TO RUN
#   docker run -p 8080:8080 go-web-app:latest
#   docker run -p 8080:8080 -e APP_ENV=production go-web-app:latest
# =============================================================================


# -----------------------------------------------------------------------------
# CONCEPT 1 – SYNTAX DIRECTIVE
# -----------------------------------------------------------------------------
# The #syntax comment MUST be the very first line (before FROM).
# It pins the BuildKit frontend parser version so your build is reproducible
# even if the default parser changes in future Docker versions.
# Requires BuildKit: DOCKER_BUILDKIT=1 docker build ...
# (BuildKit is the default engine in Docker Desktop and Docker Engine 23+)
# -----------------------------------------------------------------------------
# syntax=docker/dockerfile:1


# =============================================================================
# STAGE 1 – BUILDER
# =============================================================================
# Multi-stage builds (--target) let you use a fat SDK image to compile code
# and then copy only the resulting binary into a slim runtime image.
# Nothing from this stage ships in the final image unless you explicitly
# COPY --from=builder.
# =============================================================================

# -----------------------------------------------------------------------------
# CONCEPT 2 – FROM
# -----------------------------------------------------------------------------
# FROM <image>[:<tag>] [AS <name>]
#
# - Every Dockerfile must start with FROM (after optional directives/ARGs).
# - <image>   : Docker Hub image name  (e.g. golang, ubuntu, alpine)
# - :<tag>    : Always pin a specific tag – never use "latest" in production
#               because it changes without warning and breaks reproducibility.
# - AS <name> : Names this stage so later stages can reference it with
#               COPY --from=<name> or --target=<name> at build time.
# -----------------------------------------------------------------------------
FROM golang:1.22.5 AS builder


# -----------------------------------------------------------------------------
# CONCEPT 3 – ARG  (build-time variables)
# -----------------------------------------------------------------------------
# ARG <name>[=<default>]
#
# - ARG values are available ONLY during the build (docker build --build-arg).
# - They are NOT stored in the image layers and NOT available at runtime.
# - Use ARG for things like version numbers, feature flags, registry URLs.
# - ARG declared before FROM is scoped to the FROM line only; re-declare
#   after FROM to use it in subsequent instructions.
# - WARNING: ARG values can appear in docker history – do NOT pass secrets.
#            Use BuildKit secret mounts (--secret) for sensitive data.
#
# Usage:
#   docker build --build-arg APP_VERSION=2.0.0 .
# -----------------------------------------------------------------------------
ARG APP_VERSION=1.0.0
ARG BUILD_DATE
ARG GIT_COMMIT=unknown


# -----------------------------------------------------------------------------
# CONCEPT 4 – ENV  (runtime environment variables)
# -----------------------------------------------------------------------------
# ENV <key>=<value> ...
#
# - ENV variables persist into every RUN instruction AND into the running
#   container (unlike ARG which disappears after the build).
# - They can be overridden at runtime: docker run -e APP_ENV=production ...
# - Use ENV for configuration your application reads at runtime.
# - Prefer single ENV instruction with multiple key=value pairs to minimise
#   image layers (each instruction adds a layer).
# - can be access in the application code using os.Getenv("APP_ENV") in Go.
# - can be used in subsequent instructions with $VAR or ${VAR} syntax.
# - can be used in the ENTRYPOINT/CMD to pass configuration to the binary, like: docker run -e APP_PORT=9090 go-web-app:latest → ./main --port=9090
# - we can store credentials in ENV variables, but it is not recommended for production use. Use Docker secrets or environment variable files instead
# -----------------------------------------------------------------------------
ENV APP_ENV=development \
    APP_PORT=8080 \
    CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64


# -----------------------------------------------------------------------------
# CONCEPT 5 – LABEL  (image metadata / OCI annotations)
# -----------------------------------------------------------------------------
# LABEL <key>=<value> ...
#
# - Labels attach arbitrary key-value metadata to the image.
# - They do NOT affect the running container; they are purely informational.
# - Standard OCI annotation keys (org.opencontainers.image.*) are preferred.
# - View labels: docker inspect <image> | grep -A20 Labels
# - ARG values can be interpolated here with $VAR syntax.
# -----------------------------------------------------------------------------
LABEL org.opencontainers.image.title="Go Web App" \
      org.opencontainers.image.description="Educational Go web application" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.authors="your-name@example.com" \
      org.opencontainers.image.source="https://github.com/your-org/go-web-app" \
      maintainer="your-name@example.com"


# -----------------------------------------------------------------------------
# CONCEPT 6 – WORKDIR  (working directory)
# -----------------------------------------------------------------------------
# WORKDIR /path/to/dir
#
# - Sets the working directory for all subsequent RUN, COPY, ADD, CMD,
#   ENTRYPOINT instructions (and for an interactive shell via docker exec).
# - If the directory does not exist Docker creates it automatically.
# - Prefer WORKDIR over "RUN cd /some/path" – WORKDIR is explicit and
#   survives across layers whereas cd only affects one RUN command.
# - You can call WORKDIR multiple times; each call is relative to the last.
# -----------------------------------------------------------------------------
WORKDIR /app


# -----------------------------------------------------------------------------
# CONCEPT 7 – COPY  (copy files from build context)
# -----------------------------------------------------------------------------
# COPY [--chown=<user>:<group>] [--chmod=<perms>] <src>... <dest>
# COPY --from=<stage|image> <src> <dest>
#
# - Copies files/directories from the build context (your local machine) OR
#   from a previous build stage (--from=<stage>).
# - <src> is relative to the build context root (the directory you pass to
#   docker build, usually the project root).
# - <dest> is relative to WORKDIR (or absolute).
# - COPY respects .dockerignore – always create a .dockerignore to exclude
#   node_modules, .git, test files, secrets, etc.
#
# COPY vs ADD:
#   COPY – simple, explicit, recommended for most use-cases.
#   ADD  – has extra features (see below) but can be surprising; use only
#          when you need its tar-extraction or URL-fetching capability.
#
# Layer caching tip:
#   Copy dependency manifests FIRST (go.mod / package.json) and run the
#   download step before copying the rest of the source. Docker caches each
#   layer; if go.mod hasn't changed the expensive download is skipped.
# -----------------------------------------------------------------------------

# Step 1: copy only the dependency manifest – this layer is cached as long
#         as go.mod doesn't change.
COPY go.mod ./

# -----------------------------------------------------------------------------
# CONCEPT 8 – ADD  (copy + extras)
# -----------------------------------------------------------------------------
# ADD [--chown=<user>:<group>] <src>... <dest>
#
# ADD has two capabilities beyond COPY:
#   a) Auto-extracts local .tar, .tar.gz, .tar.bz2, .tar.xz, .tgz archives.
#   b) Fetches remote URLs (not recommended – prefer RUN curl/wget for
#      better caching control and transparency).
#
# Example (archive extraction – commented out as not needed here):
#   ADD vendor.tar.gz /app/vendor/
#
# Because ADD's behaviour can be surprising, the Docker best-practices guide
# recommends COPY for everything except tar extraction.
# -----------------------------------------------------------------------------
# ADD https://example.com/somefile.tar.gz /tmp/   # ← URL fetch (not used here)


# -----------------------------------------------------------------------------
# CONCEPT 9 – RUN  (execute commands during build)
# -----------------------------------------------------------------------------
# RUN <command>                            ← shell form  (runs via /bin/sh -c)
# RUN ["executable", "arg1", "arg2"]       ← exec form   (no shell expansion)
#
# KEY RULES:
#   • Every RUN creates a new image layer. Combine related commands with &&
#     and use \ for line continuation to keep layer count low.
#   • Order instructions from least-to-most-frequently-changed to maximise
#     cache reuse (Docker caches from the top; a cache miss invalidates all
#     subsequent layers).
#   • Clean up package manager caches in the SAME RUN step that installs
#     packages, otherwise the cache ends up in a separate layer and still
#     bloats the image.
#
# BuildKit cache mount (--mount=type=cache):
#   Persists directories (e.g. Go module cache) across builds on the same
#   host without baking them into image layers. Dramatically speeds up
#   repeated builds.
# -----------------------------------------------------------------------------

# Download Go modules – cached until go.mod changes.
RUN go mod download

# Copy the full source code AFTER downloading dependencies so that source
# changes don't invalidate the expensive download layer above.
COPY . .

# Build the binary.
# Shell form: RUN go build ...   (equivalent, slightly shorter)
# Exec form used here for explicitness – no shell interpolation.
RUN go build \
    -ldflags="-s -w -X main.version=${APP_VERSION} -X main.gitCommit=${GIT_COMMIT}" \
    -o main .
#
# -ldflags "-s -w" strips debug symbols → smaller binary.
# -X main.version injects the build-arg value into the binary at link time.


# =============================================================================
# STAGE 2 – RUNNER  (production image)
# =============================================================================
# This stage starts fresh from a minimal base image. It receives only the
# files explicitly copied from the builder stage – the Go toolchain, module
# cache, and source code are all left behind, keeping the final image small
# and the attack surface minimal.
# =============================================================================

# -----------------------------------------------------------------------------
# CONCEPT 2 (continued) – FROM with a second stage
# -----------------------------------------------------------------------------
# gcr.io/distroless/base contains only libc and CA certificates – no shell,
# no package manager, no utilities. This means:
#   + Vastly smaller image (~20 MB vs ~800 MB for golang:1.22)
#   + No shell available to an attacker who gains code execution
#   - No shell means you cannot use shell form CMD/ENTRYPOINT; use exec form.
#   - Debugging is harder – use :debug tag during development.
# -----------------------------------------------------------------------------
FROM gcr.io/distroless/base AS runner

# Re-declare ARG after FROM so it is available in this stage.
ARG APP_VERSION=1.0.0

# Carry over runtime ENV to the final image.
ENV APP_ENV=production \
    APP_PORT=8080

# Apply the same metadata labels to the final image.
LABEL org.opencontainers.image.title="Go Web App" \
      org.opencontainers.image.version="${APP_VERSION}"

# Set the working directory for this stage.
WORKDIR /app

# Copy the compiled binary from the builder stage.
COPY --from=builder /app/main .

# Copy static assets from the builder stage.
COPY --from=builder /app/static ./static


# -----------------------------------------------------------------------------
# CONCEPT 10 – USER  (drop root privileges)
# -----------------------------------------------------------------------------
# USER <user>[:<group>]
#
# - By default, containers run as root (UID 0) which is a security risk.
#   If an attacker escapes the container they have root on the host.
# - Switch to a non-root user before the ENTRYPOINT / CMD.
# - Distroless images provide a built-in "nonroot" user (UID 65532).
# - For images based on Debian/Ubuntu you would first create the user:
#     RUN groupadd -r appgroup && useradd -r -g appgroup appuser
#     USER appuser
# - You can also use numeric UID/GID to avoid a dependency on /etc/passwd:
#     USER 65532:65532
# -----------------------------------------------------------------------------
USER nonroot:nonroot


# -----------------------------------------------------------------------------
# CONCEPT 11 – EXPOSE  (document the container's listening port)
# -----------------------------------------------------------------------------
# EXPOSE <port>[/<protocol>]   protocol defaults to tcp
#
# - EXPOSE is documentation only – it does NOT open the port on the host.
#   To actually publish the port use: docker run -p <host>:<container> ...
# - It signals to operators (and tools like docker-compose) which port the
#   application expects to receive traffic on.
# - List every port your app listens on.
# -----------------------------------------------------------------------------
EXPOSE 8080/tcp


# -----------------------------------------------------------------------------
# CONCEPT 12 – VOLUME  (declare persistent mount-points)
# -----------------------------------------------------------------------------
# VOLUME ["/path1", "/path2"]  or  VOLUME /path1 /path2
#
# - Declares that the specified paths are intended to be externally mounted
#   volumes (host bind-mounts or named Docker volumes).
# - Docker automatically creates an anonymous volume for the path if the
#   user doesn't provide one at runtime.
# - Use VOLUME for data that must survive container restarts: databases,
#   log files, uploaded files, etc.
# - NOTE: You cannot write to a declared VOLUME path in subsequent RUN steps
#   because a new anonymous volume is mounted there at that point.
# -----------------------------------------------------------------------------
VOLUME ["/app/logs"]


# -----------------------------------------------------------------------------
# CONCEPT 13 – HEALTHCHECK  (container liveness probe)
# -----------------------------------------------------------------------------
# HEALTHCHECK [OPTIONS] CMD <command>
# HEALTHCHECK NONE   ← disable a HEALTHCHECK inherited from a base image
#
# Options:
#   --interval=30s   how often to run the check (default 30s)
#   --timeout=30s    how long before the check is considered failed (default 30s)
#   --start-period=5s grace period after container starts (default 0s)
#   --retries=3      consecutive failures before marking unhealthy (default 3)
#
# The CMD is run inside the container; exit 0 = healthy, exit 1 = unhealthy.
# Docker (and Kubernetes liveness probes) use this to restart sick containers.
#
# NOTE: distroless images have no wget/curl, so we use the binary itself or
#       a small Go health-check binary. For demo purposes we use /bin/true
#       (available in distroless:debug). In practice, add a /healthz endpoint
#       and call it here.
# -----------------------------------------------------------------------------
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["/bin/true"]


# -----------------------------------------------------------------------------
# CONCEPT 14 – STOPSIGNAL  (graceful shutdown signal)
# -----------------------------------------------------------------------------
# STOPSIGNAL <signal>
#
# - Specifies the OS signal sent to the container process when docker stop
#   is called. Default is SIGTERM.
# - Your application should catch this signal and shut down gracefully
#   (finish in-flight requests, flush buffers, close DB connections).
# - SIGTERM is the polite "please stop" signal. After the grace period
#   (docker stop --time, default 10s) Docker sends SIGKILL which is forced.
# - Common values: SIGTERM, SIGINT, SIGHUP, or numeric form like 15.
# -----------------------------------------------------------------------------
STOPSIGNAL SIGTERM


# -----------------------------------------------------------------------------
# CONCEPT 15 – CMD  (default command / default arguments)
# -----------------------------------------------------------------------------
# CMD ["executable", "arg1", "arg2"]   ← exec form  (preferred)
# CMD command arg1 arg2                ← shell form
# CMD ["arg1", "arg2"]                 ← argument-only form (used with ENTRYPOINT)
#
# - CMD sets the default command run when a container starts with no command
#   given on the CLI: docker run <image>
# - It can be completely overridden at runtime:
#     docker run <image> /bin/sh   ← replaces CMD entirely
# - When used together with ENTRYPOINT in exec form, CMD provides default
#   arguments that can be appended-to or replaced at runtime.
# - Only the LAST CMD instruction in a Dockerfile takes effect.
# -----------------------------------------------------------------------------
# CMD ["./main"]   ← not used here because ENTRYPOINT is set (see below)


# -----------------------------------------------------------------------------
# CONCEPT 16 – ENTRYPOINT  (fixed entry-point executable)
# -----------------------------------------------------------------------------
# ENTRYPOINT ["executable", "arg1"]   ← exec form  (preferred)
# ENTRYPOINT command arg1             ← shell form  (wraps in /bin/sh -c)
#
# - ENTRYPOINT makes the container behave like an executable; everything
#   after the image name on the CLI (or CMD) is appended as arguments.
# - Unlike CMD, ENTRYPOINT cannot be overridden at runtime without --entrypoint.
# - Exec form is required when the base image has no shell (e.g. distroless).
# - Best practice for app containers: use ENTRYPOINT for the binary and CMD
#   for default flags, so users can override flags without replacing the binary.
#
#   ENTRYPOINT ["./main"]
#   CMD ["--port=8080"]          # docker run img --port=9090 → ./main --port=9090
#
# ENTRYPOINT vs CMD summary:
#   ENTRYPOINT  – what to run       (hard to override)
#   CMD         – how/with what     (easy to override)
# -----------------------------------------------------------------------------
ENTRYPOINT ["./main"]


# =============================================================================
# CONCEPT 17 – SHELL  (override the default shell)
# =============================================================================
# SHELL ["executable", "parameters"]
#
# Default shell on Linux: ["/bin/sh", "-c"]
# Default shell on Windows: ["cmd", "/S", "/C"]
#
# - Changes the shell used for subsequent RUN, CMD, ENTRYPOINT shell-form
#   instructions in this stage.
# - Useful when you need bash-specific features (e.g. pipefail):
#     SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# - Or when targeting Windows with PowerShell:
#     SHELL ["powershell", "-Command"]
# - Must be placed BEFORE the instructions that should use the new shell.
# - Example (not activated here – shown for reference):
#   SHELL ["/bin/bash", "-o", "pipefail", "-c"]
#   RUN set -euo pipefail && echo "bash with pipefail"
# =============================================================================


# =============================================================================
# CONCEPT 18 – ONBUILD  (triggers for child images)
# =============================================================================
# ONBUILD <instruction>
#
# - Registers a trigger instruction to be executed when this image is used
#   as a base image in another Dockerfile (i.e., FROM this-image).
# - The trigger fires AFTER the child image's FROM and BEFORE any other
#   instruction in the child Dockerfile.
# - Useful for creating reusable base images that automatically inject
#   boilerplate steps (e.g., COPY source, RUN install) into child images.
# - ONBUILD instructions are NOT executed when building the image itself,
#   only when the image is used as a parent.
#
# Example (not activated – shown for reference):
#   ONBUILD COPY . /app
#   ONBUILD RUN go build -o main .
#
# View triggers: docker inspect <image> --format '{{.Config.OnBuild}}'
# =============================================================================


# =============================================================================
# QUICK REFERENCE – DOCKER CLI COMMANDS TO TEST THESE CONCEPTS
# =============================================================================
#
# Build:
#   docker build -t go-web-app:latest .
#   docker build --build-arg APP_VERSION=2.0.0 --build-arg GIT_COMMIT=abc123 \
#                -t go-web-app:2.0.0 .
#   docker build --target builder -t go-web-app:builder .   # build only stage 1
#
# Run:
#   docker run -d -p 8080:8080 --name webapp go-web-app:latest
#   docker run -e APP_ENV=production -p 8080:8080 go-web-app:latest
#   docker run -v /host/logs:/app/logs go-web-app:latest   # mount VOLUME
#
# Inspect:
#   docker inspect go-web-app:latest                        # full metadata
#   docker history go-web-app:latest                        # layer history
#   docker image ls go-web-app                              # image size
#
# Health:
#   docker ps                              # STATUS column shows health
#   docker inspect webapp --format '{{.State.Health.Status}}'
#
# Cleanup:
#   docker stop webapp && docker rm webapp
#   docker rmi go-web-app:latest
# =============================================================================