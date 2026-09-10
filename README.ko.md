# clabhost - containerlab 웹 기반 개발호스트 구축

[🇺🇸 English](README.md) · [🇰🇷 한국어](README.ko.md)

[clabhost](https://github.com/kreonet/clabhost)는 [containerlab(컨테이너랩)](https://containerlab.dev) 기반의 가상 네트워크 랩을 웹 브라우저에서 직접 편집하고 제어할 수 있는 개발 환경을 구축합니다.

## 설치

```sh
curl -fsSL https://raw.githubusercontent.com/kreonet/clabhost/main/install.sh | sudo bash -s -- install
```

containerlab, clab-api-server, code-server, ufw-docker 를 설치하고 웹 스택까지 시작합니다. 재실행해도 안전합니다. 자세한 내용은 [설치 상세](docs/install.ko.md)를 보십시오.

스크립트를 먼저 읽고 실행하는 쪽을 권합니다. 하는 일이 같습니다.

```sh
git clone https://github.com/kreonet/clabhost /opt/clabhost
cd /opt/clabhost
less install.sh
sudo ./install.sh install
```

`docker compose up -d` 만으로도 포털, `/clab/`, `/grafana/` 는 동작합니다. 다만 **편집기는 `install.sh` 가 설치합니다** — 호스트에 설치되는 systemd 서비스이고 compose 에 없습니다. 이유는 [편집기를 컨테이너에 두지 않는 이유](docs/install.ko.md#편집기를-컨테이너에-두지-않는-이유)를 보십시오. 그때까지 `/code` 는 준비 중 화면입니다.

설치가 끝나면 `http://SERVER_IP/` 로 접속해 서버 계정으로 로그인합니다. 처음 실행은 편집기 확장을 내려받느라 몇 분 걸립니다.


## 요구사항

* 우분투 24.04 이상
* [공식 Docker CE](https://docs.docker.com/engine/install/ubuntu/)
* VM 기반 노드(vrnetlab)를 쓴다면 `/dev/kvm` — 하이퍼바이저에서 중첩 가상화를 켜야 합니다


## 경로

| URL | 내용 |
|--|--|
| `/` | 앱 목록. 왼쪽 메뉴에서 전환합니다 |
| `/?app=code` | 같은 화면에서 특정 앱을 선택 |
| `/clab/` | containerlab WebUI 단독 |
| `/code/` | 편집기 단독 |
| `/grafana/` | Grafana 단독 |

로그인은 한 번입니다. 서버 계정으로 로그인하면 세 앱이 모두 열리고, Grafana 는 별도 계정 없이 그 신원으로 자동 로그인됩니다. 동작 방식은 [로그인](docs/login.ko.md), 어느 URL 에 인증이 걸리는지는 [URL 과 프록시](docs/urls.ko.md)에 있습니다.


## 사용자 추가

`clab_api` 그룹에 넣고 비밀번호를 설정하면 로그인할 수 있습니다.

```sh
sudo useradd --create-home --shell /bin/bash alice
sudo passwd alice
sudo usermod -aG clab_api,docker,clab_admins alice
```

> [!WARNING]
> `docker` 와 `clab_admins` 는 **호스트 root 와 동등합니다.** 랩을 실제로 운용하려면 필요하지만, 그 시점에서 사용자 격리는 사라집니다. 아래 유의사항과 [권한 모델](docs/install.ko.md#권한-모델)을 먼저 읽으십시오.


## 유지관리

```sh
cd /opt/clabhost
sudo ./install.sh check     # 무엇이 살아 있는지 점검
sudo ./install.sh update    # git pull 후 스택 재기동
docker compose down         # 웹 스택 중지. 랩과 편집기는 그대로 남습니다
sudo systemctl restart clabhost-code
docker compose logs -f caddy
journalctl -u clabhost-code -f
```

데이터는 네임드 볼륨이 아니라 `data/` 아래 평범한 디렉터리입니다. 백업은 `tar czf backup.tgz -C /opt/clabhost data`, 초기화는 `rm -rf data/` 입니다. **`docker compose down -v` 로는 지워지지 않고, `git clean -xfd` 로는 지워집니다** — 인증서가 거기 있습니다. [데이터는 어디에 있나](docs/install.ko.md#데이터는-어디에-있나)

언인스톨러는 없습니다. 랩 호스트를 없애는 건 설치를 되짚는 것보다 VM 을 다시 만드는 편이 빠르고 확실하며, 언인스톨러는 잘못된 안심을 줍니다 — 랩 이미지, 하이퍼바이저 방화벽 규칙, DNS 레코드는 모두 이 호스트 밖에 있습니다.


## 유의사항

> [!WARNING]
> **clabhost는 1인용 개발 환경으로 설계되었습니다.** 다중 사용자 환경을 지원하지 않습니다.

이유는 다음과 같은 구조적 제약 때문입니다.

* **호스트 포트 충돌:** [Streaming Telemetry Lab](https://github.com/srl-labs/srl-telemetry-lab)과 같은 containerlab 공식 예제들은 가상 랩의 정보를 호스트의 특정 포트(예: 3000번)에 직접 매핑하여 선점합니다. 이로 인해 동일한 호스트에서 여러 랩을 동시에 실행할 수 없습니다.
* **사용자 격리(Isolation) 불가:** containerlab에서 [링크 속성(loss, delay 등)을 설정](https://containerlab.dev/manual/impairments/)하기 위해 사용하는 `netem`은 리눅스 시스템의 root 권한을 필요로 합니다. 이로 인해 사용자별 권한 격리가 불가능하며, 다른 사용자의 랩 환경을 보거나 제어할 수 있게 됩니다.

계정을 여러 개 만들 수는 있습니다. 다만 편집기는 하나이고 작업 공간도 하나이므로, **서로 신뢰하는 사람들이 함께 쓰는 실습 서버**로 취급하십시오.

편집기는 `CLAB_USER` 계정으로 호스트에서 동작합니다. 그 계정은 `docker`·`clab_admins` 소속이므로 **편집기 터미널은 실질적으로 호스트 root 입니다.** 그래야 랩을 배포하고 `netem` 으로 링크에 지연을 걸 수 있습니다.


## 문서

| 문서 | 내용 |
|--|--|
| [구성요소](docs/components.ko.md) | 무엇이 설치되고 각각 무슨 역할인지 |
| [설치 상세](docs/install.ko.md) | install.sh 가 하는 일, 권한 모델, 버전 고정, 확장 |
| [로그인](docs/login.ko.md) | PAM 로그인 한 번으로 세 앱을 여는 방법, 계정 추가, 세션 |
| [URL 과 프록시](docs/urls.ko.md) | 어느 주소로 무엇이 열리나, Caddy 가 그것을 나누는 방식 |
| [HTTPS 와 도메인](docs/tls.ko.md) | 평문 80 을 TLS 로 바꾸기 |
| [폐쇄망 설치](docs/airgap.ko.md) | 확장·이미지를 미리 받아 반입하기 |
| [방화벽](docs/firewall.ko.md) | Docker 가 ufw 를 우회하는 이유, `ufw route` 사용법 |
| [IP 대역 관리](docs/addressing.ko.md) | Docker 주소 풀 제한, 랩 여러 개 동시 실행 |
| [실제 장비 config 로 테스트하기](docs/lab-isolation.ko.md) | 공인 IP 격리, 인터넷 차단, IX 모사 |
| [토폴로지 작성](docs/topology.ko.md) | MAC, 물리망 연결, 지연·손실·대역 제한 |
