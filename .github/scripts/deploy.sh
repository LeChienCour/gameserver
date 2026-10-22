#!/usr/bin/env bash
# ==============================================================================
# Script Name: deploy.sh
# Description: Deploys the VoiceChatMod JAR and configuration to the EC2 server.
#              Supports AWS SSM Run Command (Zero-SSH via S3) with SSH fallback.
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

deployViaSsm() {
  local stage=$1
  local modSourceGlob=${MOD_JAR_GLOB:-"VoiceChatMod/build/libs/*.jar"}

  echo "Uploading mod artifacts and config to S3 (${S3_BUCKET}) for Zero-SSH SSM deployment..."
  aws s3 cp voicechatmod-common.toml "s3://${S3_BUCKET}/artifacts/${stage}/voicechatmod-common.toml"

  local jarFile
  for jarFile in $modSourceGlob; do
    if [ -f "$jarFile" ]; then
      aws s3 cp "$jarFile" "s3://${S3_BUCKET}/artifacts/${stage}/$(basename "$jarFile")"
    fi
  done

  echo "Triggering AWS SSM Run Command on instance ${INSTANCE_ID}..."
  local commandId
  commandId=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --comment "Deploy VoiceChatMod and restart Minecraft (${stage})" \
    --parameters "commands=[
      'set -euo pipefail',
      'mkdir -p ${MODS_DIR} ${CONFIG_DIR}',
      'aws s3 cp s3://${S3_BUCKET}/artifacts/${stage}/voicechatmod-common.toml ${CONFIG_DIR}/voicechatmod-common.toml',
      'aws s3 sync s3://${S3_BUCKET}/artifacts/${stage}/ ${MODS_DIR}/ --exclude \"*\" --include \"*.jar\"',
      'chown -R ec2-user:ec2-user ${MINECRAFT_DIR}',
      'chmod 644 ${CONFIG_DIR}/voicechatmod-common.toml ${MODS_DIR}/*.jar',
      'systemctl restart minecraft',
      'systemctl restart amazon-cloudwatch-agent',
      'systemctl is-active --quiet minecraft'
    ]" \
    --query "Command.CommandId" \
    --output text)

  echo "Waiting for SSM command ${commandId} to complete..."
  aws ssm wait command-executed --command-id "$commandId" --instance-id "$INSTANCE_ID"
  echo "✅ Zero-SSH SSM deployment completed successfully"
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

deployViaSsh() {
  local modSourceGlob=${MOD_JAR_GLOB:-"VoiceChatMod/build/libs/*.jar"}

  if [ -z "${INSTANCE_IP:-}" ] || [ -z "${SSH_PRIVATE_KEY:-}" ]; then
    echo "::error::Either (INSTANCE_ID + S3_BUCKET) for SSM or (INSTANCE_IP + SSH_PRIVATE_KEY) for SSH is required." >&2
    exit 1
  fi

  setupSshKey

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

  echo "Waiting for Minecraft service to become active..."
  local maxAttempts=30
  local attempt=0
  while [ "$attempt" -lt "$maxAttempts" ]; do
    if ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "ec2-user@${INSTANCE_IP}" \
      "sudo systemctl is-active --quiet minecraft"; then
      echo "✅ Minecraft service is active"
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
  local currentStage
  currentStage=$(resolveStage)
  echo "Deploying for stage: $currentStage"
  generateModConfig "$currentStage"

  if [ -n "${INSTANCE_ID:-}" ] && [ -n "${S3_BUCKET:-}" ]; then
    deployViaSsm "$currentStage"
  else
    deployViaSsh
  fi

  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "status=success" >> "$GITHUB_OUTPUT"
    echo "message=Server running successfully with mod deployed" >> "$GITHUB_OUTPUT"
  fi
}

main "$@"
