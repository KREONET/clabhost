#!/usr/bin/env bash
# clabhost -- install and maintain a containerlab host with a web front end.
#
#   install.sh install [--user NAME] [--ext-set SET] [--no-ufw] [--ref REF]
#   install.sh update [--no-native] [--ref REF]
#   install.sh check       report on what is running
#
# update pulls the repository, upgrades the natively installed components, and
# restarts what needs it. --no-native leaves containerlab, clab-api-server and
# code-server at their current versions.
#
# Safe to re-run: every step checks before it acts, and an existing .env is
# amended rather than replaced.
#
# There is no uninstall. Removing a lab host is faster and more certain by
# rebuilding the machine than by unwinding an install, and an uninstaller would
# give false comfort -- lab images, firewall rules on the hypervisor and DNS
# records all live somewhere else. To stop the stack:
#
#   cd /opt/clabhost && docker compose down
set -euo pipefail

REPO_URL="${CLABHOST_REPO:-https://github.com/kreonet/clabhost}"
PREFIX="${CLABHOST_PREFIX:-/opt/clabhost}"
REF="main"
TARGET_USER=""
EXT_SET=""
USE_UFW=1
UPDATE_NATIVE=1

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n'  "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n'  "$*" >&2; exit 1; }
ok()   { printf '    \033[1;32mok\033[0m   %s\n' "$*"; }
bad()  { printf '    \033[1;31mfail\033[0m %s\n' "$*"; }

usage() { sed -n '2,13s/^#\( \|$\)//p' "$0"; }

# ── Where is the source ───────────────────────────────────────────────────────
# The script runs two ways: from a checkout, or piped from curl. The presence of
# a compose file next to it decides which, so a checkout is never overwritten by
# a clone of itself.
script_dir() {
    local src="${BASH_SOURCE[0]:-}"
    [ -n "$src" ] && [ -f "$src" ] || return 1
    cd "$(dirname "$(readlink -f "$src")")" && pwd
}

fetch_source() {
    local here
    if here="$(script_dir)" && [ -f "$here/docker-compose.yml" ]; then
        PREFIX="$here"
        info "using the checkout at $PREFIX"
        return
    fi
    command -v git >/dev/null || die "git is required to fetch the repository"
    if [ -d "$PREFIX/.git" ]; then
        info "refreshing $PREFIX"
        git -C "$PREFIX" fetch --quiet origin "$REF"
        git -C "$PREFIX" checkout --quiet "$REF"
        git -C "$PREFIX" merge --quiet --ff-only "origin/$REF"
    else
        [ -e "$PREFIX" ] && die "$PREFIX exists and is not a git checkout"
        info "cloning $REPO_URL into $PREFIX"
        git clone --quiet --branch "$REF" "$REPO_URL" "$PREFIX"
    fi
}

compose() { docker compose --project-directory "$PREFIX" "$@"; }

# ── Preflight ─────────────────────────────────────────────────────────────────
preflight() {
    [ "$(id -u)" -eq 0 ] || die "run as root (sudo)"

    . /etc/os-release 2>/dev/null || die "cannot read /etc/os-release"
    case "$ID" in
        ubuntu|debian) : ;;
        rhel|rocky|almalinux|centos|fedora) : ;;
        *) warn "${PRETTY_NAME:-$ID} is untested; Ubuntu 24.04 or later is the reference" ;;
    esac

    command -v docker >/dev/null || die "Docker is required: https://docs.docker.com/engine/install/"
    docker compose version >/dev/null 2>&1 \
        || die "the docker compose plugin is missing (the standalone docker-compose is not enough)"
    # The snap build puts docker in a confinement where bind mounts from /opt and
    # host binaries do not resolve the same way. Catch it here rather than as a
    # container that starts and then behaves strangely.
    docker info >/dev/null 2>&1 || die "cannot talk to the Docker daemon"
    if [ -e /snap/bin/docker ]; then
        warn "snap Docker detected; the Docker CE packages are what this is tested on"
    fi

    [ -e /dev/kvm ] || warn "/dev/kvm is absent -- VM-based nodes (vrnetlab) will not run"
}

# ── Native components ─────────────────────────────────────────────────────────
install_native() {
    if command -v containerlab >/dev/null; then
        ok "containerlab $(containerlab version 2>/dev/null | awk '/version:/{print $2; exit}')"
    else
        info "installing containerlab"
        curl -sL https://containerlab.dev/setup | bash -s "all"
    fi

    if command -v clab-api-server >/dev/null; then
        ok "clab-api-server present"
    else
        info "installing clab-api-server"
        curl -fsSL https://raw.githubusercontent.com/srl-labs/clab-api-server/main/install.sh \
            | bash -s -- install
    fi
}

