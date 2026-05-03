# Multi-stage Dockerfile for Data Layer Server

# ============================================================================
# Build Stage
# ============================================================================
FROM dart:3.3-sdk AS build

WORKDIR /app

# Copy pubspec files
COPY pubspec.yaml pubspec.lock ./

# Get dependencies
RUN dart pub get

# Copy source code
COPY . .

# Compile to native executable
RUN dart compile exe bin/main.dart -o bin/server

# ============================================================================
# Runtime Stage
# ============================================================================
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy compiled binary from build stage
COPY --from=build /app/bin/server /app/bin/server

# Expose port
EXPOSE 8090

# Health check
HEALTHCHECK --interval=10s --timeout=5s --retries=5 --start-period=20s \
  CMD curl -f http://localhost:8090/health || exit 1

# Run as non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Start server
CMD ["/app/bin/server"]
