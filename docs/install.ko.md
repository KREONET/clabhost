# 설치 상세

[README](../README.ko.md) 의 절차를 그대로 따르면 됩니다. 이 문서는 `install.sh` 가 실제로 무엇을 하는지, 그리고 알아두면 좋은 것들을 정리합니다.

## install.sh 가 하는 일

| 단계 | 내용 |
| --- | --- |
| preflight | root 여부, 배포판, Docker CE 와 compose 플러그인, `/dev/kvm` 확인 |
| containerlab | 없으면 [공식 설치기](https://containerlab.dev/install/)(`containerlab.dev/setup all`) 실행 |
| clab-api-server | 없으면 [공식 설치기](https://containerlab.dev/manual/api-server/#installation) 실행 |
| API 설정 | `TLS_ENABLE=false`, `API_SERVER_HOST=localhost`, 그룹 이름 확정 후 서비스 재시작 |
| 계정 | `docker`, `clab_api`, `clab_admins` 그룹 생성·가입, `~/.clab` 과 `~/clab` 링크 생성 |
| 소스 | 체크아웃에서 실행했으면 그대로, 아니면 `/opt/clabhost` 로 clone |
| .env | 비어 있는 항목만 탐지값으로 채움. 이미 채워진 값은 건드리지 않음 |
| 디렉터리 | `DATA_DIR` 트리와 `SOCKET_DIR` 을 서비스별 소유자로 생성. `SOCKET_DIR` 은 tmpfiles.d 에도 등록 |
| ufw | ufw 가 있으면 ufw-docker 설치 (`--no-ufw` 로 생략) |
| 웹 스택 | `docker compose up -d` |
| 편집기 | code-server 가 없으면 [공식 설치기](https://code-server.dev/install.sh) 실행, `clabhost-code.service` 렌더링·기동 |
| 확장 | `EXT_SET` 에 해당하는 확장을 계정 권한으로 설치 |

`install.sh update` 는 레포를 pull 하고, **호스트에 설치된 세 구성요소를 각각의 방식으로 업그레이드하고**, 다시 읽어야 하는 것만 재시작합니다.

| 구성요소 | 업그레이드 방법 |
| --- | --- |
| containerlab | `apt install --only-upgrade containerlab` (netdevops 레포) |
| clab-api-server | 공식 설치기의 `upgrade` 서브커맨드. **서비스를 재시작하므로 웹 UI 사용자가 로그아웃됩니다** |
| code-server | 공식 설치기 재실행. 멱등이고 제자리에서 올립니다 |

버전을 그대로 두고 레포만 갱신하려면 `--no-native` 를 주십시오.

재실행해도 안전합니다. 모든 단계가 먼저 확인하고, `.env` 는 덮어쓰지 않고 빠진 항목만 채웁니다.

## API 서버의 TLS 를 끄는 이유

공식 설치기는 `TLS_ENABLE=true`, `TLS_AUTO_CERT=true` 로 둡니다. 그러면 자체 서명 인증서가 생기고, 그 인증서를 신뢰시켜야 하는 클라이언트가 둘로 늘어납니다. 브라우저에서 예외를 수락해도 VS Code 확장의 Node 프로세스는 별개라서 `tls: unknown certificate` 로 실패합니다.

이 연결은 **호스트 밖으로 나가지 않습니다.** Caddy 와 containerlab-web 이 `127.0.0.1:8090` 으로 부르는 것이 전부이고, `API_SERVER_HOST=localhost` 라서 루프백에만 바인딩합니다. 그래서 `install.sh` 는 API 자체 TLS 를 끄고, 외부 노출은 Caddy 한 곳으로 모읍니다.

수동으로 다시 켜려면 `/etc/clab-api-server/clab-api-server.env` 를 고치고 `.env` 의 `CLAB_API_URL` 을 `https://` 로 바꾸십시오. 그 경우 위의 인증서 신뢰 문제를 직접 처리해야 합니다.

## 권한 모델

`docker` 와 `clab_admins` 는 **둘 다 호스트 root 와 동등합니다.**

`docker` 그룹은 Docker 소켓에 접근할 수 있다는 뜻이고, 그것으로 `docker run -v /:/host` 를 하면 호스트 파일시스템 전체를 읽고 쓸 수 있습니다.

`clab_admins` 는 SUID 로 설치된 containerlab 의 특권 명령을 sudo 없이 실행하게 해줍니다. containerlab 공식 문서도 같은 경고를 합니다.

> Much like the `docker` group, any users part of the `clab_admins` group are effectively given root-level privileges to the system running Containerlab.

이 서버 계정을 주는 것이 곧 root 를 주는 것이라고 생각하면 됩니다. 안전한 중간 등급은 없습니다. clabhost 가 1인용인 이유도 여기에 있습니다 — [로그인](login.ko.md) 을 보십시오.

## 편집기를 컨테이너에 두지 않는 이유

code-server 는 **호스트에** 설치되고 `clabhost-code.service` 로 동작합니다. compose 에는 없습니다.

랩 호스트에서 편집기의 존재 이유 절반은 터미널입니다. 터미널을 열어 `sudo -s` 를 하고, `containerlab` 을 직접 부르고, `tc`/`netem` 으로 링크에 지연을 걸고, 지난주에 설치해 둔 `tcpdump` 를 씁니다. **컨테이너 안 터미널은 그 중 어느 것도 호스트의 것이 아닙니다.**

| | 컨테이너 | 호스트 |
| --- | --- | --- |
| 파일시스템 | 이미지의 `/etc`, `/usr` | 호스트 그대로 |
| 설치한 도구 | 재생성하면 사라짐 | 남음 |
| `sudo` | 컨테이너의 sudo | 호스트 sudoers·PAM |
| `whoami` | `coder` | 실제 계정 |

특권 컨테이너(`privileged` + `pid: host` + `docker.sock`)로 우회하면 `containerlab deploy` 정도는 됩니다. 실제로 그렇게 만들어 검증도 했습니다. 그래도 위 표의 네 줄은 그대로 남습니다. `nsenter -t 1 -m` 으로 호스트 네임스페이스에 들어가는 방법도 있지만 편집기 파일 트리는 여전히 컨테이너라 절반만 해결됩니다.

**신뢰 모델은 나빠지지 않습니다.** `CLAB_USER` 는 어차피 `docker` 와 `clab_admins` 소속이라 호스트 root 와 동등합니다 — [권한 모델](#권한-모델) 을 보십시오. 같은 권한을 얻으면서 특권 컨테이너를 없앤 것이므로 compose 스택의 폭발 반경은 오히려 줄었습니다.

프록시 쪽에서는 차이가 없습니다. Caddy 는 어느 쪽이든 유닉스 소켓에 연결하고, `caddy/Caddyfile` 은 이 결정과 무관합니다.

```sh
systemctl status clabhost-code
journalctl -u clabhost-code -f
```

유닛은 `code-server/clabhost-code.service` 를 `install.sh` 가 렌더링한 것입니다. 한 번만 고칠 때는 `/etc/systemd/system/clabhost-code.service` 를, 계속 유지할 때는 레포의 템플릿을 고치고 `install.sh update` 를 실행하십시오.

## 데이터는 어디에 있나

네임드 볼륨을 쓰지 않습니다. 전부 `DATA_DIR` 아래 평범한 디렉터리입니다.

```
/opt/clabhost/data/
├── caddy/{data,config}/          ACME 계정키와 인증서 (0700)
├── grafana/                      직접 만든 대시보드, 사용자, 설정 (uid 472)
├── prometheus/                   메트릭 저장소
└── code-server/{extensions,user-data}/
```

`docker volume ls` 에 정체 모를 해시가 남지 않고, `tar czf backup.tgz -C /opt/clabhost data` 한 줄로 백업되고, 용량이 커지면 `.env` 의 `DATA_DIR` 하나만 다른 디스크로 돌리면 됩니다. `PROM_MAX_SIZE` 와 `full` 확장 세트가 용량의 대부분입니다.

대가가 두 개 있습니다.

* **소유권을 직접 맞춰야 합니다.** 새 네임드 볼륨은 이미지의 해당 경로 소유권을 물려받지만 바인드 마운트는 그냥 root 소유 빈 디렉터리입니다. Grafana 는 uid 472 로 도므로 그대로 두면 쓰지 못합니다. `install.sh` 의 `make_dirs` 가 서비스별로 chown 합니다.
* **`docker compose down -v` 가 데이터를 지우지 않습니다.** 초기화는 `rm -rf data/` 입니다. `git clean -xfd` 도 지우므로 주의하십시오 — **인증서와 ACME 계정키가 거기 있습니다.**

## 확장은 언제 설치되나

**에디터는 목록만 보고 확장을 설치하지 않습니다.** `.vscode/extensions.json` 의 `recommendations` 는 "설치할까요?" 알림을 띄울 뿐이고 사용자가 눌러야 합니다. devcontainer 가 자동 설치처럼 보이는 것은 devcontainer CLI 가 대신 `--install-extension` 을 실행하는 것이지 에디터 기능이 아닙니다. 즉 누군가는 반드시 그 명령을 돌려야 합니다.

`install.sh` 가 그 일을 합니다. 웹 스택을 시작한 다음 `code-server/seed-extensions.sh` 를 계정 권한으로 실행합니다. `full` 세트는 1GB 가까이 되고 몇 분 걸리는데, 그동안 포털·`/clab/`·`/grafana/` 는 이미 동작합니다. `/code` 만 준비 중 화면을 보여주고 자동으로 새로고침합니다.

**두 번 실행해도 아무것도 하지 않습니다.** 확장 디렉터리에 이미 있는 것은 건너뛰므로 open-vsx 에 다시 묻지 않습니다. 외부 통신이 없는 호스트에서 그 확인 왕복은 전부 느린 실패가 되므로 이게 중요합니다.

```
extension set 'full' is already installed; nothing to do
```

직접 실행할 때는 이렇게 합니다. 스크립트만 있으면 되고 `install.sh` 를 다시 돌릴 필요는 없습니다.

```sh
. /opt/clabhost/.env
sudo -u "$CLAB_USER" \
  EXT_DIR="$DATA_DIR/code-server/extensions" EXT_SET=network \
  sh /opt/clabhost/code-server/seed-extensions.sh
sudo systemctl restart clabhost-code
```

`EXT_SET` 을 바꾸면 **모자란 것만** 받습니다. 이미 있는 것과 의존성으로 딸려온 것은 그대로 둡니다. `code-server/extensions.txt` 를 고쳤을 때도 같습니다.

버전을 올리려면 강제 재설치가 필요합니다. `EXT_UPDATE=1` 을 붙이거나 `install.sh update` 를 쓰십시오.

Open VSX 에 닿지 못해 실패한 확장이 있으면 `DATA_DIR/code-server/extensions/.install-failures` 에 남고 `install.sh check` 가 보고합니다. 실패해도 편집기 기동은 막지 않습니다 — 확장 없는 편집기도 편집기입니다.

애초에 외부로 나갈 수 없는 호스트라면 확장을 미리 받아 반입합니다. [폐쇄망 설치](airgap.ko.md) 를 보십시오.

그 경우를 위해 워크스페이스에 `.vscode/extensions.json` 을 하나 만들어 둡니다. 설치가 잘 됐으면 없어도 그만이지만, 실패했을 때는 편집기 안에서 클릭 한 번으로 다시 받을 수 있는 유일한 경로입니다. 이 파일은 **처음 한 번만** 만들어지므로 `EXT_SET` 을 바꿔도 갱신되지 않습니다. 지우면 다음 `install.sh` 실행 때 다시 만들어집니다.

## 버전 고정

netdevops 레포에는 containerlab 의 과거 버전이 모두 남아 있어 특정 버전 고정과 다운그레이드가 됩니다.

```sh
apt-cache madison containerlab        # 설치 가능한 버전 전부
sudo apt install containerlab=0.79.0  # 특정 버전
```

설치 스크립트에 환경변수로 넘길 수도 있습니다.

```sh
curl -sL https://containerlab.dev/setup | sudo -E CLAB_VERSION=0.79.0 bash -s "all"
```

업그레이드는 apt 로 합니다. `containerlab version upgrade` 명령도 있지만 GitHub 에서 설치 스크립트를 받아오는 방식이라 rate limit 에 걸릴 수 있고, apt 가 무엇이 설치되었는지 모르게 됩니다. `install.sh update` 도 apt 를 씁니다.

컨테이너 이미지는 `.env` 의 `IMG_*` 로 고정합니다. **운영에서는 반드시 고정하십시오.** containerlab-web 은 세션을 메모리에 두므로 이미지가 바뀌어 컨테이너가 재생성되면 전원이 로그아웃됩니다.

## 알아둘 것

**netdevops 레포는 서명 검증 없이 등록됩니다.** 공식 설치기가 넣는 줄은 `deb [trusted=yes] https://netdevops.fury.site/apt/ /` 이고, `trusted=yes` 는 GPG 서명 검증을 끈다는 뜻입니다. 사내 정책에 걸리면 GitHub releases 의 `.deb` 를 직접 받아 `dpkg -i` 하십시오. 다만 그 경우 SUID 는 수동으로 설정해야 합니다.

```sh
sudo chmod u+s $(which containerlab)
```

**그룹은 새 로그인부터 적용됩니다.** 설치 직후 같은 셸에서는 `id` 에 `docker` 가 보이지 않습니다. 다시 로그인하거나 `newgrp docker` 를 하십시오. 컨테이너는 `.env` 의 숫자 GID 를 쓰므로 이 문제와 무관하게 바로 동작합니다.

**설치 스크립트를 두 번 실행하면 apt 소스가 중복될 수 있습니다.** `tee -a` 로 덧붙이기 때문입니다. `apt update` 가 중복 경고를 내면 `/etc/apt/sources.list.d/netdevops.list` 를 한 줄만 남기고 정리하십시오.

## 상태 점검

```sh
sudo ./install.sh check
```

네이티브 구성요소, 컨테이너 7종, 편집기(유닛·소켓·확장 개수), Grafana 소켓, prometheus 시계열, HTTP 응답을 확인합니다.

TLS 를 켠 호스트에서는 `.env` 의 `SITE_URL` 을 채우십시오. 평문 80 은 308 로 답하므로, 기본값인 `http://127.0.0.1:80` 을 찔러 보면 정상 동작을 실패로 보고합니다.

`count(container_last_seen)` 이 0 이면 cAdvisor 가 컨테이너를 하나도 등록하지 못한 것입니다. 대시보드의 랩 관련 패널이 통째로 빕니다. Docker 가 containerd 이미지 저장소를 쓰는 호스트에서 오래된 cAdvisor 가 겪는 문제([google/cadvisor#3643](https://github.com/google/cadvisor/issues/3643))이므로 `.env` 의 `IMG_CADVISOR` 를 최신으로 올리십시오.
