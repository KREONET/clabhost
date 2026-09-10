# URL 과 프록시

브라우저가 어느 주소로 무엇을 받는지, 그리고 Caddy 가 그것을 어떻게 나누는지에 관한 문서입니다. 랩 안의 경로·라우팅과는 무관합니다 — 그쪽은 [토폴로지 작성](topology.ko.md) 과 [실제 장비 config 로 테스트하기](lab-isolation.ko.md) 를 보십시오.

로그인 자체는 [로그인](login.ko.md) 에 있습니다.

## URL 경로

| URL | 대상 | 인증 |
| --- | --- | --- |
| `/` | 포털 셸 (왼쪽 앱 목록) | 필요 |
| `/?app=code` | 같은 셸에서 편집기 선택 | 필요 |
| `/clab/` | containerlab WebUI 단독 | 필요 |
| `/code/` | 편집기 단독 | 필요 |
| `/grafana/` | Grafana 단독 | 필요 |
| `/login` | 로그인 폼 | 열림 |
| 그 외 전부 | containerlab-web (SPA 번들, `/api/*`, `/auth/*`, `/events`, `/files`) | 열림 |

마지막 줄이 열려 있는 것은 의도입니다. `/auth/login` 이 세션을 만드는 통로이고, 나머지는 containerlab-web 이 자기 세션으로 이미 막고 있습니다. 여기에 forward_auth 를 걸면 SPA 가 파싱하지 못하는 302 로 401 이 바뀝니다.

## `/clab/` 이 성립하는 이유

containerlab-web 은 Vite SPA 이고 내부 경로가 전부 **루트 절대경로**입니다.

```
/assets/main-C4G87tal.js   /api/*   /events   /auth/*   /files
```

이 앱에는 base path 개념이 없어서 서브패스로 옮길 수 없습니다.

그래서 Caddyfile 은 반대로 합니다. **포털이 차지하는 경로는 `/` 하나뿐이고, 아무도 가져가지 않은 나머지는 전부 containerlab-web 으로 떨어집니다.** `/clab/` 은 문서 요청에서만 접두어를 떼고, 그 문서가 이어서 부르는 루트 절대경로는 맨 아래 fallback 이 받습니다.

`/assets/*`, `/api/*` 를 매처로 하나씩 나열해도 되지만, 앱이 경로를 추가할 때마다 따라가야 합니다. fallback 쪽이 손이 덜 갑니다.

전제는 이 앱이 **URL 경로를 보고 화면을 바꾸지 않는다**는 것입니다 — 그래야 문서가 `/clab/` 에서 로드된 것을 신경 쓰지 않습니다. 번들에서 확인한 사실이며(경로를 읽는 코드도, `history`·`pathname` 처리도 없습니다), 앱이 그런 처리를 도입하면 `/clab/` 은 깨집니다. 그때는 포털을 `/portal` 로 옮기고 `/` 를 containerlab-web 에 돌려주는 것이 가장 단순한 수습입니다.

code-server 는 사정이 다릅니다. HTML 안의 경로가 상대 경로라서 `handle_path` 로 접두어만 떼면 그대로 동작합니다.

Grafana 는 `GF_SERVER_SERVE_FROM_SUB_PATH=true` 로 서브패스를 정식 지원합니다. 이쪽은 접두어를 **떼면 안 됩니다** — Grafana 가 `/grafana` 를 포함한 경로를 받아 자기 URL 을 만들기 때문에, 떼면 같은 경로로 무한히 301 합니다.
