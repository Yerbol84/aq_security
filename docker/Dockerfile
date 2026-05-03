# Multi-stage Dockerfile для production
# Оптимизирован для безопасности и размера

# Stage 1: Build
FROM dart:stable AS build

# Install dependencies
RUN apt-get update && apt-get install -y \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy pubspec files
COPY pubspec.* ./

# Get dependencies
RUN dart pub get

# Copy source code
COPY . .

# Compile to native executable
RUN dart compile exe bin/server.dart -o bin/server

# Stage 2: Runtime
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -r aqsecurity && useradd -r -g aqsecurity aqsecurity

# Set working directory
WORKDIR /app

# Copy compiled binary from build stage
COPY --from=build /app/bin/server /app/server

# Copy configuration files (if any)
COPY --from=build /app/config /app/config

# Create log directory
RUN mkdir -p /var/log/aq-security && \
    chown -R aqsecurity:aqsecurity /var/log/aq-security

# Set ownership
RUN chown -R aqsecurity:aqsecurity /app

# Switch to non-root user
USER aqsecurity

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8080/api/health || exit 1

# Run the server
CMD ["/app/server"]
