# code-server on Railway

A Railway-ready wrapper around [code-server](https://github.com/coder/code-server)
4.134.0 (VS Code 1.135.0) — full VS Code in the browser, with a terminal, the
extension marketplace, and your files on a persistent volume.

Published as `ghcr.io/bon5co/code-server-railway:4.134.0`.

## What this wrapper adds

The upstream image is excellent and needs no patching to run locally. It is not
deployable on Railway as-is, for four reasons:

1. **Railway mounts volumes owned by uid 0**, and the image runs as `coder`
   (uid 1000). Attaching a volume at `/home/coder` — the only path that covers
   project files, settings, installed extensions and SSH keys — makes the stock
   image exit immediately with
   `EACCES: permission denied, mkdir '/home/coder/.config'`. This entrypoint
   runs as root, repairs the mount, and drops to uid 1000 with `setpriv`.
2. **A volume mount hides what the image build wrote underneath it.** The base
   image's home skeleton (`.bashrc`, `.profile`, `.bash_logout`) disappears the
   moment the volume is attached. A pristine copy is kept in `/opt/coder-skel`
   and restored on each boot.
3. **The base image bakes `--bind-addr 0.0.0.0:8080` into its ENTRYPOINT**,
   while Railway injects its own `$PORT` and dials that injected port for the
   HTTP healthcheck. The entrypoint binds whatever Railway injects.
4. **code-server generates a random password when none is set**, writes it to
   `~/.config/code-server/config.yaml`, and prints it only to the deploy log.
   This entrypoint refuses to boot unless `PASSWORD` or `HASHED_PASSWORD` is
   set, so the credential is one the deployer chose and it survives redeploys.

It also guards the optional `GIT_REPO` clone against an existing checkout, so a
redeploy does not fail on a directory that is already populated.

## Variables

| Variable | Required | Purpose |
| --- | --- | --- |
| `PASSWORD` | yes (unless `HASHED_PASSWORD`) | Login password for the editor. |
| `HASHED_PASSWORD` | no | Argon2 hash, as an alternative to `PASSWORD`. |
| `GIT_REPO` | no | Cloned into the project directory on first boot only. |
| `CODE_SERVER_PROJECT_DIR` | no | Defaults to `/home/coder/project`. |

`PORT` is injected by Railway and must not be set by hand.

## Volume

Mount one volume at `/home/coder`. It carries the project directory, editor
settings, installed extensions (`~/.local/share/code-server`), the extension
cache and `~/.ssh`.

## Healthcheck

`/healthz` answers 200 without authentication.
