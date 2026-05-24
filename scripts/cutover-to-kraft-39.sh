#!/usr/bin/env bash
set -euo pipefail

# Usage:
# ./cutover-to-kraft-39.sh <NODE_IP> <CONTROLLER_IP1> <CONTROLLER_IP2> <CONTROLLER_IP3> <BROKER_ID>

NODE_IP="${1:?NODE_IP required}"
CONTROLLER_IPS=("${2:?CONTROLLER_IP1 required}" "${3:?CONTROLLER_IP2 required}" "${4:?CONTROLLER_IP3 required}")
BROKER_ID="${5:?BROKER_ID required}"

KAFKA_HOME="${KAFKA_HOME:-/usr/local/kafka}"
BROKER_LOG="${BROKER_LOG:-/data/kafka}"
BROKER_CONFIG="$KAFKA_HOME/config/server.properties"
BACKUP_FILE="$KAFKA_HOME/config/server.properties.zk.$(date +%Y%m%d%H%M%S).bak"

echo "[1/4] Backup current broker config"
sudo cp "$BROKER_CONFIG" "$BACKUP_FILE"

echo "[2/4] Write KRaft broker config"
cat <<EOL | sudo tee "$BROKER_CONFIG" > /dev/null
process.roles=broker
node.id=$BROKER_ID
broker.id=$BROKER_ID
listeners=PLAINTEXT://0.0.0.0:9092
advertised.listeners=PLAINTEXT://$NODE_IP:9092
listener.security.protocol.map=PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT
inter.broker.listener.name=PLAINTEXT
controller.quorum.voters=101@${CONTROLLER_IPS[0]}:9093,102@${CONTROLLER_IPS[1]}:9093,103@${CONTROLLER_IPS[2]}:9093
controller.listener.names=CONTROLLER
log.dirs=$BROKER_LOG
num.partitions=1
offsets.topic.replication.factor=3
transaction.state.log.replication.factor=3
transaction.state.log.min.isr=2
group.initial.rebalance.delay.ms=0
log.retention.hours=168
log.retention.check.interval.ms=300000
EOL

echo "[3/4] Restart broker"
sudo systemctl restart kafka.service

echo "[4/4] Check broker state"
sudo systemctl status kafka.service --no-pager || true
echo "Run kafka-metadata-quorum.sh and produce/consume tests after all brokers are cut over."
