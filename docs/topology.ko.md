# 토폴로지 작성

실제 장비를 모사할 때 알아두면 좋은 것들입니다.

## MAC 은 모든 kind 에서 지정할 수 있습니다

링크 엔드포인트에 `mac` 을 씁니다. 스키마가 형식까지 검사합니다.

```yaml
topology:
  nodes:
    r1: {kind: linux, image: alpine:latest}
    r2: {kind: linux, image: alpine:latest}
  links:
    - type: veth
      endpoints:
        - node: r1
          interface: eth1
          mac: 00:1c:73:aa:bb:01
        - node: r2
          interface: eth1
          mac: 00:1c:73:aa:bb:02
```

선언한 값이 그대로 들어갑니다. 실제 장비 MAC 을 넣어서 라이선스나 DHCP 예약을 재현할 수 있습니다.

`mac` 을 쓰려면 확장 링크 문법이 필요하고, 확장 문법에는 `type` 을 반드시 적어야 합니다. 빠뜨리면 이런 오류가 납니다.

```
Failed to read topology file: yaml: unmarshal errors:
  line 17: cannot unmarshal !!map into string
```

## 관리 IP 는 노드마다 고정할 수 있습니다

```yaml
mgmt:
  ipv4-subnet: 172.30.101.0/24
topology:
  nodes:
    r1:
      kind: linux
      image: alpine:latest
      mgmt-ipv4: 172.30.101.11
```

## 인터페이스 IP 는 네 kind 에서만 동작합니다

링크 엔드포인트의 `ipv4` / `ipv6` 필드는 **`nokia_srlinux`, `arista_ceos`, `vyosnetworks_vyos`, `cisco_iol`** 에서만 적용됩니다. 공식 문서에 명시되어 있습니다.

다른 kind 에서는 **스키마 검증은 통과하지만 경고도 오류도 없이 조용히 무시됩니다.** `linux` kind 로 `ipv4: 10.99.0.1/30` 을 선언하고 배포해 보면 인터페이스에 링크로컬 주소만 붙어 있고 통신이 되지 않습니다. 오타처럼 보이지도 않아서 원인을 찾기 어렵습니다.

지원되지 않는 kind 에서는 `exec` 로 직접 설정합니다.

```yaml
nodes:
  r1:
    kind: linux
    image: alpine:latest
    exec:
      - ip addr add 10.99.0.1/30 dev eth1
      - ip link set eth1 up
```

실제 장비 config 를 쓰는 경우에는 config 안에 이미 주소가 들어있으므로 이 제약이 무관합니다.

## 실제 장비 config 넣기

`startup-config` 에 파일을 지정하면 부팅 시 로드됩니다.

```yaml
nodes:
  seoul-r1:
    kind: nokia_srlinux
    image: ghcr.io/nokia/srlinux
    startup-config: configs/seoul-r1.cfg
```

## 물리망에 붙이기

노드를 호스트의 물리 인터페이스에 직접 연결할 수 있습니다. 랩 노드가 실제 LAN 에 올라가 진짜 IP 를 받습니다.

```yaml
links:
  - type: macvlan
    endpoint:
      node: r1
      interface: eth1
      mac: 00:1c:73:aa:bb:01      # 선택
    host-interface: eth0
    mode: bridge                   # 기본값
```

macvlan 자식은 부모 인터페이스를 가진 **호스트 자신과는 통신할 수 없습니다.** 리눅스 macvlan 의 구조적 제약입니다. 랩 노드와 이 서버가 통신해야 하면 다른 방법을 쓰십시오.

| 방법 | 용도 |
| --- | --- |
| `type: macvlan` + `host-interface` | 노드를 물리 NIC 에 직접 연결 |
| `type: host` + `host-interface` | veth 한쪽을 호스트 네임스페이스로 |
| kind `bridge` / `ovs-bridge` | 호스트의 기존 리눅스 브릿지나 OVS 에 연결 |
| `mgmt.bridge` | 관리망을 기존 브릿지로 백업. 다른 워크로드와 같은 L2 에 놓임 |
| 노드의 `network-mode: host` | 노드를 호스트 네트워크 네임스페이스에 |

## 링크 지연, 손실, 대역 제한

링크는 veth 쌍이므로 `tc netem` 이 걸립니다. containerlab 이 명령을 제공하고 API 와 Web UI 에도 있습니다. UNetLab / PNetLab 이 쓰는 것과 같은 메커니즘입니다.

지정할 수 있는 값은 `delay`, `jitter`, `loss`(%), `rate`(Kbit/s), `corruption`(%) 입니다. 측정해 보면 값이 정확합니다. 1 Gbit 를 100 Mbit 로 제한하면 실제로 99.3 Mbit/s 가 나오고, 손실 20% 를 걸면 18% 가 측정됩니다.

세 가지를 알아두어야 합니다.

**단방향입니다.** 지정한 인터페이스의 **송신** 방향에만 걸립니다. 한쪽에만 50ms 를 걸면 왕복 50ms 가 되고, 양쪽에 걸면 왕복 100ms 가 됩니다. "이 링크의 지연이 50ms" 를 원하면 양쪽 엔드포인트에 각각 걸어야 합니다.

**설정은 누적이 아니라 교체입니다.** 매번 netem qdisc 전체를 다시 씁니다. 이미 `delay` 가 걸린 인터페이스에 `loss` 만 보내면 delay 가 사라집니다. 원하는 값 전부를 매번 함께 보내야 합니다.

**재시작하면 사라집니다.** 런타임 상태이고 containerlab 토폴로지 스키마에 이 값을 담는 필드가 없습니다. 링크 속성은 `endpoints`, `mtu`, `ipv4`, `ipv6`, `vars`, `labels` 뿐입니다. 노드를 재시작하면 qdisc 가 초기 상태로 돌아갑니다.

배포 시점에 자동으로 적용하려면 노드의 `exec` 에 `tc` 명령을 넣습니다. 노드는 privileged 로 뜨므로 이미지에 `iproute2` 만 있으면 됩니다. 재배포는 견디지만 노드 단일 재시작은 여전히 견디지 못합니다.

```yaml
nodes:
  r1:
    kind: linux
    image: frrouting/frr:latest
    exec:
      - tc qdisc add dev eth1 root netem delay 30ms 3ms loss 1% rate 50mbit
```

## 랩은 재부팅해도 살아납니다

containerlab 은 랩 노드에 `restart: always` 를 붙입니다. 스택을 재시작하거나 업그레이드해도 랩은 영향받지 않고, **호스트를 재부팅해도 랩이 저절로 다시 올라옵니다.**

재부팅으로 정리되기를 기대하지 말고 명시적으로 지우십시오.

```sh
sudo containerlab destroy -t mylab.clab.yml
```
