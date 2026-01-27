# Deployment Guide

## Prerequisites

### 1. Install AWS CLI

**macOS:**
```bash
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
```

**Linux:**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

**Windows:**
Download from: https://awscli.amazonaws.com/AWSCLIV2.msi

### 2. Install SSM Session Manager Plugin

**macOS (ARM):**
```bash
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac_arm64/session-manager-plugin.pkg" -o "session-manager-plugin.pkg"
sudo installer -pkg session-manager-plugin.pkg -target /
```

**macOS (Intel):**
```bash
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac/session-manager-plugin.pkg" -o "session-manager-plugin.pkg"
sudo installer -pkg session-manager-plugin.pkg -target /
```

**Linux:**
```bash
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
sudo dpkg -i session-manager-plugin.deb
```

### 3. Configure AWS CLI

```bash
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Enter default region (e.g., us-west-2)
# Enter default output format (json)
```

### 4. Create EC2 Key Pair

```bash
aws ec2 create-key-pair \
  --key-name clawdbot-key \
  --query 'KeyMaterial' \
  --output text > clawdbot-key.pem

chmod 400 clawdbot-key.pem
```

### 5. Enable Bedrock Models

Visit [Bedrock Console](https://console.aws.amazon.com/bedrock/):
1. Go to "Model access"
2. Click "Manage model access"
3. Enable:
   - ✅ Claude 3.5 Sonnet v2
   - ✅ Claude Opus 4
   - ✅ Claude 3 Haiku
4. Click "Save changes"
5. Wait for "Access granted" status

## Deployment

### Option 1: Using Helper Script (Recommended)

```bash
cd clawdbot-aws-bedrock
./scripts/deploy.sh clawdbot-bedrock us-west-2 clawdbot-key
```

### Option 2: Manual Deployment

```bash
# 1. Run pre-check
./scripts/bedrock-precheck.sh us-west-2

# 2. Deploy stack
aws cloudformation create-stack \
  --stack-name clawdbot-bedrock \
  --template-body file://cloudformation/clawdbot-bedrock.yaml \
  --parameters \
    ParameterKey=KeyPairName,ParameterValue=clawdbot-key \
    ParameterKey=ClawdbotModel,ParameterValue=anthropic.claude-opus-4-20250514 \
    ParameterKey=InstanceType,ParameterValue=t3.medium \
    ParameterKey=CreateVPCEndpoints,ParameterValue=true \
  --capabilities CAPABILITY_IAM \
  --region us-west-2

# 3. Wait for completion
aws cloudformation wait stack-create-complete \
  --stack-name clawdbot-bedrock \
  --region us-west-2
```

### Option 3: AWS Console

1. Go to [CloudFormation Console](https://console.aws.amazon.com/cloudformation/)
2. Click "Create stack" → "With new resources"
3. Upload `cloudformation/clawdbot-bedrock.yaml`
4. Fill in parameters:
   - Stack name: `clawdbot-bedrock`
   - Key Pair Name: Select your key pair
   - Clawdbot Model: `anthropic.claude-opus-4-20250514`
5. Check "I acknowledge that AWS CloudFormation might create IAM resources"
6. Click "Create stack"

## Accessing Clawdbot

### Step 1: Get Instance ID

```bash
INSTANCE_ID=$(aws cloudformation describe-stacks \
  --stack-name clawdbot-bedrock \
  --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' \
  --output text \
  --region us-west-2)

echo $INSTANCE_ID
```

### Step 2: Start Port Forwarding

```bash
aws ssm start-session \
  --target $INSTANCE_ID \
  --region us-west-2 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["18789"],"localPortNumber":["18789"]}'
```

Keep this terminal open!

### Step 3: Get Gateway Token

Open a new terminal:

```bash
# Connect to instance
aws ssm start-session --target $INSTANCE_ID --region us-west-2

# Switch to ubuntu user
sudo su - ubuntu

# Get token
cat ~/.clawdbot/gateway_token.txt
```

### Step 4: Open Web UI

Open in browser:
```
http://localhost:18789/?token=<your-token>
```

## Connecting Messaging Platforms

### WhatsApp

1. In Web UI: Channels → Add Channel → WhatsApp
2. Scan QR code with WhatsApp
3. Wait for connection

### Telegram

1. Create bot with [@BotFather](https://t.me/botfather)
2. Get bot token
3. In Web UI: Configure Telegram channel

### Discord

1. Create bot at [Discord Developer Portal](https://discord.com/developers/applications)
2. Get bot token
3. In Web UI: Configure Discord channel

### Slack

1. Create app at [Slack API](https://api.slack.com/apps)
2. Configure bot token scopes
3. In Web UI: Configure Slack channel

Full guide: https://docs.molt.bot/channels/

## Verification

### Check Setup Status

```bash
# Connect via SSM
aws ssm start-session --target $INSTANCE_ID --region us-west-2

# Check status
sudo su - ubuntu
cat ~/.clawdbot/setup_status.txt

# View logs
tail -100 /var/log/clawdbot-setup.log

# Check service
systemctl --user status clawdbot-gateway
```

### Test Bedrock Connection

```bash
# On the instance
aws bedrock-runtime invoke-model \
  --model-id anthropic.claude-3-5-sonnet-20241022-v2:0 \
  --body '{"anthropic_version":"bedrock-2023-05-31","max_tokens":10,"messages":[{"role":"user","content":"Hi"}]}' \
  output.txt

cat output.txt
```

## Updating

### Update Clawdbot

```bash
# Connect via SSM
aws ssm start-session --target $INSTANCE_ID --region us-west-2

# Update
sudo su - ubuntu
npm update -g clawdbot
systemctl --user restart clawdbot-gateway
```

### Update CloudFormation Stack

```bash
aws cloudformation update-stack \
  --stack-name clawdbot-bedrock \
  --template-body file://cloudformation/clawdbot-bedrock.yaml \
  --parameters \
    ParameterKey=ClawdbotModel,ParameterValue=anthropic.claude-3-5-sonnet-20241022-v2:0 \
  --capabilities CAPABILITY_IAM \
  --region us-west-2
```

## Cleanup

```bash
# Delete stack (removes all resources)
aws cloudformation delete-stack \
  --stack-name clawdbot-bedrock \
  --region us-west-2

# Wait for deletion
aws cloudformation wait stack-delete-complete \
  --stack-name clawdbot-bedrock \
  --region us-west-2
```

## Next Steps

- Configure messaging channels
- Install skills: `clawdbot skills install <skill-name>`
- Set up cron jobs: `clawdbot cron add "0 9 * * *" "Daily summary"`
- Explore Web UI features

For more details, see [Clawdbot Documentation](https://docs.molt.bot/).
