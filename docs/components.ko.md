# 구성요소

두 부류입니다. **호스트에 직접 설치되는 것**과 **컨테이너로 동작하는 것**입니다. 나누는 기준은 호스트 자체를 다뤄야 하는지입니다 — 네트워크 네임스페이스를 만들거나, 호스트의 터미널이어야 하거나, 랩 파일의 소유자여야 하는 것은 호스트에 둡니다.

`install.sh install` 이 양쪽을 모두 처리합니다.

| 요소 | 설명 | 설치방식 |
|--|--|--|
| [containerlab](https://containerlab.dev/install/) | 랩을 만들고 없애는 CLI. 이 레포가 존재하는 이유 | os native |
| [clab-api-server](https://containerlab.dev/manual/api-server/#installation) | containerlab 을 REST 로 감싼 것. 리눅스 PAM 으로 인증하므로 별도 계정 체계가 없습니다 | os native |
| [code-server](https://coder.com/docs/code-server) | 브라우저 편집기. containerlab 확장과 YAML 스키마가 미리 설치됩니다. [터미널이 호스트 셸이어야 해서](install.ko.md#편집기를-컨테이너에-두지-않는-이유) 컨테이너가 아닙니다 | os native |
| [containerlab-web](https://containerlab.dev/manual/gui/web/#installation) | 토폴로지 편집기와 TopoViewer. API 서버에 붙습니다 | docker |
| [Caddy](https://caddyserver.com/docs/) | 리버스 프록시. **외부로 열리는 유일한 포트**입니다. 기본은 평문 80 — [HTTPS 로 바꾸기](tls.ko.md) | docker |
| auth shim | 웹 UI 의 로그인 세션을 다른 앱이 쓸 수 있는 신원으로 번역합니다. 비밀번호를 다루지 않으므로 특권이 없습니다 — [로그인](login.ko.md) | docker |
| [Grafana](https://grafana.com/docs/grafana/latest/) | 대시보드. 로그인한 신원으로 자동 로그인되고 `clabhost overview` 가 기본 제공됩니다 | docker |
| [Prometheus](https://prometheus.io/docs/) | 메트릭 저장소. 외부로 노출되지 않고 Grafana 를 통해서만 봅니다 | docker |
| [node-exporter](https://github.com/prometheus/node_exporter) | 호스트의 CPU·메모리·디스크 | docker |
| [cAdvisor](https://github.com/google/cadvisor) | 컨테이너별 자원 사용량. 랩 노드가 여기 잡힙니다 | docker |

`ufw-docker` 도 설치합니다. 구성요소는 아니고, [Docker 가 ufw 를 우회하는 문제](firewall.ko.md)를 막는 스크립트입니다. `install.sh install --no-ufw` 로 건너뜁니다.

## 왜 이 조합인가

`containerlab`, `clab-api-server`, `containerlab-web` 은 srl-labs 의 공식 구성요소이고 그대로 씁니다. 이 레포가 더하는 것은 그 앞단입니다.

* **로그인 한 번.** 웹 UI 에 리눅스 계정으로 로그인하면 편집기와 Grafana 까지 통과합니다. auth shim 이 그 일을 하고, 외부 인증 서버가 필요 없습니다.
* **포트 하나.** 랩이 호스트 포트를 직접 점유하기 때문에(공식 예제가 3000, 9090 을 씁니다) 나머지는 유닉스 소켓이나 내부 브릿지로만 통신합니다.
* **편집기에 확장이 미리 설치됨.** containerlab 확장은 CLI 를 직접 호출하므로, 편집기가 호스트에 있어야 배포·삭제·노드 접속이 동작합니다.
* **모니터링 기본 제공.** 랩 노드는 컨테이너이므로 cAdvisor 가 그대로 잡습니다. 랩별 CPU·메모리를 보는 대시보드가 들어 있습니다.

각각의 이유는 [설치 상세](install.ko.md)에 있습니다.
