# Dockerfile for Temporal Benchmark Runner
# Multi-stage build for ARM64 (Graviton)
#
# This image:
# - Builds the benchmark binary from Go source
# - Creates a minimal Alpine-based runtime image
# - Exposes Prometheus metrics on port 9090
# - Runs as non-root user for security

# Build arguments
ARG TARGETARCH=arm64
ARG ALPINE_TAG=3.23

# ============================================================================
# Stage 1: Build the benchmark binary
# ============================================================================
FROM golang:1.23-alpine AS builder

ARG TARGETARCH

# Install build dependencies
RUN apk add --no-cache git ca-certificates

WORKDIR /build

# Copy go.mod and go.sum first for better layer caching
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the benchmark binary
# CGO_ENABLED=0 for static binary
# -ldflags="-s -w" to strip debug info and reduce binary size
RUN CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build \
    -ldflags="-s -w" \
    -o /benchmark \
    ./cmd/benchmark

# ============================================================================
# Stage 2: Create minimal runtime image
# ============================================================================
ARG ALPINE_TAG
FROM alpine:${ALPINE_TAG}

# Install runtime dependencies
# - ca-certificates: for TLS connections to Temporal
# - curl: for health checks and debugging
RUN apk add --no-cache ca-certificates curl

# Create non-root user for security
RUN addgroup -g 1000 benchmark && \
    adduser -u 1000 -G benchmark -s /bin/sh -D benchmark

# Copy the benchmark binary from builder
COPY --from=builder /benchmark /usr/local/bin/benchmark

# Ensure binary is executable
RUN chmod +x /usr/local/bin/benchmark

# Switch to non-root user
USER benchmark

# Expose Prometheus metrics port
EXPOSE 9090

# Set entrypoint to the benchmark binary
ENTRYPOINT ["/usr/local/bin/benchmark"]
