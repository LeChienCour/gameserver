#!/usr/bin/env bash
# ==============================================================================
# Script Name: deploy.sh
# Description: Deploys the VoiceChatMod JAR and configuration to the EC2 server
# ==============================================================================
set -euo pipefail

readonly MINECRAFT_DIR="/opt/minecraft"
readonly MODS_DIR="${MINECRAFT_DIR}/mods"
readonly CONFIG_DIR="${MINECRAFT_DIR}/runs/client/config"
readonly SSH_KEY_PATH="$HOME/.ssh/game_server_key"

cleanupOnExit() {
  rm -f "$SSH_KEY_PATH" voicechatmod-common.toml
}
trap cleanupOnExit EXIT

validateEnv() {
  if [ -z "${INSTANCE_IP:-}" ]; then
    echo "::error::INSTANCE_IP environment variable is required but not set." >&2
    exit 1
  fi
  if [ -z "${SSH_PRIVATE_KEY:-}" ]; then
    echo "::error::SSH_PRIVATE_KEY environment variable is required but not set." >&2
    exit 1
  fi
}

setupSshKey() {
  mkdir -p "$HOME/.ssh"
  {
    echo "-----BEGIN RSA PRIVATE KEY-----"
    echo "$SSH_PRIVATE_KEY" | fold -w 64
    echo "-----END RSA PRIVATE KEY-----"
  } > "$SSH_KEY_PATH"
  chmod 600 "$SSH_KEY_PATH"
}

getSsmParam() {
  local paramName=$1
  local fallbackValue=$2
  local value

  if value=$(aws ssm get-parameter --name "$paramName" --with-decryption --query 'Parameter.Value' --output text 2>/dev/null); then
    echo "$value"
  else
    echo "$fallbackValue"
  fi
}

resolveStage() {
  if [ -n "${PR_NUMBER:-}" ]; then
    STAGE="pr-${PR_NUMBER}"
  elif [ -n "${STAGE:-}" ]; then
    case "$STAGE" in
      "dev"|"qa"|"prod"|"pr-"*)
        ;;
      *)
        echo "::error::Invalid stage name: $STAGE" >&2
        exit 1
        ;;
    esac
  else
    STAGE="dev"
  fi
  echo "$STAGE"
}

generateModConfig() {
  local stage=$1
  local defaultWsUrl="wss://${stage}-api.gameserver.example.com"

  local websocketUrl
  local apiKey
  local userPoolId
  local userPoolClientId

  websocketUrl=$(getSsmParam "/game-server/${stage}/websocket/stage-url" "$defaultWsUrl")
  apiKey=$(getSsmParam "/game-server/${stage}/websocket/api-key" "dev-key")
  userPoolId=$(getSsmParam "/game-server/${stage}/cognito/user-pool-id" "us-east-1_dev")
  userPoolClientId=$(getSsmParam "/game-server/${stage}/cognito/user-pool-client-id" "dev-client")

  cat > voicechatmod-common.toml << EOF
# Voice Chat Mod Configuration
enableVoiceChat = true
defaultVolume = 0.7
maxVoiceDistance = 64
reconnectionAttempts = 3
reconnectionDelay = 5
websocketStageUrl = "${websocketUrl}"
websocketApiKey = "${apiKey}"
userPoolId = "${userPoolId}"
userPoolClientId = "${userPoolClientId}"
selectedMicrophone = ""
useSystemDefaultMic = true
microphoneBoost = 1.0
EOF
}

deployToServer() {
  local modSourceGlob=${MOD_JAR_GLOB:-"VoiceChatMod/build/libs/*.jar"}

  echo "Preparing remote directories on ${INSTANCE_IP}..."
  ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "ec2-user@${INSTANCE_IP}" \
    "sudo mkdir -p ${MODS_DIR} ${CONFIG_DIR} && sudo chown -R ec2-user:ec2-user ${MINECRAFT_DIR}"

  echo "Copying configuration and mod JARs to ${INSTANCE_IP}..."
  scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no voicechatmod-common.toml "ec2-user@${INSTANCE_IP}:${CONFIG_DIR}/voicechatmod-common.toml"
  # shellcheck disable=SC2086
  scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no $modSourceGlob "ec2-user@${INSTANCE_IP}:${MODS_DIR}/"

  ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "ec2-user@${INSTANCE_IP}" \
    "sudo chmod 644 ${CONFIG_DIR}/voicechatmod-common.toml ${MODS_DIR}/*.jar"

  echo "Restarting Minecraft and CloudWatch services..."
  ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "ec2-user@${INSTANCE_IP}" \
    "sudo systemctl restart minecraft && sudo systemctl restart amazon-cloudwatch-agent"
}

waitForServerReady() {
  echo "Waiting for Minecraft service to become active..."
  local maxAttempts=30
  local attempt=0

  while [ "$attempt" -lt "$maxAttempts" ]; do
    if ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "ec2-user@${INSTANCE_IP}" \
      "sudo systemctl is-active --quiet minecraft"; then
      echo "✅ Minecraft service is active"
      if [ -n "${GITHUB_OUTPUT:-}" ]; then
        echo "status=success" >> "$GITHUB_OUTPUT"
        echo "message=Server running successfully with mod deployed" >> "$GITHUB_OUTPUT"
      fi
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 5
  done

  echo "❌ Minecraft server failed to reach active state" >&2
  return 1
}

main() {
  echo "Starting deployment..."
  validateEnv
  setupSshKey
  local currentStage
  currentStage=$(resolveStage)
  echo "Deploying for stage: $currentStage"
  generateModConfig "$currentStage"
  deployToServer
  waitForServerReady
}

main "$@"
