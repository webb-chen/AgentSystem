# syntax=docker/dockerfile:1

FROM --platform=$BUILDPLATFORM golang:1.26.2-bookworm AS builder

ARG TARGETOS
ARG TARGETARCH
ARG GOPROXY=

WORKDIR /src

ENV GOPROXY=${GOPROXY}

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY . .
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -trimpath -ldflags="-s -w" -o /out/mingyingkeji-sandbox ./cmd/server && \
    CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -trimpath -ldflags="-s -w" -o /out/mingyingkeji-sandbox-profilebuilder ./cmd/profilebuilder

FROM node:20-bookworm-slim AS node-runtime

FROM python:3.11-slim-bookworm AS system-office-profile

ARG APT_MIRROR=
ARG APT_SECURITY_MIRROR=

WORKDIR /src

COPY --from=node-runtime /usr/local/ /usr/local/
COPY --from=builder /out/mingyingkeji-sandbox-profilebuilder /usr/local/bin/mingyingkeji-sandbox-profilebuilder
COPY profiles ./profiles

RUN if [ -n "$APT_MIRROR" ]; then \
        sed -i "s|http://deb.debian.org/debian|http://$APT_MIRROR/debian|g" /etc/apt/sources.list.d/*.sources; \
    fi && \
    if [ -n "$APT_SECURITY_MIRROR" ]; then \
        sed -i "s|http://deb.debian.org/debian-security|http://$APT_SECURITY_MIRROR/debian-security|g" /etc/apt/sources.list.d/*.sources; \
    fi && \
    apt-get -o Acquire::Retries=5 update && \
    apt-get -o Acquire::Retries=5 install -y --fix-missing --no-install-recommends bubblewrap util-linux && \
    sed 's/\r$//' profiles/skill-office/apt-packages.txt | grep -v '^[[:space:]]*$' | xargs -r apt-get -o Acquire::Retries=5 install -y --fix-missing --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

ENV PATH=/usr/bin:/bin:/usr/local/bin:/usr/sbin:/sbin

ARG NPM_CONFIG_REGISTRY=
ARG PIP_INDEX_URL=

RUN if [ -n "$NPM_CONFIG_REGISTRY" ]; then npm config set registry "$NPM_CONFIG_REGISTRY"; fi && \
    if [ -n "$PIP_INDEX_URL" ]; then export PIP_INDEX_URL; fi && \
    python3 -c "import ssl; print(ssl.OPENSSL_VERSION)" && \
    npm install -g pnpm@9.15.9 && \
    mingyingkeji-sandbox-profilebuilder --profile skill-office --source-dir profiles --output-dir /tmp/profile-build --force && \
    mkdir -p /out/skill-office && \
    tar --one-file-system \
        --exclude=/dev --exclude=./dev \
        --exclude=/out --exclude=./out \
        --exclude=/proc --exclude=./proc \
        --exclude=/run --exclude=./run \
        --exclude=/src --exclude=./src \
        --exclude=/sys --exclude=./sys \
        --exclude=/tmp/profile-build --exclude=./tmp/profile-build \
        -C / -cf - . | tar -C /out/skill-office -xf - && \
    mkdir -p /out/skill-office/opt/mingyingkeji/profiles && \
    mv /tmp/profile-build/skill-office /out/skill-office/opt/mingyingkeji/profiles/skill-office

FROM system-office-profile

WORKDIR /app

COPY --from=builder /out/mingyingkeji-sandbox /usr/local/bin/mingyingkeji-sandbox
COPY --chmod=755 scripts/build-dependency-profile /usr/local/bin/mingyingkeji-sandbox-build-dependency-profile
COPY --chmod=755 scripts/docker-entrypoint /usr/local/bin/mingyingkeji-sandbox-docker-entrypoint
RUN sed -i 's/\r$//' /usr/local/bin/mingyingkeji-sandbox-build-dependency-profile /usr/local/bin/mingyingkeji-sandbox-docker-entrypoint

RUN useradd --system --create-home --home-dir /home/mingyingkeji --shell /usr/sbin/nologin mingyingkeji && \
    mkdir -p /opt/mingyingkeji/prebuilt-dependency-rootfs && \
    cp -R /out/. /opt/mingyingkeji/prebuilt-dependency-rootfs/ && \
    rm -rf /out /src && \
    mkdir -p /var/lib/mingyingkeji-sandbox/dependency-rootfs && \
    chown -R mingyingkeji:mingyingkeji /opt/mingyingkeji/prebuilt-dependency-rootfs && \
    chown -R mingyingkeji:mingyingkeji /var/lib/mingyingkeji-sandbox

EXPOSE 2660

USER mingyingkeji

ENTRYPOINT ["mingyingkeji-sandbox-docker-entrypoint"]
CMD ["mingyingkeji-sandbox"]
