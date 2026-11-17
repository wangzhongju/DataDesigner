#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname -- "$dir")"

die() {
    printf '%s\n' "$*" >&2
    exit 2
}

usage() {
    cat <<'EOF'
Usage: bash docker/docker.sh COMMAND [ARGS]

  build prod TAG [OPTIONS]           Build the DataDesigner image from this checkout.
  start                             Start the container and wait for readiness.
  recreate                          Recreate the container with the current configuration.
  stop                              Stop the container.
  restart                           Restart the container and wait for readiness.
  down                              Remove the container and network.
  status                            List containers, including stopped ones.
  config                            Validate the Compose configuration.
  logs [OPTIONS]                    Show container logs.
  into                              Open Bash as the calling host user.
  exec COMMAND [ARGS]               Run a command in the container.
  help                              Show this help.

The default image is datadesigner-local:latest. Set DATA_DESIGNER_IMAGE to
select another image for container commands.
EOF
}

build_image() {
    local tag=$1
    shift
    local tunnel_enabled="${SSH_TUNNEL_ENABLED:-}" tunnel_proxy="${SSH_TUNNEL_PROXY:-}"
    local archive_url="${UBUNTU_ARCHIVE_URL:-}"
    local build_env="$dir/env/build.env" build_network=default
    local build_args=()
    if [[ -f $build_env ]]; then
        # shellcheck source=/dev/null
        source "$build_env"
    fi
    tunnel_proxy="${tunnel_proxy:-${SSH_TUNNEL_PROXY:-http://127.0.0.1:17897}}"
    case "${tunnel_enabled:-${SSH_TUNNEL_ENABLED:-0}}" in
        0) ;;
        1)
            if [[ ! $tunnel_proxy =~ ^http://127\.0\.0\.1:[0-9]{1,5}$ ]]; then
                echo 'SSH_TUNNEL_PROXY must be http://127.0.0.1:PORT.' >&2
                return 2
            fi
            if ! curl --fail --silent --show-error --head --output /dev/null \
                --connect-timeout 5 --max-time 20 --noproxy '' \
                --proxy "$tunnel_proxy" https://pypi.org/simple/uv/; then
                echo 'Cannot reach PyPI through the SSH tunnel. See docker/README.md.' >&2
                return 2
            fi
            build_network=host
            build_args+=(
                --build-arg "HTTP_PROXY=$tunnel_proxy" --build-arg "http_proxy=$tunnel_proxy"
                --build-arg "HTTPS_PROXY=$tunnel_proxy" --build-arg "https_proxy=$tunnel_proxy"
                --build-arg "NO_PROXY=localhost,127.0.0.1" --build-arg "no_proxy=localhost,127.0.0.1"
            )
            ;;
        *)
            echo 'SSH_TUNNEL_ENABLED must be 0 or 1.' >&2
            return 2
            ;;
    esac
    archive_url="${archive_url:-${UBUNTU_ARCHIVE_URL:-}}"
    if [[ -n $archive_url ]]; then
        build_args+=(--build-arg "UBUNTU_ARCHIVE_URL=$archive_url")
    fi
    DOCKER_BUILDKIT=1 docker build --network "$build_network" "${build_args[@]}" \
        --file "$dir/Dockerfile" --tag "$tag" "$@" "$root"
}

compose() {
    docker compose --project-name datadesigner --env-file /dev/null \
        --file "$dir/compose/compose.app.yml" "$@"
}

host_identity() {
    caller_uid="$(id -u)"
    DOCKER_USER="$(id -un)"
    if [[ $caller_uid == 0 && -n ${SUDO_USER:-} ]]; then
        DOCKER_USER="$SUDO_USER"
    fi
    DOCKER_USER_ID="$(id -u "$DOCKER_USER")"
    DOCKER_GRP="$(id -gn "$DOCKER_USER")"
    DOCKER_GRP_ID="$(id -g "$DOCKER_USER")"
    [[ $DOCKER_USER_ID != 0 ]] || die 'Run container commands as a non-root host user (or via sudo from that user).'
    export DOCKER_USER DOCKER_USER_ID DOCKER_GRP DOCKER_GRP_ID
}

prepare_dirs() {
    local path
    for path in "$dir/state" "$dir/home"; do
        [[ ! -d $path ]] || continue
        if [[ $caller_uid == 0 ]]; then
            install -d -m 700 -o "$DOCKER_USER_ID" -g "$DOCKER_GRP_ID" -- "$path"
        else
            (umask 077 && mkdir -p -- "$path")
        fi
    done
}

start_container() {
    prepare_dirs
    compose up -d --wait "$@" datadesigner
}

check_container_user() {
    if ! compose exec -T --user "$DOCKER_USER" datadesigner sh -c \
        '[ "$(id -u):$(id -g):$HOME" = "$1" ]' sh "$DOCKER_USER_ID:$DOCKER_GRP_ID:/home/$DOCKER_USER" </dev/null; then
        die 'Start the container as the current host user, or run recreate after changing users.'
    fi
}

action="${1:-help}"
[[ $# == 0 ]] || shift
case "$action" in
    help|-h|--help) usage; exit ;;
    build)
        [[ $# -ge 2 && $1 == prod && -n $2 && $2 != -* ]] || die 'Use build prod TAG [docker build arguments].'
        shift
        build_image "$@"
        exit
        ;;
    start|recreate|stop|restart|down|status|config|into)
        [[ $# == 0 ]] || die "$action accepts no extra arguments."
        ;;
    exec)
        [[ $# -ge 1 && -n $1 && $1 != -* ]] || die 'Use exec COMMAND [ARGS].'
        ;;
    logs) ;;
    *) die "Unknown command: $action (see help)." ;;
esac

host_identity

case "$action" in
    start) start_container ;;
    recreate) start_container --force-recreate ;;
    stop) compose stop datadesigner ;;
    restart) compose restart datadesigner; start_container ;;
    down) compose down ;;
    status) compose ps --all ;;
    config) compose config --quiet; printf '%s\n' 'datadesigner: configuration valid' ;;
    logs) compose logs "$@" datadesigner ;;
    into)
        check_container_user
        tty_args=()
        if [[ ! -t 0 || ! -t 1 ]]; then
            tty_args=(-T)
        fi
        compose exec "${tty_args[@]}" --user "$DOCKER_USER" datadesigner bash --login
        ;;
    exec)
        check_container_user
        compose exec -T --user "$DOCKER_USER" datadesigner "$@"
        ;;
esac
