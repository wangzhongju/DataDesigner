# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

FROM ubuntu:24.04 AS base
ARG UBUNTU_ARCHIVE_URL=http://archive.ubuntu.com/ubuntu/
RUN --mount=type=cache,id=datadesigner-apt,target=/var/lib/apt/lists,sharing=locked \
    sed -i -E "s|^URIs: http://archive\.ubuntu\.com/ubuntu/?$|URIs: $UBUNTU_ARCHIVE_URL|" \
        /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get -o Acquire::Retries=3 update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates python3

FROM base AS build
ENV UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_PYTHON_DOWNLOADS=never \
    UV_LINK_MODE=copy
WORKDIR /src
RUN --mount=type=cache,id=datadesigner-apt,target=/var/lib/apt/lists,sharing=locked \
    apt-get -o Acquire::Retries=3 update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends git python3-venv
RUN python3 -m venv /tmp/bootstrap \
    && /tmp/bootstrap/bin/pip install --disable-pip-version-check --no-cache-dir \
        --only-binary=:all: --no-deps uv==0.13.4 \
    && install /tmp/bootstrap/bin/uv /usr/local/bin/uv \
    && rm -rf /tmp/bootstrap

# Cache third-party dependencies separately from the three workspace wheels.
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,id=datadesigner-uv,target=/root/.cache/uv \
    uv sync --frozen --all-packages --no-dev --no-install-workspace

COPY README.md LICENSE ./
COPY packages/ ./packages/
# Hatch derives all three package versions from the same Git history.
RUN --mount=type=bind,source=.git,target=/src/.git \
    --mount=type=cache,id=datadesigner-uv,target=/root/.cache/uv \
    uv sync --locked --all-packages --no-dev --no-editable

FROM base AS runtime
ENV VIRTUAL_ENV=/opt/venv
ENV UV_PROJECT_ENVIRONMENT="${VIRTUAL_ENV}" \
    UV_LINK_MODE=copy \
    PATH="${VIRTUAL_ENV}/bin:${PATH}" \
    HOME=/state \
    DATA_DESIGNER_HOME=/state/.data-designer
RUN --mount=type=cache,id=datadesigner-apt,target=/var/lib/apt/lists,sharing=locked \
    apt-get -o Acquire::Retries=3 update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends bash-completion git make sudo vim
COPY --from=build --chown=1000:1000 /opt/venv /opt/venv
COPY --from=build /usr/local/bin/uv /usr/local/bin/uv
COPY --chmod=755 docker/runtime/env.sh /usr/local/bin/datadesigner-env.sh
RUN install -d -o 1000 -g 1000 /state /workspace
USER 1000:1000
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/datadesigner-env.sh"]
CMD ["data-designer", "--help"]
