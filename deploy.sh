#!/bin/bash

###############################################################################
# Clawdbot AWS Bedrock Deployment Script
# Usage: ./deploy.sh [stack-name] [region] [keypair-name]
###############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parameters
STACK_NAME=${1:-clawdbot-bedrock}
REGION=${2:-us-west-2}
KEYPAIR_NAME=${3}

echo -e "${BLUE}=========================================="
echo "Clawdbot AWS Bedrock Deployment"
echo "==========================================${NC}"
echo ""
echo "Stack Name: $STACK_NAME"
echo "Region: $REGION"
echo "Key Pair: ${KEYPAIR_NAME:-<will prompt>}"
echo ""

# Check prerequisites
echo -e "${BLUE}[1/4] Checking prerequisites...${NC}"

if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI not installed${NC}"
    exit 1
fi

if ! command -v session-manager-plugin &> /dev/null; then
    echo -e "${YELLOW}⚠️  SSM Session Manager Plugin not installed${NC}"
    echo "Install from: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
fi

# Check AWS credentials
if ! aws sts get-caller-identity --region $REGION &> /dev/null; then
    echo -e "${RED}❌ AWS credentials not configured${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Prerequisites OK${NC}"
echo ""

# Get keypair if not provided
if [ -z "$KEYPAIR_NAME" ]; then
    echo -e "${YELLOW}Available key pairs:${NC}"
    aws ec2 describe-key-pairs --region $REGION --query 'KeyPairs[*].KeyName' --output table
    echo ""
    read -p "Enter key pair name: " KEYPAIR_NAME
fi

# Deploy CloudFormation (pre-check runs automatically via Lambda)
echo -e "${BLUE}[2/4] Deploying CloudFormation stack...${NC}"
echo -e "${YELLOW}Note: Lambda pre-check will run automatically during deployment${NC}"

aws cloudformation create-stack \
  --stack-name $STACK_NAME \
  --template-body file://cloudformation/clawdbot-bedrock.yaml \
  --parameters \
    ParameterKey=KeyPairName,ParameterValue=$KEYPAIR_NAME \
    ParameterKey=ClawdbotModel,ParameterValue=anthropic.claude-opus-4-20250514 \
    ParameterKey=InstanceType,ParameterValue=t3.medium \
    ParameterKey=CreateVPCEndpoints,ParameterValue=true \
    ParameterKey=AutoEnableBedrock,ParameterValue=true \
  --capabilities CAPABILITY_IAM \
  --region $REGION

echo -e "${GREEN}✅ Stack creation initiated${NC}"
echo ""

# Wait for completion
echo -e "${BLUE}[3/4] Waiting for stack creation (10-15 minutes)...${NC}"
echo "Lambda pre-check is running automatically..."
echo "Monitor progress: https://console.aws.amazon.com/cloudformation/home?region=$REGION#/stacks"
echo ""

aws cloudformation wait stack-create-complete \
  --stack-name $STACK_NAME \
  --region $REGION

echo -e "${GREEN}✅ Stack created successfully${NC}"
echo ""

# Get outputs
echo -e "${BLUE}[4/4] Retrieving connection information...${NC}"

INSTANCE_ID=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query 'Stacks[0].Outputs[?OutputKey==`InstanceId`].OutputValue' \
  --output text \
  --region $REGION)

echo -e "${GREEN}=========================================="
echo "✅ Deployment Complete!"
echo "==========================================${NC}"
echo ""
echo "Instance ID: $INSTANCE_ID"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. Start port forwarding (keep this terminal open):"
echo -e "${BLUE}   aws ssm start-session \\"
echo "     --target $INSTANCE_ID \\"
echo "     --region $REGION \\"
echo "     --document-name AWS-StartPortForwardingSession \\"
echo "     --parameters '{\"portNumber\":[\"18789\"],\"localPortNumber\":[\"18789\"]}'${NC}"
echo ""
echo "2. Get gateway token (in a new terminal):"
echo -e "${BLUE}   aws ssm start-session --target $INSTANCE_ID --region $REGION${NC}"
echo "   Then run: ${BLUE}sudo su - ubuntu && cat ~/.clawdbot/gateway_token.txt${NC}"
echo ""
echo "3. Open in browser:"
echo -e "${BLUE}   http://localhost:18789/?token=<your-token>${NC}"
echo ""
echo "For detailed instructions, see: docs/DEPLOYMENT.md"
echo ""
