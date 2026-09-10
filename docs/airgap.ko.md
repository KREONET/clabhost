# 폐쇄망에 설치하기

외부 통신이 없는 호스트에서 걸리는 것은 세 가지입니다.

| 무엇 | 어디서 받나 | 없으면 |
| --- | --- | --- |
| 편집기 확장 | open-vsx.org | 편집기는 뜨지만 vscode-containerlab 이 없습니다 |
| 스택 컨테이너 이미지 | Docker Hub, ghcr.io, quay.io | `docker compose up` 이 실패합니다 |
| 랩 노드 이미지 | ghcr.io, 벤더 레지스트리 | 랩 배포가 실패합니다 |

셋 다 연결된 호스트에서 미리 받아 옮깁니다. 아래는 **연결된 호스트**와 **대상 호스트**를 오가는 절차입니다.

## 확장: 디렉터리를 통째로 옮깁니다

권장하는 방법입니다. `.vsix` 를 하나씩 받는 것보다 확실한 이유는 아래 [함정](#vsix-를-하나씩-받는-경우) 에 있습니다.

### 연결된 호스트에서

`clabhost` 를 설치할 필요 없이 code-server 이미지 하나면 됩니다. 만들 때 쓴 경로와 풀 때 쓸 경로가 달라도 됩니다 — `extensions.json` 에 절대경로(`location.path`)가 들어가긴 하지만 code-server 는 같이 적힌 `relativeLocation` 을 읽습니다. `/ext` 로 만든 디렉터리를 호스트의 `data/code-server/extensions` 에 풀어 16개가 그대로 인식되는 것을 확인했습니다.

```sh
mkdir -p /tmp/ext-seed
docker run --rm --user 0:0 -v /tmp/ext-seed:/ext codercom/code-server:latest \
  --extensions-dir /ext \
  --install-extension srl-labs.vscode-containerlab \
  --install-extension redhat.vscode-yaml \
  --install-extension y-ysss.cisco-config-highlight \
  --install-extension aswertus.cisco-ios-lsp \
  --install-extension hediet.vscode-drawio \
  --install-extension electropol-fr.drawio-diagrams-editor \
  --install-extension ms-python.python \
  --install-extension detachhead.basedpyright \
  --install-extension charliermarsh.ruff \
  --install-extension docker.docker \
  --install-extension eamodio.gitlens

tar -C /tmp/ext-seed -czf ext-seed.tgz .
```

목록은 [`code-server/extensions.txt`](../code-server/extensions.txt) 와 같아야 합니다. 위는 `network` 세트이고, `full` 은 LLM 어시스턴트 세 개가 더 붙습니다. 레포가 있다면 목록을 직접 뽑아 쓰십시오.

```sh
awk '/^# --- SET / {c=$4; next} /^#/||/^$/ {next} {print}' code-server/extensions.txt
```

### 대상 호스트에서

`.env` 의 `DATA_DIR` 아래에 풀고 소유자를 `CLAB_UID:CLAB_GID` 로 맞춥니다. 편집기는 그 계정으로 도므로 소유권이 맞지 않으면 확장을 읽지 못합니다.

```sh
. /opt/clabhost/.env
sudo install -d -m 0755 "$DATA_DIR/code-server/extensions"
sudo tar -C "$DATA_DIR/code-server/extensions" -xzf ext-seed.tgz
sudo chown -R "$CLAB_UID:$CLAB_GID" "$DATA_DIR/code-server"
```

그 다음 `install.sh install` 을 실행하면 확장 단계가 **이미 다 있는 것을 보고 그냥 지나갑니다.** 마켓플레이스에 한 번도 붙지 않습니다.

```
extension set 'network' is already installed; nothing to do
```

이 한 줄이 나오지 않고 무언가를 설치하려 든다면, 옮긴 목록과 `.env` 의 `EXT_SET` 이 어긋난 것입니다. 세트를 낮추거나 빠진 것을 마저 옮기십시오. 받지 못한 확장은 `DATA_DIR/code-server/extensions/.install-failures` 에 남고 편집기 기동을 막지는 않습니다.

## 확장: `.vsix` 를 폴더에 넣습니다

브라우저밖에 없는 반입 환경에서는 이 방법을 쓰게 됩니다. `code-server/vsix/` 에 `.vsix` 를 넣어 두면 확장 단계가 **마켓플레이스에 붙기 전에** 전부 설치합니다. 폴더는 `/opt/clabhost` 안에 있으니 통째로 들고 가면 됩니다.

```
/opt/clabhost/code-server/vsix/
  srl-labs.vscode-containerlab-0.26.3.vsix
  redhat.vscode-yaml-1.25.2026090408.vsix
  hediet.vscode-drawio-1.6.6.vsix
```

```sh
docker compose up -d
sudo ./install.sh install   # 확장 단계의 출력을 그대로 보여줍니다
```

```
  ok      hediet.vscode-drawio  (vsix)
  ok      redhat.vscode-yaml  (vsix)
  ok      srl-labs.vscode-containerlab  (vsix)
extension set 'minimal' is already installed; nothing to do
```

마지막 줄이 핵심입니다. vsix 로 들어온 것을 이미 있다고 보고 넘어가므로 **네트워크를 한 번도 건드리지 않습니다.** `--network none` 으로 확인한 동작입니다.

두 번째 기동부터는 `have` 로 바뀌고 아무것도 하지 않습니다.

```
  have    hediet.vscode-drawio
  have    redhat.vscode-yaml
  have    srl-labs.vscode-containerlab
```

`.vsix` 는 `.gitignore` 에 들어 있어서 `git pull` 이 건드리지 않고, 커밋에도 올라가지 않습니다.

`EXT_SET` 이 요구하는 것 중 vsix 가 없는 것은 마켓플레이스를 시도하고 실패합니다. 폐쇄망에서는 그 목록이 **무엇을 빠뜨렸는지** 알려주는 답입니다.

```
extension set 'network': installing 8
  FAILED  y-ysss.cisco-config-highlight
  ...
```
```sh
cat "$DATA_DIR/code-server/extensions/.install-failures"
```

빠진 것을 채우거나 `EXT_SET` 을 낮추십시오. 어느 쪽이든 편집기는 동작합니다.

### 의존성은 직접 챙겨야 합니다

**오프라인 설치는 의존성을 조용히 빠뜨립니다.**

`srl-labs.vscode-containerlab` 하나를 진짜 오프라인(`--network none`)에서 vsix 로 설치하면 이렇게 됩니다.

```
Extension 'srl-labs.vscode-containerlab-0.26.3.vsix' was successfully installed.

$ ls /ext
extensions.json
srl-labs.vscode-containerlab-0.26.3
```

같은 명령이 **온라인에서는** `redhat.vscode-yaml` 과 `hediet.vscode-drawio` 를 함께 설치합니다. 이 확장이 그 둘을 의존성으로 선언하기 때문이고, 오프라인에서는 그것을 받아올 수 없으니 **경고 한 줄 없이 건너뜁니다.** 결과는 "확장은 설치됐는데 YAML 스키마 검증이 안 되는" 상태이고, 원인을 찾기 어렵습니다.

이 방법을 쓴다면 의존성까지 직접 챙겨야 합니다. open-vsx API 의 `dependencies` 필드는 비어 있는 경우가 있어 믿을 수 없습니다. 연결된 호스트에서 한 번 설치해 보고 `ls` 로 실제로 딸려온 것을 확인하는 편이 빠릅니다.

받는 주소는 이렇습니다.

```sh
curl -s https://open-vsx.org/api/srl-labs/vscode-containerlab/latest \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["files"]["download"])'
```

**플랫폼별 빌드가 있는 확장은 `/latest` 를 그냥 쓰면 안 됩니다.** 어느 플랫폼 것이 나올지 정해져 있지 않습니다. 실제로 `charliermarsh/ruff/latest` 는 `alpine-arm64` 를 돌려줍니다. 대상 플랫폼을 경로에 넣으십시오.

```sh
curl -s https://open-vsx.org/api/charliermarsh/ruff/linux-x64/latest \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["files"]["download"])'
# -> .../charliermarsh.ruff-2026.78.0@linux-x64.vsix
```

받은 파일은 `code-server/vsix/` 에 그대로 두면 됩니다. 파일명은 건드리지 마십시오 — `publisher.name-<버전>[@플랫폼].vsix` 에서 확장 id 를 뽑아 이미 설치됐는지 판단합니다.

사내에 Open VSX 미러를 운영한다면 code-server 의 `EXTENSIONS_GALLERY` 환경변수로 갤러리를 바꿀 수 있습니다. 이 레포에서 검증하지는 않았습니다.

## 스택 이미지

받아야 할 목록은 `.env` 의 `IMG_*` 가 전부입니다. **폐쇄망에서는 태그를 반드시 고정하십시오** — `latest` 는 대상 호스트에서 확인할 방법이 없습니다.

```sh
# 연결된 호스트
grep '^IMG_' .env.example | cut -d= -f2 | xargs -n1 docker pull
grep '^IMG_' .env.example | cut -d= -f2 | xargs docker save -o clabhost-images.tar

# 대상 호스트
docker load -i clabhost-images.tar
```

편집기는 이미지가 아니라 호스트에 설치되므로 여기 목록에 없습니다. 폐쇄망에서는 code-server 의 `.deb`(또는 standalone tarball)를 [릴리스](https://github.com/coder/code-server/releases) 에서 미리 받아 반입하고, `install.sh` 를 실행하기 전에 설치해 두십시오 — 이미 있으면 설치기를 부르지 않습니다.

## 랩 노드 이미지

랩에서 쓸 NOS 이미지도 같은 방식으로 옮깁니다.

```sh
docker save ghcr.io/nokia/srlinux:25.10 ghcr.io/srl-labs/network-multitool \
  -o lab-images.tar
```

토폴로지의 `image:` 태그가 옮긴 것과 정확히 같아야 합니다. containerlab 은 로컬에 없으면 받으러 나가고, 폐쇄망에서는 그대로 실패합니다.

공개 예제 상당수는 배포 후 `apk add` 나 `pip install` 을 하는 `exec` 를 포함합니다. 그 부분은 이미지를 옮겨도 동작하지 않으므로 토폴로지에서 걷어내야 합니다.

## 확인

```sh
sudo ./install.sh check
```

`editor` 항목의 확장 개수가 옮긴 수와 맞는지 보십시오. 컨테이너 안에서 직접 확인할 수도 있습니다.

```sh
. /opt/clabhost/.env
sudo -u "$CLAB_USER" code-server --extensions-dir "$DATA_DIR/code-server/extensions" \
     --list-extensions --show-versions
```

## 인터넷이 필요한 나머지

옮겨도 동작하지 않는 것들입니다. 폐쇄망에서는 포기하거나 사내 대체재를 쓰십시오.

* **YAML 스키마 검증** — `code-server/settings.json` 의 `yaml.schemas` 가 GitHub raw URL 을 가리킵니다. 스키마 파일을 호스트에 두고 그 경로로 바꾸십시오.
* **LLM 어시스턴트** — `full` 세트의 세 확장은 각자의 API 에 붙습니다. 폐쇄망에서는 `EXT_SET=network` 가 맞습니다.
* **Grafana 플러그인 설치, 뉴스 피드, 업데이트 확인** — 뉴스와 업데이트 확인은 compose 에서 이미 꺼 두었습니다.
