# 방화벽

## Docker 는 ufw 를 우회합니다

Docker 로 포트를 publish 하면 ufw 규칙이 적용되지 않습니다. Docker 가 자기 규칙을 `DOCKER-USER` / `FORWARD` 체인에 직접 넣기 때문에, `ufw deny` 를 걸어두어도 publish 된 컨테이너 포트는 외부에 그대로 열립니다. 방화벽이 켜져 있으니 안전하다고 착각하기 딱 좋은 지점입니다.

[ufw-docker](https://github.com/chaifeng/ufw-docker) 가 `DOCKER-USER` 체인에 규칙을 넣어 이 구멍을 막습니다. `install.sh install` 이 ufw 가 설치된 호스트에서 이것을 함께 넣습니다. 원하지 않으면 `--no-ufw` 를 주십시오.

`ufw` 자체가 꺼져 있으면 먼저 켜야 합니다. **SSH 를 허용한 다음에 켜십시오.** 순서를 바꾸면 접속이 끊깁니다.

```sh
sudo ufw allow from YOUR_PC_IP to any port 22 proto tcp
sudo ufw enable
```

## route allow 와 allow 의 차이

ufw-docker 를 설치하면 publish 된 컨테이너 포트가 기본 차단됩니다. 열어줄 대상을 명시해야 합니다.

```sh
sudo ufw route allow proto tcp from YOUR_PC_IP to any port 80
```

`ufw route` 는 **publish 된 포트**, 즉 bridge 네트워크 컨테이너에 적용됩니다. 이 트래픽은 호스트를 거쳐 컨테이너로 전달(FORWARD)되기 때문입니다.

`network_mode: host` 로 뜬 컨테이너는 호스트가 직접 포트를 듣는 것이라 일반 `ufw allow` 규칙이 적용됩니다.

포트를 지정하지 않은 `ufw allow from CIDR` 은 쓰지 마십시오. 그 대역에 모든 포트가 열립니다. 실제로 겪은 사례인데, 어떤 서버에 `Anywhere ALLOW IN 134.75.248.0/23` 규칙이 있어서 의도하지 않은 내부 포트까지 그 대역에 노출되어 있었습니다.

## containerlab 은 스스로 구멍을 뚫습니다

containerlab 은 랩 노드에 외부에서 접근할 수 있게 하려고 **`DOCKER-USER` 체인에 자기 관리망을 허용하는 규칙을 자동으로 추가합니다.** ufw-docker 로 막아둔 것을 containerlab 이 자기 대역만큼은 뚫는다는 뜻입니다.

원하지 않으면 토폴로지에서 끕니다. 이 설정이 있으면 containerlab 이 iptables 를 아예 건드리지 않습니다.

```yaml
mgmt:
  external-access: false
```

단, 이것은 **인바운드만** 막습니다. 랩이 밖으로 나가는 것은 그대로 됩니다. 아웃바운드까지 막는 방법은 [랩 격리](lab-isolation.ko.md) 를 보십시오.

## 컨테이너에서 호스트로 접근

bridge 네트워크 컨테이너가 호스트에서 돌아가는 서비스에 접근해야 하는 경우가 있습니다. `host.docker.internal` 을 쓰면 됩니다.

```yaml
services:
  myapp:
    extra_hosts: ["host.docker.internal:host-gateway"]
```

**ufw 가 켜져 있으면 이것만으로는 안 됩니다.** 컨테이너에서 호스트로 가는 트래픽은 FORWARD 가 아니라 INPUT 이라 ufw-docker 가 관여하지 않고, ufw 의 기본 incoming deny 정책에 막힙니다. ICMP 는 ufw 가 기본 허용하므로 ping 은 되는데 TCP 는 안 되어서 원인을 찾기 어렵습니다.

해당 브릿지 대역에서 그 포트로 가는 것을 허용해야 합니다.

```sh
sudo ufw allow from 172.30.255.0/24 to any port 8090 proto tcp
```

`ufw status` 에 규칙이 보이는데도 안 되면 **앞에 있는 다른 규칙이 먼저 매칭되는지** 확인하십시오. iptables 는 첫 매칭이 이깁니다. 이전에 넣어둔 deny 규칙이 위에 있어서 나중에 추가한 allow 가 도달하지 못하는 경우가 있습니다.

```sh
sudo iptables -n -L ufw-user-input | grep 8090
```

이런 이유로 clabhost 는 caddy, containerlab-web, auth shim, 편집기를 전부 `network_mode: host` 로 둡니다. 이들 사이의 통신은 127.0.0.1 이거나 유닉스 소켓이라 ufw 를 지나지 않습니다. 브릿지에 있는 것은 prometheus, grafana, node-exporter, cadvisor 뿐이고, 이들은 호스트로 나갈 일이 없습니다.
