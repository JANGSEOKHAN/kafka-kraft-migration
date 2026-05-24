# Kafka KRaft Migration Runbook

Kafka 3.9에서 ZooKeeper 기반 metadata를 KRaft로 전환하고, 이후 Kafka 4.x 계열로 업그레이드하기 위한 공개용 작업 흐름입니다.

## 1. Pre-check

- broker count, controller quorum 계획 확인
- topic replication factor, ISR 상태 확인
- consumer group lag 확인
- SCRAM/ACL 적용 환경의 인증/권한 영향도 확인
- Kafka home, config, log directory 백업
- ZooKeeper data와 Kafka log directory 백업

## 2. Migration Phase

- controller 전용 config 생성
- `zookeeper.metadata.migration.enable=true` 활성화
- controller storage format 수행
- controller service 기동
- broker config에 controller quorum voters 반영
- migration 완료 로그 확인

## 3. Cutover Phase

- broker에서 ZooKeeper 관련 설정 제거
- `process.roles=broker` 적용
- KRaft quorum 기반 broker 재기동
- metadata quorum 상태 확인
- topic list, produce/consume test 수행

## 4. Upgrade Phase

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

## Public Sanitization

원본 작업 기록의 내부 IP, 서버명, 계정, cluster id, 운영 로그, 보안 정책 상세값은 제거했습니다.
