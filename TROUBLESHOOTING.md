# Troubleshooting Guide

## Common Issues

### 1. Pre-Check Failed

**Symptom**: Pre-check script reports errors

**Solutions**:

```bash
# Check Bedrock service availability
aws bedrock list-foundation-models --region us-west-2

# If "AccessDeniedException":
# → Check IAM permissions
# → Verify Bedrock is available in your region

# If "Model not found":
# → Enable model in Bedrock Console
# → Wait for "Access granted" status
```

### 2. CloudFormation Stack Creation Failed

**Symptom**: Stack shows `CREATE_FAILED` status

**Solutions**:

```bash
# View failure reason
aws cloudformation describe-stack-events \
  --stack-name clawdbot-bedrock \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]' \
  --region us-west-2

# Common causes:
# - Insufficient IAM permissions
# - Invalid key pair name
# - Region doesn't support Bedrock
# - Model not enabled

# Delete failed stack
aws cloudformation delete-stack \
  --stack-name clawdbot-bedrock \
  --region us-west-2

# Fix issue and redeploy
```

### 3. Cannot Connect via SSM

**Symptom**: `aws ssm start-session` fails

**Solutions**:

```bash
# Check SSM agent status
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --region us-west-2

# If no results:
# → Wait 2-3 minutes for agent to register
# → Check IAM role has AmazonSSMManagedInstanceCore policy

# Check instance status
aws ec2 describe-instance-status \
  --instance-ids $INSTANCE_ID \
  --region us-west-2

# Restart SSM agent (via SSH if available)
ssh -i key.pem ubuntu@<public-ip>
sudo snap restart amazon-ssm-agent
```

### 4. Port Forwarding Fails

**Symptom**: Port forwarding command hangs or fails

**Solutions**:

```bash
# Check if port 18789 is already in use locally
lsof -i :18789
# If in use, kill the process or use different port

# Use different local port
aws ssm start-session \
  --target $INSTANCE_ID \
  --region us-west-2 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["18789"],"localPortNumber":["8789"]}'

# Then access: http://localhost:8789/?token=<token>
```

### 5. Clawdbot Service Not Running

**Symptom**: Cannot access Web UI, service down

**Solutions**:

```bash
# Connect to instance
aws ssm start-session --target $INSTANCE_ID --region us-west-2
sudo su - ubuntu

# Check service status
systemctl --user status clawdbot-gateway

# View logs
journalctl --user -u clawdbot-gateway -n 100

# Restart service
systemctl --user restart clawdbot-gateway

# If service doesn't exist, reinstall
clawdbot daemon install
```

### 6. Bedrock API Errors

**Symptom**: Clawdbot responds with errors

**Common Errors**:

#### "AccessDeniedException"

```bash
# Check IAM role permissions
aws iam get-role-policy \
  --role-name <ClawdbotInstanceRole> \
  --policy-name BedrockAccessPolicy

# Verify role is attached to instance
aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].IamInstanceProfile'
```

#### "ModelNotReadyException"

```bash
# Model not enabled in Bedrock Console
# → Go to Bedrock Console → Model access → Enable model
```

#### "ThrottlingException"

```bash
# Too many requests
# → Reduce usage
# → Request quota increase in Service Quotas console
```

### 7. High Costs

**Symptom**: Unexpected AWS bill

**Solutions**:

```bash
# Check Bedrock usage
aws ce get-cost-and-usage \
  --time-period Start=2026-01-01,End=2026-01-31 \
  --granularity DAILY \
  --metrics BlendedCost \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Bedrock"]}}'

# View CloudTrail logs to find heavy usage
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=InvokeModel \
  --max-items 100

# Optimize:
# 1. Switch to cheaper model (Sonnet instead of Opus)
# 2. Reduce max_tokens in config
# 3. Set up cost alerts
```

### 8. Setup Script Failed

**Symptom**: `/var/log/clawdbot-setup.log` shows errors

**Solutions**:

```bash
# View full log
aws ssm start-session --target $INSTANCE_ID --region us-west-2
sudo cat /var/log/clawdbot-setup.log | grep -i error

# Common issues:
# - NVM installation failed → Rerun manually
# - npm install failed → Check network connectivity
# - Docker not started → sudo systemctl start docker

# Manual recovery
sudo su - ubuntu
cd ~

# Install NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
source ~/.bashrc

# Install Node.js
nvm install 22
nvm use 22

# Install Clawdbot
npm install -g clawdbot@latest

# Configure and start
clawdbot daemon install
```

## Debugging Tips

### View Real-Time Logs

