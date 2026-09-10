# 실제 장비 config 로 테스트하기

실제 장비 config 를 그대로 넣어 공인 IP 가 잔뜩 들어간 망을 재현할 수 있습니다. 이 문서는 그 랩이 실제 인터넷으로 새어나가지 않게 하는 방법을 정리합니다.

## 공인 IP 는 그대로 써도 됩니다

데이터플레인 링크는 veth 쌍이고 양 끝이 각 컨테이너의 네트워크 네임스페이스 안에만 있습니다. 그래서 어떤 주소를 쓰든 호스트 라우팅 테이블에 나타나지 않습니다.

랩 안의 `1.1.1.1` 과 진짜 `1.1.1.1` 이 같은 서버에서 동시에 살아있을 수 있습니다. 실제로 확인한 결과입니다.

```
랩 안:  1.1.1.1 ↔ 1.1.1.2      0% loss, 0.069 ms   ← netns 안의 veth
호스트: → 진짜 1.1.1.1          0% loss, 3.6 ms     ← 실제 인터넷
호스트 라우팅 테이블            1.1.1.0/30 없음
```

왕복 시간 차이가 그 증거입니다. 전국에 흩어진 공인망을 통째로 복제해도 호스트나 실제 망에 영향이 없습니다.

## 그런데 기본값으로는 인터넷으로 나갑니다

노드의 default route 가 관리망을 향하고 Docker 가 그 대역에 NAT 를 걸어주기 때문입니다.

```
r1 routes:  default via 172.28.98.1 dev eth0
ping 9.9.9.9         → 0% packet loss        ← 진짜 인터넷 도달
nslookup google.com  → 142.250.198.142
```

실제 장비 config 에는 당연히 default route 가 들어있으므로, **랩에 없는 목적지로 가는 패킷이 실제 인터넷으로 새어나갑니다.** 공인망을 테스트할 때 가장 위험한 지점입니다.

`mgmt.external-access: false` 는 **인바운드만** 막습니다. 이것만으로는 부족합니다.

## 방법 1: 관리망은 살리고 NAT 만 끄기

관리망으로 노드에 붙어 config 를 넣으면서 인터넷만 차단하고 싶을 때 씁니다. 보통 이쪽이 원하는 그림입니다.

```yaml
mgmt:
  network: mylab-mgmt
  ipv4-subnet: 172.30.101.0/24
  external-access: false                                        # 인바운드 차단
  driver-opts:
    com.docker.network.bridge.enable_ip_masquerade: "false"     # 아웃바운드 차단
```

확인한 결과입니다.

| | 결과 |
| --- | --- |
| 랩 내부 통신 | 정상 |
| 인터넷 (`ping 9.9.9.9`) | 100% packet loss |
| DNS 조회 | 해석 안 됨 |
| 관리망 게이트웨이 | 도달 가능 — 노드 관리 계속 됨 |

## 방법 2: 완전한 air-gap

관리망 자체를 없앱니다. 노드에 `eth0` 이 생기지 않아 우회 경로가 물리적으로 존재하지 않습니다.

```yaml
mgmt:
  skip-when-unused: true
topology:
  nodes:
    r1:
      network-mode: none
```

노드에는 `lo` 와 데이터플레인 인터페이스만 남고, 탈출 시도는 `Network unreachable` 로 끝납니다. 관리망 자체가 생성되지 않습니다. 노드 접근은 `docker exec` 로만 됩니다.

## IX 처럼 한 노드만 외부로 내보내기

IX 나 트랜싯 사업자를 모사하려면 그 노드에만 관리망을 주고 나머지는 `network-mode: none` 으로 둡니다. 내부 노드는 IX 노드를 거치지 않고 밖으로 나갈 방법이 없습니다.

```yaml
name: ixlab
mgmt:
  network: ix-mgmt
  ipv4-subnet: 172.30.102.0/24
topology:
  nodes:
    ix:                                   # 유일한 출구
      kind: linux
      image: alpine:latest
      mgmt-ipv4: 172.30.102.10
      exec:
        - ip addr add 203.0.113.1/24 dev eth1
        - ip link set eth1 up
        - sysctl -w net.ipv4.ip_forward=1
    r1:                                   # 관리망 없음
      kind: linux
      image: alpine:latest
      network-mode: none
      exec:
        - ip addr add 203.0.113.11/24 dev eth1
        - ip link set eth1 up
        - ip route add default via 203.0.113.1
  links:
    - endpoints: ["ix:eth1", "r1:eth1"]
```

이 상태에서는 IX 노드만 인터넷에 닿고 `r1` 은 못 닿습니다. IX 노드에 NAT 를 걸어주면 그때부터 `r1` 도 나갑니다.

```sh
# ix 노드 안에서
iptables -t nat -A POSTROUTING -s 203.0.113.0/24 -o eth0 -j MASQUERADE
```

확인한 결과입니다.

| | 결과 |
| --- | --- |
| `ix` → 인터넷 | 도달 |
| `r1` → 인터넷 (IX 에 NAT 걸기 전) | 100% packet loss |
| `r1` → `ix` | 도달 |
| `r1` → 인터넷 (IX 에 NAT 건 후) | 도달 |

인터넷 도달성이 전적으로 IX 노드에 달려 있어서, 거기서 정책을 껐다 켰다 하며 시험할 수 있습니다. 실제 IX 나 트랜싯 사업자와 같은 동작입니다.

## 이 설정들은 전부 랩 파일 안에 있습니다

위의 격리, NAT, 관리망 설정은 모두 해당 랩의 `.clab.yml` 안에 들어갑니다. containerlab 에는 이런 정책을 담는 전역 설정 파일이 없습니다.

정책이 서로 다른 랩을 같은 서버에서 동시에 돌릴 수 있습니다. 확인한 결과입니다.

```
labX  (NAT 끔)     → 9.9.9.9   100% packet loss
labY  (기본값)      → 9.9.9.9     0% packet loss
                      같은 호스트에서 동시 구동
```

토폴로지 파일을 넘기면 격리 설정까지 함께 넘어갑니다. 실제 장비 config 들과 같이 git 에 넣어두면, 그 랩을 받는 사람이 호스트에 무엇을 설정해달라고 부탁할 필요가 없습니다.

호스트 전역인 것은 `/etc/docker/daemon.json` 의 주소 풀 하나뿐이고, 그것도 containerlab 이 아니라 Docker 설정입니다. [IP 대역 관리](addressing.ko.md) 를 보십시오.