# The API server only ever answers Caddy and containerlab-web over loopback.
# Leaving its own TLS on means a self-signed certificate that every client --
# the web app, the VS Code extension's Node process -- has to be told to trust,
# for a connection that never leaves the host.
configure_api() {
    local env=/etc/clab-api-server/clab-api-server.env
    [ -f "$env" ] || { warn "$env not found; skipping API configuration"; return; }
    local changed=0
    set_kv() {
        local key="$1" val="$2"
        grep -q "^${key}=" "$env" || { printf '%s=%s\n' "$key" "$val" >> "$env"; changed=1; return; }
        if grep -q "^${key}=${val}$" "$env"; then return; fi
        sed -i "s|^${key}=.*|${key}=${val}|" "$env"
        changed=1
    }
    set_kv TLS_ENABLE false
    set_kv TLS_AUTO_CERT false
    set_kv API_SERVER_HOST localhost
    set_kv API_USER_GROUP clab_api
    set_kv SUPERUSER_GROUP clab_admins
    if [ "$changed" = 1 ]; then
        info "updated $env"
        systemctl restart clab-api-server
    fi
    systemctl enable --quiet --now clab-api-server 2>/dev/null || true
}

# ── Account ───────────────────────────────────────────────────────────────────
setup_user() {
    if [ -z "$TARGET_USER" ]; then
        TARGET_USER="${SUDO_USER:-}"
        [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != root ] \
            || die "cannot tell which account to use; pass --user NAME"
    fi
    id "$TARGET_USER" >/dev/null 2>&1 || die "no such user: $TARGET_USER"

    for g in docker clab_api clab_admins; do
        getent group "$g" >/dev/null || groupadd -f "$g"
        id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx "$g" || {
            usermod -aG "$g" "$TARGET_USER"
            info "$TARGET_USER: added to $g"
        }
    done

    # PAM checks the Linux password, so an account without one cannot sign in.
    # The failure is indistinguishable from a typo, so ask for it here.
    if [ "$(passwd --status "$TARGET_USER" | awk '{print $2}')" != P ]; then
        warn "$TARGET_USER has no password set; sign-in will fail until it has one"
        info "set one now with: sudo passwd $TARGET_USER"
    fi

    local home
    home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    # clab-api-server stores labs in ~/.clab -- hardcoded, not configurable. The
    # editor opens ~/clab, a symlink, because a dotted directory does not show
    # up in the file explorer.
    install -d -o "$TARGET_USER" -g "$(id -g "$TARGET_USER")" -m 0750 "$home/.clab"
    if [ ! -e "$home/clab" ]; then
        ln -sfn "$home/.clab" "$home/clab"
        chown -h "$TARGET_USER:$(id -g "$TARGET_USER")" "$home/clab"
    fi
}

# ── Firewall ──────────────────────────────────────────────────────────────────
# Docker inserts its own rules into DOCKER-USER and FORWARD, so a published port
# is open regardless of what ufw says. ufw-docker closes that. See
# docs/firewall.ko.md.
setup_ufw() {
    [ "$USE_UFW" = 1 ] || return 0
    command -v ufw >/dev/null || { info "ufw is not installed; skipping"; return 0; }

    if [ ! -x /usr/local/bin/ufw-docker ]; then
        info "installing ufw-docker"
        curl -fsSL -o /usr/local/bin/ufw-docker \
            https://raw.githubusercontent.com/chaifeng/ufw-docker/master/ufw-docker
        chmod +x /usr/local/bin/ufw-docker
    fi
    if ! grep -q 'ufw-docker' /etc/ufw/after.rules 2>/dev/null; then
        /usr/local/bin/ufw-docker install
        systemctl restart ufw
        info "ufw-docker installed; published container ports are now filtered"
    else
        ok "ufw-docker already installed"
    fi
    warn "no source range is allowed yet. Open port ${HTTP_PORT:-80} to your network:"
    warn "  sudo ufw route allow proto tcp from YOUR_CIDR to any port ${HTTP_PORT:-80}"
}

