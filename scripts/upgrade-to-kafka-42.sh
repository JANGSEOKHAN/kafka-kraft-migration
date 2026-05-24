#!/usr/bin/env bash
set -euo pipefail

# Public example. Review paths and service names before use.

KAFKA_TGZ="${KAFKA_TGZ:-/tmp/kafka_2.13-4.2.0.tgz}"
KAFKA_USER="${KAFKA_USER:-kafka}"
KAFKA_HOME="${KAFKA_HOME:-/usr/local/kafka}"
EXPECT_VERSION="${EXPECT_VERSION:-4.2.0}"
BACKUP_ROOT="${BACKUP_ROOT:-/tmp/kafka-upgrade-$(date +%Y%m%d%H%M%S)}"
TMP_DIR="$(mktemp -d /tmp/kafka_extract_XXXX)"
OLD_BACKUP_HOME="$BACKUP_ROOT/kafka.home.before"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

service_exists() {
  local svc="$1"
  systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -Fxq "$svc"
}

echo "[1/8] Validate input"
[ -f "$KAFKA_TGZ" ] || { echo "Kafka archive not found: $KAFKA_TGZ"; exit 1; }
[ -e "$KAFKA_HOME" ] || { echo "Kafka home not found: $KAFKA_HOME"; exit 1; }

echo "[2/8] Stop services"
service_exists "kafka-controller.service" && sudo systemctl stop kafka-controller.service || true
service_exists "kafka.service" && sudo systemctl stop kafka.service || true

echo "[3/8] Backup current Kafka home"
sudo mkdir -p "$BACKUP_ROOT"
if [ -L "$KAFKA_HOME" ]; then
  OLD_HOME="$(readlink -f "$KAFKA_HOME")"
  sudo mv "$OLD_HOME" "$OLD_BACKUP_HOME"
  sudo rm -f "$KAFKA_HOME"
else
  sudo mv "$KAFKA_HOME" "$OLD_BACKUP_HOME"
fi

echo "[4/8] Extract new Kafka binary"
tar -xzf "$KAFKA_TGZ" -C "$TMP_DIR"
EXTRACTED_DIR="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[[ "$(basename "$EXTRACTED_DIR")" == *"$EXPECT_VERSION"* ]] || { echo "Unexpected Kafka version"; exit 1; }
sudo mv "$EXTRACTED_DIR" "$KAFKA_HOME"

echo "[5/8] Restore config"
[ -d "$OLD_BACKUP_HOME/config" ] && sudo cp -a "$OLD_BACKUP_HOME/config/." "$KAFKA_HOME/config/"

echo "[6/8] Recreate controller-only scripts"
sudo cp "$KAFKA_HOME/bin/kafka-run-class.sh" "$KAFKA_HOME/bin/kafka-controller-run-class.sh"
sudo cp "$KAFKA_HOME/bin/kafka-server-start.sh" "$KAFKA_HOME/bin/kafka-controller-start.sh"
sudo sed -i '/JMX_PORT/d;/KAFKA_JMX_OPTS/d;/KAFKA_JMX_PORT/d' "$KAFKA_HOME/bin/kafka-controller-run-class.sh"
sudo sed -i 's|exec $(dirname \$0)/kafka-run-class.sh|exec $(dirname \$0)/kafka-controller-run-class.sh|g' "$KAFKA_HOME/bin/kafka-controller-start.sh"
sudo chmod +x "$KAFKA_HOME/bin/kafka-controller-run-class.sh" "$KAFKA_HOME/bin/kafka-controller-start.sh"

echo "[7/8] Start services"
sudo chown -R "$KAFKA_USER:$KAFKA_USER" "$KAFKA_HOME"
sudo systemctl daemon-reload
service_exists "kafka-controller.service" && sudo systemctl start kafka-controller.service || true
service_exists "kafka.service" && sudo systemctl start kafka.service || true

echo "[8/8] Verify version and service status"
sudo -u "$KAFKA_USER" "$KAFKA_HOME/bin/kafka-topics.sh" --version || true
service_exists "kafka-controller.service" && sudo systemctl status kafka-controller.service --no-pager || true
service_exists "kafka.service" && sudo systemctl status kafka.service --no-pager || true
