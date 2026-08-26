# Railway-ready code-server (VS Code in the browser).
#
# Upstream ships a uid-1000 image with no VOLUME and a hardcoded listen port.
# Railway mounts volumes owned by uid 0 and injects its own $PORT, so the stock
# image crashes with `EACCES: permission denied, mkdir '/home/coder/.config'`
# the moment a volume is attached at the home directory. This wrapper repairs
# the mount as root, seeds the home skeleton the mount hides, honours the
# injected port, and drops back to uid 1000 before code-server starts.
FROM codercom/code-server:4.134.0

USER root

# The volume is mounted at /home/coder, which hides the skeleton dotfiles the
# base image wrote there. Keep a pristine copy outside the mount and restore
# any that are missing on each boot.
RUN mkdir -p /opt/coder-skel \
 && cp -a /home/coder/.bashrc /home/coder/.profile /home/coder/.bash_logout /opt/coder-skel/ \
 && chown -R 1000:1000 /opt/coder-skel

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

# Sanity: the assumptions this wrapper is built on must still hold.
RUN set -eux; \
    [ "$(id -u coder)" = "1000" ]; \
    command -v setpriv; \
    command -v dumb-init; \
    /usr/bin/code-server --version | grep -q '^4\.134\.0'

ENV HOME=/home/coder \
    USER=coder \
    CODE_SERVER_VERSION=4.134.0 \
    CODE_SERVER_PROJECT_DIR=/home/coder/project

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
