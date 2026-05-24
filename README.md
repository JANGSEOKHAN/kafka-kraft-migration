# Kafka KRaft 마이그레이션 운영 가이드

ZooKeeper 기반 Kafka 클러스터를 KRaft 구조로 전환하고, 이후 Kafka 4.x 계열로 업그레이드하는 흐름을 정리한 운영 가이드입니다.
Kafka 3.9의 metadata migration 기능을 활용해 ZooKeeper metadata를 KRaft controller quorum으로 이관한 뒤, broker cutover와 binary upgrade까지 이어지는 절차를 기준으로 구성했습니다.

## 마이그레이션 흐름

```text
Pre-check
  -> Kafka 3.9 Migration Phase
  -> KRaft 안정화 확인
  -> ZooKeeper 연결 해제 / Broker Cutover
  -> Kafka 4.x Binary Upgrade
  -> Quorum, Topic, Lag, Produce/Consume 검증
```

## 저장소 구조

```text
docs/
  migration-runbook.md     # 단계별 작업 흐름과 검증 체크리스트
scripts/
  migrate-to-kraft-39.sh   # Kafka 3.9 KRaft migration phase 구성
  cutover-to-kraft-39.sh   # ZooKeeper dependency 제거 후 broker cutover
  upgrade-to-kafka-42.sh   # KRaft 전환 이후 Kafka 4.x binary upgrade
```

## Shell Script 설명

| Script | 목적 | 주요 작업 |
| --- | --- | --- |
| `migrate-to-kraft-39.sh` | ZooKeeper 기반 Kafka 3.9 클러스터를 KRaft migration phase로 전환 | 기존 Kafka/ZooKeeper 데이터 백업, controller 전용 설정 생성, controller storage format, `kafka-controller.service` 생성, broker에 `zookeeper.metadata.migration.enable=true` 적용 |
| `cutover-to-kraft-39.sh` | metadata migration 완료 후 broker를 KRaft only 구성으로 전환 | `server.properties` 백업, ZooKeeper 설정 제거, `process.roles=broker` 적용, controller quorum voters 반영, broker 순차 재시작 |
| `upgrade-to-kafka-42.sh` | KRaft 전환이 끝난 Kafka 클러스터의 binary upgrade | 기존 Kafka home 백업, 신규 Kafka binary 배치, 기존 config 복원, controller/broker service 재기동, version/service 상태 확인 |

## 1. 사전 점검

실행 전 아래 항목을 먼저 확인합니다.

- broker/controller 대상 노드와 ID 매핑
- Kafka cluster id
- topic replication factor, ISR, under-replicated partitions
- consumer group lag
- SCRAM/ACL 사용 시 인증/권한 영향도
- Kafka home, config, log directory 백업
- ZooKeeper data와 Kafka log directory 백업
- rollback 가능 시점과 cutover 이후 복구 전략

## 2. Kafka 3.9 KRaft Migration Phase

`migrate-to-kraft-39.sh`는 ZooKeeper metadata를 유지한 상태에서 KRaft controller를 추가하고, Kafka broker가 migration mode로 동작하도록 구성합니다.

```bash
./scripts/migrate-to-kraft-39.sh \
  <node-ip> \
  <controller-ip-a> <controller-ip-b> <controller-ip-c> \
  <cluster-id> \
  <controller-id> \
  <broker-id> \
  <kafka-user>
```

예시:

```bash
./scripts/migrate-to-kraft-39.sh \
  <node-a-ip> <controller-a-ip> <controller-b-ip> <controller-c-ip> \
  <cluster-id> 101 1 kafka
```

실행 후 확인:

```bash
systemctl status kafka-controller.service
systemctl status kafka.service

kafka-metadata-quorum.sh \
  --bootstrap-server <bootstrap-server> \
  describe --status
```

확인 기준:

- controller quorum이 정상 형성됨
- migration 관련 error 로그가 없음
- under-replicated partitions가 0
- produce/consume 테스트 성공

## 3. KRaft Cutover

metadata migration 완료 후 `cutover-to-kraft-39.sh`를 사용해 broker에서 ZooKeeper 설정을 제거하고 KRaft only 구성으로 전환합니다.
이 단계는 broker를 한 대씩 순차적으로 진행하는 방식이 안전합니다.

```bash
./scripts/cutover-to-kraft-39.sh \
  <node-ip> \
  <controller-ip-a> <controller-ip-b> <controller-ip-c> \
  <broker-id>
```

예시:

```bash
./scripts/cutover-to-kraft-39.sh \
  <node-a-ip> <controller-a-ip> <controller-b-ip> <controller-c-ip> 1
```

실행 후 확인:

```bash
grep "process.roles" <kafka-home>/config/server.properties
kafka-metadata-quorum.sh --bootstrap-server <bootstrap-server> describe --status
kafka-topics.sh --bootstrap-server <bootstrap-server> --list
```

확인 기준:

- broker 설정에 `process.roles=broker`가 적용됨
- ZooKeeper 관련 설정이 제거됨
- topic list 조회와 produce/consume 테스트가 정상 동작함

## 4. Kafka 4.x Binary Upgrade

KRaft 전환과 안정화 확인이 끝난 뒤 `upgrade-to-kafka-42.sh`로 Kafka binary를 교체합니다.
Kafka archive 경로와 Kafka home은 환경 변수로 지정할 수 있습니다.

```bash
KAFKA_TGZ=/tmp/kafka_2.13-4.2.0.tgz \
KAFKA_HOME=/usr/local/kafka \
KAFKA_USER=kafka \
./scripts/upgrade-to-kafka-42.sh
```

실행 후 확인:

```bash
kafka-topics.sh --version
kafka-metadata-quorum.sh --bootstrap-server <bootstrap-server> describe --status
kafka-consumer-groups.sh --bootstrap-server <bootstrap-server> --describe --all-groups
```

확인 기준:

- controller/broker service가 정상 기동됨
- Kafka CLI version이 기대 버전으로 표시됨
- quorum, topic, consumer group lag 상태가 정상임

## 검증 체크리스트

- [ ] controller quorum 정상
- [ ] under-replicated partitions 0
- [ ] produce/consume 테스트 성공
- [ ] consumer group lag 확인
- [ ] SCRAM/ACL 인증 및 권한 테스트 완료
- [ ] broker/controller 로그에 반복 error 없음
- [ ] Kafka binary upgrade 후 topic, ACL, consumer group 상태 확인

## 주의사항

- 이 스크립트는 운영 작업 흐름을 설명하기 위한 예시입니다. 실제 적용 전 staging 환경에서 반드시 검증합니다.
- controller id, broker id, listener, quorum voters, log directory, service name은 환경에 맞게 조정합니다.
- cutover 이후에는 ZooKeeper 기반으로 되돌리는 방식이 제한적이므로 백업과 rollback 기준을 먼저 정합니다.
- 보안 설정이 있는 클러스터는 `listener.security.protocol.map`, SCRAM, ACL, JAAS 설정을 별도로 반영해야 합니다.
