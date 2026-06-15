# syntax=docker/dockerfile:1
# Stage 1: Download dependencies (cache layer)
FROM maven:3.9-eclipse-temurin-21-alpine AS deps
WORKDIR /build
COPY pom.xml .
# Pre-fetch all dependencies into a cacheable layer
RUN mvn dependency:go-offline -q

# Stage 2: Build application
FROM deps AS builder
COPY src/ src/
RUN mvn package -DskipTests -q

# Stage 3: Minimal runtime image
FROM eclipse-temurin:21-jre-alpine AS runtime
LABEL org.opencontainers.image.source="https://github.com/hknisci/k8s-creating_cluster_with_ansible"
LABEL org.opencontainers.image.description="Dream Games DevOps Case Study - Query Param App"

# Create non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Create log directory owned by appuser
RUN mkdir -p /app/logs && chown -R appuser:appgroup /app

WORKDIR /app

COPY --from=builder --chown=appuser:appgroup /build/target/*.jar app.jar

USER appuser

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD wget -qO- http://localhost:8080/actuator/health/liveness || exit 1

# Build acceleration notes:
# 1. Maven dependency layer cached separately (deps stage)
# 2. Only src/ changes invalidate builder cache, not pom.xml changes
# 3. JRE-only runtime (not JDK) keeps image minimal (~200MB vs ~500MB)
# 4. Alpine base for minimal attack surface
# 5. Non-root user (appuser) for security
ENTRYPOINT ["java", \
    "-XX:MaxRAMPercentage=75.0", \
    "-XX:+UseContainerSupport", \
    "-Djava.security.egd=file:/dev/./urandom", \
    "-Dspring.profiles.active=prod", \
    "-jar", "app.jar"]
