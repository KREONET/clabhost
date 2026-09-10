# clabhost - a browser-based containerlab development host

[🇺🇸 English](README.md) · [🇰🇷 한국어](README.ko.md)

[clabhost](https://github.com/kreonet/clabhost) builds a development environment where virtual network labs running on [containerlab](https://containerlab.dev) can be edited and driven from a web browser.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/kreonet/clabhost/main/install.sh | sudo bash -s -- install
```

Installs containerlab, clab-api-server, code-server and ufw-docker, then starts the web stack. Safe to re-run.

Then open `http://SERVER_IP/` and sign in with a server account. The first run takes a few minutes while the editor's extensions are downloaded.


## Requirements

* Ubuntu 24.04 or later
* [Docker CE from Docker's own repository](https://docs.docker.com/engine/install/ubuntu/)
* `/dev/kvm` if you use VM-based nodes (vrnetlab) — enable nested virtualisation on the hypervisor


## Paths

| URL | Contents |
|--|--|
| `/` | App list; switch from the left rail |
| `/?app=code` | Select an app in the same shell |
| `/clab/` | containerlab WebUI on its own |
| `/code/` | Editor on its own |
| `/grafana/` | Grafana on its own |

You sign in once. A server account unlocks all three apps, and Grafana signs you in under that same identity with no account of its own. Which URLs are gated is in [URL 과 프록시](docs/urls.ko.md).


## Adding accounts

Membership in `clab_api` plus a password is what makes sign-in work.

```sh
sudo useradd --create-home --shell /bin/bash alice
sudo passwd alice
sudo usermod -aG clab_api,docker,clab_admins alice
```

> [!WARNING]
> `docker` and `clab_admins` are **each equivalent to host root**. Running labs in practice needs them, and at that point user isolation is gone. Read the caveats below first.


## Day to day

```sh
cd /opt/clabhost
sudo ./install.sh check     # report on what is running
sudo ./install.sh update    # pull and restart the stack
docker compose down         # stop the web stack; labs and editor are left alone
sudo systemctl restart clabhost-code
docker compose logs -f caddy
journalctl -u clabhost-code -f
```

There is no uninstaller. Rebuilding the machine is faster and more certain than unwinding an install, and an uninstaller would give false comfort.


## Caveats

> [!WARNING]
> **clabhost is designed as a single-user development environment.** It does not support multi-user operation.

The reasons are structural:

* **Host port collisions.** Official containerlab examples such as the [Streaming Telemetry Lab](https://github.com/srl-labs/srl-telemetry-lab) map lab data straight onto specific host ports (3000, for instance) and claim them. Two labs like that cannot run on one host at the same time.
* **No isolation between users.** `netem`, which containerlab uses to [set link impairments](https://containerlab.dev/manual/impairments/) such as loss and delay, requires root on the host. Per-user privilege separation is therefore impossible, and any user can see and control another user's labs.

The editor runs on the host as `CLAB_USER`, and that account is in `docker` and `clab_admins` — so **the editor's terminal is effectively host root.** That is what lets it deploy labs and set `netem` impairments on a link.


## Documentation

The documents below are in Korean.

| Document | Contents |
|--|--|
| [구성요소](docs/components.ko.md) | What gets installed and what each piece is for |
| [설치 상세](docs/install.ko.md) | What install.sh does, the privilege model, pinning versions, extensions |
| [로그인](docs/login.ko.md) | One PAM sign-in across three apps; adding accounts; sessions |
| [URL 과 프록시](docs/urls.ko.md) | Which URL serves what, and how Caddy divides them up |
| [HTTPS 와 도메인](docs/tls.ko.md) | Moving from plain port 80 to TLS |
| [폐쇄망 설치](docs/airgap.ko.md) | Staging extensions and images for a host with no egress |
| [방화벽](docs/firewall.ko.md) | Why Docker bypasses ufw, and how to use `ufw route` |
| [IP 대역 관리](docs/addressing.ko.md) | Constraining Docker's address pool; running several labs at once |
| [실제 장비 config 로 테스트하기](docs/lab-isolation.ko.md) | Isolating public IPs, blocking internet access, emulating an IX |
| [토폴로지 작성](docs/topology.ko.md) | MAC addresses, physical uplinks, delay/loss/rate limits |
