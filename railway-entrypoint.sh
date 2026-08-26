#!/bin/sh
# Boot code-server on Railway.
#
# Runs as root (the template sets RAILWAY_RUN_UID=0) so it can repair the
# volume, then hands over to uid 1000 for the server itself.
set -eu

PREFIX="[railway-entrypoint]"
CODER_UID=1000
CODER_GID=1000
HOME_DIR=/home/coder
PROJECT_DIR="${CODE_SERVER_PROJECT_DIR:-$HOME_DIR/project}"

# 1. Refuse to boot without a password.
#
# code-server generates a random password into
# $HOME/.config/code-server/config.yaml when neither PASSWORD nor
# HASHED_PASSWORD is set. That password is only ever printed to the deploy
# log, and on a deploy with no volume it is regenerated on every redeploy.
if [ -z "${PASSWORD:-}" ] && [ -z "${HASHED_PASSWORD:-}" ]; then
    echo "$PREFIX FATAL: neither PASSWORD nor HASHED_PASSWORD is set." >&2
    echo "$PREFIX Set PASSWORD to a value you control; refusing to serve an editor with a log-only password." >&2
    exit 1
fi

# 2. Repair the volume.
#
# Railway mounts volumes owned by uid 0 while this image runs as uid 1000.
# chown -R over a home directory that has grown large is slow, so only recurse
# when the mount root itself is still wrong; otherwise fix the paths we create.
mkdir -p "$HOME_DIR" "$PROJECT_DIR" \
         "$HOME_DIR/.config/code-server" \
         "$HOME_DIR/.local/share/code-server" \
         "$HOME_DIR/.local/share/code-server/coder-logs" \
         "$HOME_DIR/.cache" \
         "$HOME_DIR/.ssh"
chmod 700 "$HOME_DIR/.ssh"

owner="$(stat -c '%u:%g' "$HOME_DIR")"
if [ "$owner" != "$CODER_UID:$CODER_GID" ]; then
    echo "$PREFIX $HOME_DIR owned by $owner, repairing to $CODER_UID:$CODER_GID"
    chown -R "$CODER_UID:$CODER_GID" "$HOME_DIR"
else
    chown "$CODER_UID:$CODER_GID" \
        "$PROJECT_DIR" \
        "$HOME_DIR/.config" "$HOME_DIR/.config/code-server" \
        "$HOME_DIR/.local" "$HOME_DIR/.local/share" "$HOME_DIR/.local/share/code-server" \
        "$HOME_DIR/.local/share/code-server/coder-logs" \
        "$HOME_DIR/.local/share/code-server/coder-logs/"*.log \
        "$HOME_DIR/.cache" "$HOME_DIR/.ssh"
fi
echo "$PREFIX $HOME_DIR owner=$(stat -c '%u:%g' "$HOME_DIR")"

# 3. Restore the home skeleton the mount hides.
for f in .bashrc .profile .bash_logout; do
    if [ ! -e "$HOME_DIR/$f" ] && [ -e "/opt/coder-skel/$f" ]; then
        cp -a "/opt/coder-skel/$f" "$HOME_DIR/$f"
        chown "$CODER_UID:$CODER_GID" "$HOME_DIR/$f"
        echo "$PREFIX restored $f"
    fi
done

# 4. Optional git clone, guarded against an existing checkout.
#
# Upstream's template clones unconditionally, which fails on every boot after
# the first once the directory persists.
if [ -n "${GIT_REPO:-}" ]; then
    if [ -d "$PROJECT_DIR/.git" ]; then
        echo "$PREFIX $PROJECT_DIR already holds a git checkout, leaving it alone"
    elif [ -n "$(ls -A "$PROJECT_DIR" 2>/dev/null || true)" ]; then
        echo "$PREFIX $PROJECT_DIR is not empty, skipping clone of $GIT_REPO"
    else
        echo "$PREFIX cloning $GIT_REPO into $PROJECT_DIR"
        setpriv --reuid="$CODER_UID" --regid="$CODER_GID" --init-groups \
            git clone "$GIT_REPO" "$PROJECT_DIR" || \
            echo "$PREFIX WARNING: clone failed, continuing with an empty project directory"
    fi
fi

# 5. Honour Railway's injected port.
#
# The base image bakes `--bind-addr 0.0.0.0:8080` into its ENTRYPOINT. Railway
# injects $PORT into every service and its HTTP healthcheck dials the injected
# port, not the domain's target port, so the app must follow $PORT.
PORT="${PORT:-8080}"
# Do NOT invoke code-server as root here, even for --version: it creates
# $HOME/.local/share/code-server/coder-logs owned by uid 0 on the volume,
# and the real server then fails to open its own log file. The version is
# baked into the image instead.
echo "$PREFIX code-server ${CODE_SERVER_VERSION:-unknown} binding 0.0.0.0:$PORT project=$PROJECT_DIR"

export HOME="$HOME_DIR"
export USER=coder
export XDG_CONFIG_HOME="$HOME_DIR/.config"
export XDG_DATA_HOME="$HOME_DIR/.local/share"
export XDG_CACHE_HOME="$HOME_DIR/.cache"

# fixuid is not run here: it exists to reconcile a host uid at `docker run`
# time and Railway always starts this container the same way. Handing over
# directly also means no start command can accidentally replace this script.
exec setpriv --reuid="$CODER_UID" --regid="$CODER_GID" --init-groups \
    /usr/bin/dumb-init /usr/bin/code-server \
        --bind-addr "0.0.0.0:$PORT" \
        --disable-telemetry \
        --disable-update-check \
        "$PROJECT_DIR"