# ── Configuration ─────────────────────────────────────────────────────────────
# Values already in .env win. Detection only fills what is missing, so a hand
# edit survives every later run.
write_env() {
    local env="$PREFIX/.env"
    [ -f "$env" ] || { install -m 0640 /dev/null "$env"; info "creating $env"; }

    local home uid gid docker_gid admins_gid docker_bin host_ip
    home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    uid="$(id -u "$TARGET_USER")"
    gid="$(id -g "$TARGET_USER")"
    docker_gid="$(getent group docker | cut -d: -f3)"
    admins_gid="$(getent group clab_admins | cut -d: -f3)"
    docker_bin="$(command -v docker)"
    host_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')"

    put() {
        local key="$1" val="$2"
        if grep -q "^${key}=" "$env"; then
            # An empty value counts as unset: install.sh writes placeholders and
            # this is what fills them in on the next run.
            grep -q "^${key}=$" "$env" || return 0
            sed -i "s|^${key}=$|${key}=${val}|" "$env"
        else
            printf '%s=%s\n' "$key" "$val" >> "$env"
        fi
    }

    put HOST_IP          "$host_ip"
    put HTTP_PORT        "${HTTP_PORT:-80}"
    put CLAB_API_URL     "http://127.0.0.1:8090"
    put CLAB_USER        "$TARGET_USER"
    put CLAB_HOME        "$home"
    put CLAB_UID         "$uid"
    put CLAB_GID         "$gid"
    put DOCKER_GID       "$docker_gid"
    put CLAB_ADMINS_GID  "$admins_gid"
    put DOCKER_BIN       "$docker_bin"
    put DATA_DIR         "/opt/clabhost/data"
    put SOCKET_DIR       "/run/clabhost"
    put EXT_SET          "${EXT_SET:-full}"
    put PROM_RETENTION   "30d"
    put PROM_MAX_SIZE    "8GB"
    put INTERNAL_SUBNET  "172.30.255.0/24"
    chmod 0640 "$env"

    # A value that was already there but points at a group that has since been
    # renumbered would make the editor silently lose docker access.
    local cur
    cur="$(grep '^DOCKER_GID=' "$env" | cut -d= -f2)"
    [ "$cur" = "$docker_gid" ] || warn "DOCKER_GID in .env is $cur but the host group is $docker_gid"
}

make_dirs() {
    # shellcheck disable=SC1091
    . "$PREFIX/.env"

    # A bind mount does not inherit ownership from the image the way a fresh
    # named volume does: an empty host directory is root-owned, and a service
    # that runs unprivileged then cannot write to it. So each one is created
    # here with the uid its service actually runs as.
    # chown rather than `install -o`: the uid Grafana runs as has no account on
    # the host, and coreutils here refuses a numeric argument it cannot resolve.
    install -d -m 0755 "$DATA_DIR"
    # caddy runs as root in its container. 0700 because /data holds the ACME
    # account key and the certificates.
    install -d -m 0700 "$DATA_DIR/caddy" "$DATA_DIR/caddy/data" "$DATA_DIR/caddy/config"
    # prometheus runs with user: root in docker-compose.yml.
    install -d -m 0755 "$DATA_DIR/prometheus"
    # grafana/grafana runs as uid 472, gid 0.
    install -d -m 0755 "$DATA_DIR/grafana"
    chown 472:0 "$DATA_DIR/grafana"
    # The editor runs as the account, natively.
    install -d -m 0755 "$DATA_DIR/code-server" \
        "$DATA_DIR/code-server/extensions" \
        "$DATA_DIR/code-server/user-data"
    chown "$CLAB_UID:$CLAB_GID" "$DATA_DIR/code-server" \
        "$DATA_DIR/code-server/extensions" \
        "$DATA_DIR/code-server/user-data"

    # /run is a tmpfs, so this is gone after every boot; tmpfiles.d puts it
    # back. Grafana needs its own subdirectory because it runs as uid 472 and
    # the editor's directory belongs to the account.
    install -d -m 0755 "$SOCKET_DIR"
    chown "$CLAB_UID:$CLAB_GID" "$SOCKET_DIR"
    install -d -m 0755 "$SOCKET_DIR/grafana"
    chown 472:0 "$SOCKET_DIR/grafana"
    cat > /etc/tmpfiles.d/clabhost.conf <<TMPF
d ${SOCKET_DIR} 0755 ${CLAB_UID} ${CLAB_GID} -
d ${SOCKET_DIR}/grafana 0755 472 0 -
TMPF
}

