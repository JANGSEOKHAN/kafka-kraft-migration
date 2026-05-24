#!/usr/bin/env bash
set -euo pipefail

# Usage:
# ./migrate-to-kraft-39.sh <NODE_IP> <CONTROLLER_IP1> <CONTROLLER_IP2> <CONTROLLER_IP3> <CLUSTER_ID> <CONTROLLER_ID> <BROKER_ID> <KAFKA_USER>

NODE_IP="${1:?NODE_IP required}"
CONTROLLER_IPS=("${2:?CONTROLLER_IP1 required}" "${3:?CONTROLLER_IP2 required}" "${4:?CONTROLLER_IP3 required}")
CLUSTER_ID="${5:?CLUSTER_ID required}"
CONTROLLER_ID="${6:?CONTROLLER_ID required}"
BROKER_ID="${7:?BROKER_ID required}"
KAFKA_USER="${8:?KAFKA_USER required}"

KAFKA_HOME="${KAFKA_HOME:-/usr/local/kafka}"
JAVA_HOME="${JAVA_HOME:-/usr/local/java}"
BROKER_LOG="${BROKER_LOG:-/data/kafka}"
CONTROLLER_LOG="${CONTROLLER_LOG:-/data/controller}"
ZOOKEEPER_LOG="${ZOOKEEPER_LOG:-/data/zookeeper}"
BACKUP_ROOT="${BACKUP_ROOT:-/tmp/kafka-kraft-migration-backup}"

CONTROLLER_CONFIG="$KAFKA_HOME/config/kraft/controller.properties"
BROKER_CONFIG="$KAFKA_HOME/config/server.properties"
CTRL_START="$KAFKA_HOME/bin/kafka-controller-start.sh"
CTRL_RUNCLASS="$KAFKA_HOME/bin/kafka-controller-run-class.sh"

echo "[1/9] Create backup directories"
sudo mkdir -p "$BACKUP_ROOT"/{broker,zookeeper,kafka-home,zookeeper-home}

echo "[2/9] Backup current data and config"
[ -d "$BROKER_LOG" ] && sudo cp -a "$BROKER_LOG" "$BACKUP_ROOT/broker/" || true
[ -d "$ZOOKEEPER_LOG" ] && sudo cp -a "$ZOOKEEPER_LOG" "$BACKUP_ROOT/zookeeper/" || true
[ -d "$KAFKA_HOME" ] && sudo cp -a "$KAFKA_HOME" "$BACKUP_ROOT/kafka-home/" || true

echo "[3/9] Prepare controller log directory"
sudo mkdir -p "$CONTROLLER_LOG"
sudo chown -R "$KAFKA_USER:$KAFKA_USER" "$CONTROLLER_LOG"

echo "[4/9] Write controller.properties for migration phase"
cat <<EOL | sudo tee "$CONTROLLER_CONFIG" > /dev/null
process.roles=controller
node.id=$CONTROLLER_ID
controller.quorum.voters=101@${CONTROLLER_IPS[0]}:9093,102@${CONTROLLER_IPS[1]}:9093,103@${CONTROLLER_IPS[2]}:9093
controller.listener.names=CONTROLLER
listeners=CONTROLLER://0.0.0.0:9093
listener.security.protocol.map=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT
zookeeper.metadata.migration.enable=true
zookeeper.connect=${CONTROLLER_IPS[0]}:12181,${CONTROLLER_IPS[1]}:12181,${CONTROLLER_IPS[2]}:12181
inter.broker.listener.name=PLAINTEXT
log.dirs=$CONTROLLER_LOG
EOL

echo "[5/9] Format controller storage"
sudo -u "$KAFKA_USER" "$KAFKA_HOME/bin/kafka-storage.sh" format \
  --cluster-id "$CLUSTER_ID" \
  -c "$CONTROLLER_CONFIG" \
  --ignore-formatted

echo "[6/9] Create controller-only start scripts"
sudo cp "$KAFKA_HOME/bin/kafka-run-class.sh" "$CTRL_RUNCLASS"
sudo cp "$KAFKA_HOME/bin/kafka-server-start.sh" "$CTRL_START"
sudo sed -i '/JMX_PORT/d;/KAFKA_JMX_OPTS/d;/KAFKA_JMX_PORT/d' "$CTRL_RUNCLASS"
sudo sed -i 's|exec $(dirname \$0)/kafka-run-class.sh|exec $(dirname \$0)/kafka-controller-run-class.sh|g' "$CTRL_START"
sudo chmod +x "$CTRL_RUNCLASS" "$CTRL_START"

echo "[7/9] Create kafka-controller.service"
cat <<EOL | sudo tee /etc/systemd/system/kafka-controller.service > /dev/null
[Unit]
Description=Apache Kafka Controller (KRaft Migration)
After=network.target

[Service]
Type=simple
User=$KAFKA_USER
Group=$KAFKA_USER
Environment="JAVA_HOME=$JAVA_HOME"
ExecStart=$CTRL_START $CONTROLLER_CONFIG
ExecStop=$KAFKA_HOME/bin/kafka-server-stop.sh
Restart=on-failure
RestartSec=5
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
EOL

echo "[8/9] Write broker server.properties for migration phase"
cat <<EOL | sudo tee "$BROKER_CONFIG" > /dev/null
broker.id=$BROKER_ID
listeners=PLAINTEXT://0.0.0.0:9092
advertised.listeners=PLAINTEXT://$NODE_IP:9092
listener.security.protocol.map=PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT
inter.broker.protocol.version=3.9
zookeeper.metadata.migration.enable=true
zookeeper.connect=${CONTROLLER_IPS[0]}:12181,${CONTROLLER_IPS[1]}:12181,${CONTROLLER_IPS[2]}:12181
zookeeper.connection.timeout.ms=18000
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

echo "[9/9] Reload systemd and restart services"
sudo systemctl daemon-reload
sudo systemctl enable kafka-controller.service
sudo systemctl restart kafka-controller.service
sudo systemctl restart kafka.service

echo "Check controller logs for metadata migration completion before cutover."
