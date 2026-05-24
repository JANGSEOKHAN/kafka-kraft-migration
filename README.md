# Kafka KRaft Migration Runbook

Apache Kafka 운영 환경에서 ZooKeeper 기반 메타데이터를 KRaft 구조로 전환하는 과정을 공개용으로 정리한 runbook입니다.

이 저장소는 실제 운영 환경의 내부 IP, 서버명, 계정, cluster id, 보안 설정값을 제거하고 placeholder 기반으로 재구성했습니다.

## Scope

- Kafka 3.9 기반 KRaft migration 준비
- controller/broker 설정 분리
- `zookeeper.metadata.migration.enable=true` 기반 migration phase
- broker cutover 이후 ZooKeeper dependency 제거
- Kafka 4.x binary upgrade 시 점검 항목

## Repository Structure

```text
docs/
  migration-runbook.md
scripts/
  migrate-to-kraft-39.sh
  cutover-to-kraft-39.sh
  upgrade-to-kafka-42.sh
```

## Safety Notes

- 실제 운영 적용 전 staging 환경에서 반드시 검증합니다.
- topic, ACL, SCRAM, consumer group lag, replication 상태를 함께 확인합니다.
- rollback을 위해 Kafka home, config, log directory를 사전에 백업합니다.
- public repository에는 실제 IP, account, credential, cluster id를 포함하지 않습니다.

## Example

```bash
./scripts/migrate-to-kraft-39.sh \
  <node-ip> <controller-ip-a> <controller-ip-b> <controller-ip-c> \
  <cluster-id> <controller-id> <broker-id> <kafka-user>
```