# ── Browser editor ──────────────────────────────────────────────────────────
# On the host, not in a container. The reason is the terminal: the point of an
# editor on a lab host is that you can drop into a shell, sudo, and reach the
# host's own tools -- containerlab, tc/netem, tcpdump, whatever you installed
# last week. A container gives you the container's filesystem and the image's
# tools instead, and anything you install there is gone on the next recreate.
#
# This costs nothing at the proxy: Caddy connects to a unix socket either way.
install_code_server() {
    # shellcheck disable=SC1091
    . "$PREFIX/.env"

    if command -v code-server >/dev/null; then
        ok "code-server $(code-server --version 2>/dev/null | awk 'NR==1{print $1}')"
    else
        info "installing code-server"
        # --method standalone --prefix /usr/local, not the installer's
        # defaults. Detection puts a .deb in /usr/bin on Debian, which is fine
        # until a host already has a standalone install in /usr/local/bin: PATH
        # finds the old one, the unit is rendered against it, and every later
        # upgrade lands somewhere the service never looks. And the standalone
        # default prefix is ~/.local, which under sudo is root's home. One
        # method, one path.
        curl -fsSL https://code-server.dev/install.sh \
            | sh -s -- --method standalone --prefix /usr/local
        command -v code-server >/dev/null || die "code-server install failed"
    fi

    # Two installs on PATH is the failure above, already happened. Worth saying
    # out loud rather than leaving someone to wonder why an upgrade did nothing.
    if dpkg -s code-server >/dev/null 2>&1 && [ "$(command -v code-server)" != /usr/bin/code-server ]; then
        warn "code-server is installed twice: the deb in /usr/bin and $(command -v code-server)"
        warn "  the service uses the one on PATH; remove the other to stop them diverging"
    fi

    local bin unit=/etc/systemd/system/clabhost-code.service
    bin="$(command -v code-server)"
    sed -e "s|@USER@|$CLAB_USER|g" \
        -e "s|@GROUP@|$(id -gn "$CLAB_USER")|g" \
        -e "s|@HOME@|$CLAB_HOME|g" \
        -e "s|@SOCKET_DIR@|$SOCKET_DIR|g" \
        -e "s|@DATA_DIR@|$DATA_DIR|g" \
        -e "s|@CODE_SERVER@|$bin|g" \
        "$PREFIX/code-server/clabhost-code.service" > "$unit"
    systemctl daemon-reload
    systemctl enable --quiet clabhost-code.service
}

seed_extensions() {
    # shellcheck disable=SC1091
    . "$PREFIX/.env"
    info "extensions (set '${EXT_SET:-full}')"
    # As the account, so everything it writes is already owned correctly.
    sudo -u "$CLAB_USER" \
        EXT_DIR="$DATA_DIR/code-server/extensions" \
        EXT_SET="${EXT_SET:-full}" \
        EXT_UPDATE="${EXT_UPDATE:-0}" \
        CODE_SERVER="$(command -v code-server)" \
        sh "$PREFIX/code-server/seed-extensions.sh" || warn "extension seeding reported errors"

    # Hand the same list to the editor as workspace recommendations. Redundant
    # when seeding worked; when it did not, it is the only one-click retry a
    # user has. Seeded once -- after that the file is theirs.
    local rec="$DATA_DIR/code-server/extensions/.recommendations.json"
    local ws="$CLAB_HOME/clab/.vscode"
    if [ -f "$rec" ] && [ ! -f "$ws/extensions.json" ]; then
        install -d -m 0755 "$ws"
        install -m 0644 "$rec" "$ws/extensions.json"
        chown -R "$CLAB_UID:$CLAB_GID" "$ws"
    fi
}

