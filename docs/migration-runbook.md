# Kafka KRaft 마이그레이션 Runbook

Kafka 3.9에서 ZooKeeper 기반 metadata를 KRaft로 전환하고, 이후 Kafka 4.x 계열로 업그레이드하기 위한 작업 흐름입니다.

## Script Map

| 단계 | Script | 설명 |
| --- | --- | --- |
| Migration Phase | `scripts/migrate-to-kraft-39.sh` | controller 전용 설정과 service를 만들고 broker를 migration mode로 구성합니다. ZooKeeper metadata를 KRaft controller quorum으로 이관할 준비 단계입니다. |
| Cutover Phase | `scripts/cutover-to-kraft-39.sh` | migration 완료 후 broker에서 ZooKeeper 설정을 제거하고 `process.roles=broker` 기반 KRaft only 구성으로 전환합니다. |
| Upgrade Phase | `scripts/upgrade-to-kafka-42.sh` | KRaft 전환 이후 Kafka binary를 4.x 계열로 교체하고 controller/broker service를 재기동합니다. |

## 1. Pre-check

- broker count, controller quorum 계획 확인
- controller id와 broker id 매핑 확인
- Kafka cluster id 확인
- topic replication factor, ISR 상태 확인
- consumer group lag 확인
- SCRAM/ACL 적용 환경의 인증/권한 영향도 확인
- Kafka home, config, log directory 백업
- ZooKeeper data와 Kafka log directory 백업

## 2. Migration Phase

사용 script:

```bash
./scripts/migrate-to-kraft-39.sh \
  <node-ip> <controller-ip-a> <controller-ip-b> <controller-ip-c> \
  <cluster-id> <controller-id> <broker-id> <kafka-user>
```

주요 작업:

- controller 전용 config 생성
- `zookeeper.metadata.migration.enable=true` 활성화
- controller storage format 수행
- controller service 기동
- broker config에 controller quorum voters 반영
- migration 완료 로그 확인

## 3. Cutover Phase

사용 script:

```bash
./scripts/cutover-to-kraft-39.sh \
  <node-ip> <controller-ip-a> <controller-ip-b> <controller-ip-c> <broker-id>
```

주요 작업:

- broker에서 ZooKeeper 관련 설정 제거
- `process.roles=broker` 적용
- KRaft quorum 기반 broker 재기동
- metadata quorum 상태 확인
- topic list, produce/consume test 수행

## 4. Upgrade Phase

사용 script:

```bash
KAFKA_TGZ=/tmp/kafka_2.13-4.2.0.tgz ./scripts/upgrade-to-kafka-42.sh
```

주요 작업:

- Kafka binary 백업
- 신규 Kafka binary 배치
- 기존 config와 custom script 복원
- controller/broker service 순서대로 기동
- version, quorum, topic, consumer lag 확인

## 5. Validation

```bash
kafka-metadata-quorum.sh --bootstrap-server <bootstrap-server> describe --status
kafka-topics.sh --bootstrap-server <bootstrap-server> --list
kafka-consumer-groups.sh --bootstrap-server <bootstrap-server> --describe --all-groups
```

## 6. Rollback 관점

- migration phase 중 실패하면 controller service를 중지하고 백업한 Kafka/ZooKeeper data와 config를 기준으로 복구합니다.
- cutover 이후에는 ZooKeeper dependency 제거 상태가 되므로 사전 백업과 검증 기준이 중요합니다.
- binary upgrade 실패 시 기존 Kafka home 백업본을 복원하고 controller/broker service를 다시 기동합니다.
