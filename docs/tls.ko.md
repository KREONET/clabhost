# HTTPS 와 도메인

clabhost 는 **평문 HTTP 80 포트 하나만** 엽니다. 신뢰하는 연구망·관리망 안에서 쓰는 것을 전제로 하고, 접속 대역은 ufw 로 좁힙니다([방화벽](firewall.ko.md)).

```sh
sudo ufw route allow proto tcp from YOUR_CIDR to any port 80
```

평문이라는 것은 **로그인 비밀번호가 그대로 흐른다**는 뜻입니다. 그 망을 신뢰할 수 없으면 아래대로 TLS 를 켜십시오.

## 도메인이 있고 인증서를 받을 수 있는 경우

`caddy/Caddyfile` 은 두 곳만 고치면 됩니다.

```diff
 {
-	auto_https off
 	admin off
 }

-:{$HTTP_PORT:80} {
+clab1.example.net {
 	encode zstd gzip
```

`auto_https off` 를 지우고 사이트 주소를 호스트 이름으로 바꾸면 Caddy 가 Let's Encrypt 에서 인증서를 받아 갱신까지 합니다. 그 다음 compose 에서 443 을 열어야 합니다. `caddy` 는 `network_mode: host` 라 `ports` 설정이 없으므로, 호스트 방화벽만 열면 됩니다.

```sh
sudo ufw route allow proto tcp from YOUR_CIDR to any port 443
sudo ufw route allow proto tcp from any to any port 80   # HTTP-01 challenge 용
docker compose restart caddy
```

Grafana 의 `GF_SERVER_ROOT_URL` 은 요청의 프로토콜과 호스트에서 만들어지므로 그대로 두면 됩니다.

`.env` 의 `SITE_URL` 도 채우십시오. TLS 를 켜면 평문 80 은 308 로 답하는데, `install.sh check` 는 기본적으로 `http://127.0.0.1:80` 을 찔러 보므로 정상 동작을 실패로 보고합니다.

```sh
SITE_URL=https://clab1.example.net
```

## 포트를 열 수 없는 경우 (DNS-01)

방화벽이 80 을 밖으로 열어주지 않으면 HTTP-01 challenge 가 안 됩니다. DNS 서버를 직접 운영한다면 RFC2136(TSIG) 로 DNS-01 을 씁니다.

이 플러그인은 기본 Caddy 이미지에 없어서 이미지를 따로 빌드해야 합니다.

```dockerfile
# caddy/Dockerfile
FROM caddy:2-builder AS builder
RUN xcaddy build --with github.com/caddy-dns/rfc2136

FROM caddy:2-alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
```

```yaml
# docker-compose.yml 의 caddy 서비스
  caddy:
    build: ./caddy          # image: 를 대체합니다
```

```caddyfile
{
	email hostmaster@example.net
	acme_dns rfc2136 {
		key_name   clab
		key_alg    hmac-sha256
		key        {env.CLAB_TSIG_KEY}
		server     ns.example.net:53
	}
}

clab1.example.net {
	...
}
```

`CLAB_TSIG_KEY` 는 `.env` 에 넣고 compose 의 `caddy` 서비스에 `environment` 로 넘기십시오. **키를 Caddyfile 에 직접 쓰지 마십시오** — 이 파일은 레포에 커밋됩니다.

## 사내 CA 나 자체 서명

Caddy 내부 CA 로 발급받을 수 있습니다. 사이트 블록에 한 줄이면 됩니다.

```caddyfile
clab1.example.net {
	tls internal
	...
}
```

루트 인증서를 클라이언트에 배포하면 브라우저 경고가 사라집니다. 호스트에서 바로 꺼낼 수 있습니다 — Caddy 의 `/data` 는 네임드 볼륨이 아니라 바인드 마운트입니다.

```sh
. /opt/clabhost/.env
sudo cp "$DATA_DIR/caddy/data/caddy/pki/authorities/local/root.crt" .
```

같은 이유로 **`$DATA_DIR/caddy/data` 를 지우면 인증서와 ACME 계정키가 사라집니다.** 다시 발급받게 되므로 Let's Encrypt 사용 시 rate limit 을 염두에 두십시오. 모드가 `0700` 인 것도 그래서입니다.

## 앞단에 별도 프록시가 있는 경우

이미 nginx 나 로드밸런서가 TLS 를 종료하고 있다면 `caddy/Caddyfile` 은 손댈 필요가 없습니다. 그 프록시가 `X-Forwarded-Proto: https` 를 보내면 Grafana 가 자기 URL 을 https 로 만듭니다.

`HTTP_PORT` 를 8080 같은 값으로 바꿔 80 을 앞단 프록시에 넘기고, ufw 에서 80 을 닫으십시오.