# ── Native upgrades ─────────────────────────────────────────────────────────
# Three components live on the host, and each has its own way of being upgraded.
# Doing it here means `update` leaves nothing at an old version by accident,
# which is the usual reason a host drifts.
update_native() {
    [ "$UPDATE_NATIVE" = 1 ] || { info "skipping native upgrades (--no-native)"; return 0; }

    # containerlab ships from the netdevops apt repository, so apt is the
    # answer. `containerlab version upgrade` also exists, but it fetches an
    # installer from GitHub and leaves apt unaware of what is installed.
    if dpkg -s containerlab >/dev/null 2>&1; then
        local before after
        before="$(dpkg-query -W -f='${Version}' containerlab 2>/dev/null)"
        apt-get update -qq
        # A .deb installed with `dpkg -i` leaves no repository behind, so apt
        # has nothing newer to offer and --only-upgrade is a silent no-op. Say
        # so rather than reporting the current version as if it were the latest.
        if [ -z "$(apt-cache madison containerlab 2>/dev/null)" ]; then
            warn "containerlab $before: no apt repository configured, so this cannot upgrade it"
            warn "  add the netdevops repository, or re-run https://containerlab.dev/setup"
        else
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --only-upgrade containerlab
            after="$(dpkg-query -W -f='${Version}' containerlab 2>/dev/null)"
            if [ "$before" = "$after" ]; then
                ok "containerlab $after"
            else
                info "containerlab $before -> $after"
            fi
        fi
    else
        warn "containerlab was not installed from apt; upgrade it however it was installed"
    fi

    # The API server's own installer has an upgrade subcommand. It restarts the
    # service, and containerlab-web keeps its sessions in memory upstream of
    # that, so anyone signed in is signed out.
    # Only upgrade a binary that came from a release. A version string with a
    # suffix on it -- v0.6.0-chownfix -- is somebody's own build, and replacing
    # it with the official release silently drops whatever it was patched for.
    if command -v clab-api-server >/dev/null; then
        local apiv
        apiv="$(clab-api-server --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+[^ ]*' | head -1)"
        if [ -n "$apiv" ] && ! printf '%s' "$apiv" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
            warn "clab-api-server $apiv looks like a local build; leaving it alone"
            warn "  upgrade it yourself, or rebuild from the release this should track"
        else
            info "clab-api-server: upgrading (this signs out anyone using the web UI)"
            curl -fsSL https://raw.githubusercontent.com/srl-labs/clab-api-server/main/install.sh \
                | bash -s -- upgrade
            configure_api
        fi
    fi

    # The official code-server installer is idempotent and upgrades in place;
    # it prints "already installed" when there is nothing to do.
    if command -v code-server >/dev/null; then
        local bin cv_before cv_after
        # The binary on PATH is the one the unit was rendered against, so that
        # is the one whose version means anything here.
        bin="$(command -v code-server)"
        cv_before="$("$bin" --version 2>/dev/null | awk 'NR==1{print $1}')"
        # --prefix as well: the standalone default is ~/.local, which under
        # sudo means root's home and not the path the unit points at.
        curl -fsSL https://code-server.dev/install.sh \
            | sh -s -- --method standalone --prefix /usr/local
        cv_after="$("$bin" --version 2>/dev/null | awk 'NR==1{print $1}')"
        if [ "$cv_before" = "$cv_after" ]; then
            ok "code-server $cv_after"
        else
            info "code-server $cv_before -> $cv_after"
        fi
    fi
}

# ── Commands ──────────────────────────────────────────────────────────────────
cmd_install() {
    preflight
    install_native
    configure_api
    setup_user
    fetch_source
    write_env
    make_dirs
    setup_ufw

    info "starting the web stack"
    compose up -d

    install_code_server
    # After the stack, so a slow extension download does not hold up the web UI.
    seed_extensions
    systemctl restart clabhost-code.service

    # shellcheck disable=SC1091
    . "$PREFIX/.env"
    echo
    info "http://${HOST_IP:-<server-ip>}:${HTTP_PORT:-80}/  -- sign in as $CLAB_USER"
    info "group membership only applies to new logins; run 'newgrp docker' or re-login"
}

cmd_update() {
    [ "$(id -u)" -eq 0 ] || die "run as root (sudo)"
    fetch_source
    # shellcheck disable=SC1091
    . "$PREFIX/.env"
    TARGET_USER="$CLAB_USER"
    write_env
    make_dirs
    update_native
    # --ignore-buildable: a host that builds its own image (Caddy with a DNS
    # plugin, say) has no registry to pull it from, and without this the pull
    # fails and takes the rest of update with it.
    compose pull --quiet --ignore-buildable
    compose up -d
    # The Caddyfile and prometheus.yml are single-file bind mounts. A git pull
    # replaces the file, which gives it a new inode, and the running container
    # keeps reading the old one.
    compose restart caddy prometheus
    # The unit is rendered from the repository, so a pull can change it.
    install_code_server
    seed_extensions
    systemctl restart clabhost-code.service
    info "updated"
}