```bash
# Gateway logs
journalctl --user -u clawdbot-gateway -f

# System logs
tail -f /var/log/clawdbot-setup.log

# Docker logs (if using sandbox)
docker ps
docker logs -f <container-id>
```

### Check Configuration

```bash
# View Clawdbot config
cat ~/.clawdbot/clawdbot.json | jq .

# Verify Bedrock config
cat ~/.clawdbot/clawdbot.json | jq '.agents.defaults.model'

# Check AWS credentials
aws sts get-caller-identity
```

### Test Components

```bash
# Test Bedrock
aws bedrock-runtime invoke-model \
  --model-id anthropic.claude-3-5-sonnet-20241022-v2:0 \
  --body '{"anthropic_version":"bedrock-2023-05-31","max_tokens":10,"messages":[{"role":"user","content":"test"}]}' \
  test.txt

# Test Docker
docker run hello-world

# Test Gateway
curl http://localhost:18789/health
```

## Performance Issues

### Slow Response Times

**Causes**:
- Network latency to Bedrock
- Large context windows
- Heavy model (Opus vs Sonnet)

**Solutions**:

```bash
# 1. Enable VPC endpoints (if not already)
# → Reduces latency by 30-50%

# 2. Switch to faster model
# Edit ~/.clawdbot/clawdbot.json:
"model": "anthropic.claude-3-5-sonnet-20241022-v2:0"

# 3. Reduce max tokens
"maxTokens": 4096  # Instead of 8192

# 4. Use larger instance
# Update CloudFormation: InstanceType=t3.large
```

### High Memory Usage

```bash
# Check memory
free -h

# Check Docker containers
docker stats

# Restart service
systemctl --user restart clawdbot-gateway

# If persistent, use larger instance
```

## Network Issues

### Cannot Reach Bedrock

```bash
# Check VPC endpoint status
aws ec2 describe-vpc-endpoints \
  --filters "Name=service-name,Values=com.amazonaws.us-west-2.bedrock-runtime" \
  --region us-west-2

# Check security group
aws ec2 describe-security-groups \
  --group-ids <vpce-sg-id> \
  --region us-west-2

# Test connectivity
curl -v https://bedrock-runtime.us-west-2.amazonaws.com
```

### SSM Connection Drops

```bash
# Check SSM VPC endpoint
aws ec2 describe-vpc-endpoints \
  --filters "Name=service-name,Values=com.amazonaws.us-west-2.ssm" \
  --region us-west-2

# Restart SSM agent
sudo snap restart amazon-ssm-agent

# Check instance connectivity
aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["echo test"]' \
  --region us-west-2
```

## Getting Help

### Check Logs First

```bash
# Setup logs
cat /var/log/clawdbot-setup.log

# Service logs
journalctl --user -u clawdbot-gateway -n 100

# CloudFormation events
aws cloudformation describe-stack-events \
  --stack-name clawdbot-bedrock \
  --region us-west-2
```

### Community Support

- **Clawdbot Issues**: https://github.com/clawdbot/clawdbot/issues
- **Clawdbot Discord**: https://discord.gg/clawdbot
- **AWS re:Post**: https://repost.aws/tags/bedrock

### AWS Support

If you have AWS Support:
1. Open a case in AWS Console
2. Select "Technical Support"
3. Category: "Amazon Bedrock" or "Systems Manager"
4. Include:
   - Stack name
   - Instance ID
   - Error messages
   - CloudFormation events
   - Relevant logs

## Emergency Procedures

### Instance Unresponsive

```bash
# 1. Check instance status
aws ec2 describe-instance-status --instance-ids $INSTANCE_ID

# 2. Reboot instance
aws ec2 reboot-instances --instance-ids $INSTANCE_ID

# 3. If still unresponsive, stop and start
aws ec2 stop-instances --instance-ids $INSTANCE_ID
aws ec2 start-instances --instance-ids $INSTANCE_ID
```

### Data Recovery

```bash
# 1. Create snapshot
VOLUME_ID=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' \
  --output text)

aws ec2 create-snapshot \
  --volume-id $VOLUME_ID \
  --description "Clawdbot backup"

# 2. Create new volume from snapshot
aws ec2 create-volume \
  --snapshot-id $SNAPSHOT_ID \
  --availability-zone us-west-2a

# 3. Attach to new instance
```

### Complete Rebuild

```bash
# 1. Backup configuration
aws ssm start-session --target $INSTANCE_ID
sudo su - ubuntu
tar -czf ~/clawdbot-backup.tar.gz ~/.clawdbot/

# 2. Delete stack
aws cloudformation delete-stack --stack-name clawdbot-bedrock

# 3. Redeploy
./scripts/deploy.sh

# 4. Restore configuration
# Upload backup and extract
```
