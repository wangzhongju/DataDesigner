#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

die() {
    printf '%s\n' "$*" >&2
    exit 2
}

# Install a complete file only if no personal copy already exists.
install_profile() {
    local target="$HOME/$1" temporary
    shift
    [[ ! -e $target && ! -L $target ]] || return 0
    temporary=$(mktemp "$HOME/.datadesigner-profile.XXXXXX")
    if "$@" > "$temporary" && {
        ln -T -- "$temporary" "$target" 2>/dev/null || [[ -e $target || -L $target ]]
    }; then
        rm -f -- "$temporary"
    else
        rm -f -- "$temporary"
        die "Cannot initialize $target."
    fi
}

shell_profile() {
    cat "/etc/skel/$1"
    printf '\n# DataDesigner environment\n[ ! -f "$HOME/.datadesigner_env" ] || . "$HOME/.datadesigner_env"\n'
    if [[ $1 == .bashrc ]]; then
        cat <<'EOF'
PS1='\[\033[01;32m\]\u@\[\033[01;35m\]\h\[\033[00m\]:\[\033[01;36m\]\w\[\033[00m\]$ '
EOF
    fi
}

initialize_profiles() {
    install_profile .datadesigner_env cat <<'EOF'
export VIRTUAL_ENV=/opt/venv
case ":$PATH:" in
    *:/opt/venv/bin:*) ;;
    *) export PATH="/opt/venv/bin:$PATH" ;;
esac
export EDITOR="${EDITOR:-vim}"
export VISUAL="${VISUAL:-vim}"
export LANG="${LANG:-C.UTF-8}"
EOF
    install_profile .bashrc shell_profile .bashrc
    install_profile .profile shell_profile .profile
    install_profile .vimrc cat <<'EOF'
set encoding=utf-8
set fileencodings=utf-8
set number
set expandtab
set tabstop=4
set shiftwidth=4
syntax on
EOF
}

if (( EUID != 0 )); then
    if [[ ${1:-} == --init-profile ]]; then
        shift
        initialize_profiles
    fi
    exec "$@"
fi

# The Compose entry point supplies the host identity. A standalone Docker
# invocation with no identity uses the account selected by docker run.
if [[ -z ${DOCKER_USER:-} ]]; then
    exec "$@"
fi

user_name=$DOCKER_USER
uid=${DOCKER_USER_ID:?DOCKER_USER_ID is required}
group_name=${DOCKER_GRP:?DOCKER_GRP is required}
gid=${DOCKER_GRP_ID:?DOCKER_GRP_ID is required}
[[ $user_name =~ ^[a-z_][a-z0-9_-]*$ && $group_name =~ ^[a-z_][a-z0-9_-]*$ ]] ||
    die 'Invalid host user or group name.'
[[ $uid =~ ^[1-9][0-9]*$ && $gid =~ ^[1-9][0-9]*$ ]] ||
    die 'The host user and primary group must have nonzero numeric IDs.'

if group=$(getent group "$group_name"); then
    [[ $(cut -d: -f3 <<< "$group") == "$gid" ]] || die "Group $group_name has a different GID."
elif group=$(getent group "$gid"); then
    (( gid >= 1000 )) || die 'Cannot rename a system group.'
    groupmod --new-name "$group_name" "${group%%:*}"
else
    groupadd --gid "$gid" "$group_name"
fi

user_home="/home/$user_name"
if id "$user_name" >/dev/null 2>&1; then
    [[ $(id -u "$user_name") == "$uid" && $(id -g "$user_name") == "$gid" ]] ||
        die "User $user_name has a different UID or GID."
    usermod --home "$user_home" --shell /bin/bash "$user_name"
elif account=$(getent passwd "$uid"); then
    (( uid >= 1000 )) || die 'Cannot rename a system user.'
    usermod --login "$user_name" --home "$user_home" --shell /bin/bash --gid "$gid" "${account%%:*}"
else
    useradd --uid "$uid" --gid "$gid" --home-dir "$user_home" --shell /bin/bash "$user_name"
fi

[[ ! -L $user_home ]] || die "Container HOME cannot be a symlink: $user_home."
if [[ ! -d $user_home ]]; then
    install -d -m 0750 -o "$uid" -g "$gid" "$user_home"
fi
[[ $(stat -c '%u:%g' "$user_home") == "$uid:$gid" ]] || die "Check the ownership of $user_home."

if [[ $(stat -c '%u:%g' /opt/venv) != "$uid:$gid" ]]; then
    chown -hR -- "$uid:$gid" /opt/venv
fi

printf '%s ALL=(ALL:ALL) NOPASSWD:ALL\n' "$user_name" > /etc/sudoers.d/datadesigner-user
chmod 0440 /etc/sudoers.d/datadesigner-user
visudo -cf /etc/sudoers.d/datadesigner-user >/dev/null

export HOME="$user_home" USER="$user_name" LOGNAME="$user_name"
exec setpriv --reuid "$uid" --regid "$gid" --init-groups "$0" --init-profile "$@"