cmd_check() {
    # Unlike install, check must not touch git. Resolve the checkout it is run
    # from so `./install.sh check` works outside /opt/clabhost.
    local here
    if here="$(script_dir)" && [ -f "$here/docker-compose.yml" ]; then PREFIX="$here"; fi
    [ -f "$PREFIX/.env" ] || die "no .env at $PREFIX -- run install first"
    # shellcheck disable=SC1091
    . "$PREFIX/.env"
    local rc=0

    info "native"
    command -v containerlab >/dev/null && ok "containerlab" || { bad "containerlab"; rc=1; }
    systemctl is-active --quiet clab-api-server && ok "clab-api-server" || { bad "clab-api-server"; rc=1; }
    curl -fsS -o /dev/null "${CLAB_API_URL}/health" 2>/dev/null \
        && ok "API ${CLAB_API_URL}/health" || { bad "API ${CLAB_API_URL}/health"; rc=1; }

    info "containers"
    for c in caddy web auth grafana prometheus node-exporter cadvisor; do
        local state
        state="$(docker inspect -f '{{.State.Status}}' "clabhost-$c" 2>/dev/null || echo missing)"
        [ "$state" = running ] && ok "$c" || { bad "$c ($state)"; rc=1; }
    done

    info "editor"
    command -v code-server >/dev/null && ok "code-server installed" \
        || { bad "code-server is not installed"; rc=1; }
    systemctl is-active --quiet clabhost-code.service && ok "clabhost-code.service" \
        || { bad "clabhost-code.service is not running"; rc=1; }
    [ -S "${SOCKET_DIR}/ide.sock" ] && ok "socket ${SOCKET_DIR}/ide.sock" \
        || { bad "socket ${SOCKET_DIR}/ide.sock"; rc=1; }
    local ext="${DATA_DIR}/code-server/extensions" n
    n="$(find "$ext" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)"
    [ "$n" -gt 0 ] && ok "$n extensions" || { bad "no extensions installed"; rc=1; }
    if [ -f "$ext/.install-failures" ]; then
        warn "some extensions failed: $(tr '\n' ' ' < "$ext/.install-failures")"
    fi

    info "grafana socket"
    [ -S "${SOCKET_DIR}/grafana/grafana.sock" ] && ok "socket ${SOCKET_DIR}/grafana/grafana.sock" \
        || { bad "socket ${SOCKET_DIR}/grafana/grafana.sock"; rc=1; }

    info "metrics"
    # Empty cAdvisor series means every per-container panel is blank. It is the
    # one failure here that still leaves the dashboard looking merely idle.
    for q in "count(node_cpu_seconds_total)" "count(container_last_seen)"; do
        local v
        v="$(docker exec clabhost-prometheus wget -qO- \
             "http://localhost:9090/api/v1/query?query=$(printf '%s' "$q" | sed 's/(/%28/g;s/)/%29/g')" \
             2>/dev/null | sed -n 's/.*"value":\[[^,]*,"\([0-9]*\)".*/\1/p')"
        [ -n "${v:-}" ] && [ "$v" != 0 ] && ok "$q = $v" || { bad "$q is empty"; rc=1; }
    done

    # A site put behind TLS answers plain HTTP with a 308 to https, so probing
    # 127.0.0.1:80 would report a failure that is really the correct behaviour.
    # SITE_URL names what to probe when the Caddyfile no longer serves :80.
    local base="${SITE_URL:-http://127.0.0.1:${HTTP_PORT:-80}}"
    info "http ($base)"
    local code
    code="$(curl -sk -o /dev/null -w '%{http_code}' "$base/login")"
    [ "$code" = 200 ] && ok "/login $code" || { bad "/login $code"; rc=1; }
    # Accept: text/html because that is what makes the shim answer a browser
    # navigation with a redirect to /login instead of a bare 401.
    code="$(curl -sk -o /dev/null -w '%{http_code}' -H 'Accept: text/html' "$base/")"
    [ "$code" = 302 ] && ok "/ $code (redirects to sign-in)" \
        || { bad "/ $code (expected 302 without a session)"; rc=1; }

    return $rc
}

# ── Entry ─────────────────────────────────────────────────────────────────────
cmd="${1:-}"
[ $# -gt 0 ] && shift || true
while [ $# -gt 0 ]; do
    case "$1" in
        --user)    TARGET_USER="${2:?--user needs a name}"; shift 2 ;;
        --ext-set) EXT_SET="${2:?--ext-set needs minimal|network|full}"; shift 2 ;;
        --ref)     REF="${2:?--ref needs a branch or tag}"; shift 2 ;;
        --no-ufw)  USE_UFW=0; shift ;;
        --no-native) UPDATE_NATIVE=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

case "$cmd" in
    install) cmd_install ;;
    update)  cmd_update ;;
    check)   cmd_check ;;
    -h|--help|"") usage ;;
    *) die "unknown command: $cmd" ;;
esac
