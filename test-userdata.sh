#!/bin/bash
# 这是从 CloudFormation UserData 提取的脚本，用于测试逻辑
# 不要在生产环境运行此脚本，仅用于验证

set -e

# 模拟 CloudFormation 参数
ClawdbotModel="anthropic.claude-3-5-sonnet-20241022-v2:0"
EnableSandbox="true"

echo "=========================================="
echo "Testing UserData Script Logic"
echo "=========================================="

# 测试 1: 检查必需命令
echo "[Test 1] Checking required commands..."
commands=("curl" "apt-get" "systemctl" "openssl" "python3")
for cmd in "${commands[@]}"; do
    if command -v $cmd &> /dev/null; then
        echo "  ✓ $cmd found"
    else
        echo "  ✗ $cmd NOT found"
    fi
done

# 测试 2: 检查 heredoc 语法
echo "[Test 2] Testing heredoc syntax..."

# 测试 UBUNTU_SCRIPT heredoc
cat << 'UBUNTU_SCRIPT' > /tmp/test-ubuntu.sh
set -e
cd ~
echo "NVM install would happen here"
export NVM_DIR="$HOME/.nvm"
echo "Node.js install would happen here"
UBUNTU_SCRIPT

if [ -f /tmp/test-ubuntu.sh ]; then
    echo "  ✓ UBUNTU_SCRIPT heredoc OK"
    rm /tmp/test-ubuntu.sh
else
    echo "  ✗ UBUNTU_SCRIPT heredoc FAILED"
fi

# 测试 JSON heredoc
cat > /tmp/test-config.json << JSONEOF
{
  "gateway": {
    "port": 18789,
    "bind": "loopback"
  },
  "agents": {
    "defaults": {
      "model": {
        "provider": "bedrock",
        "model": "$ClawdbotModel"
      }
    }
  }
}
JSONEOF

if [ -f /tmp/test-config.json ]; then
    echo "  ✓ JSONEOF heredoc OK"
    if python3 -c "import json; json.load(open('/tmp/test-config.json'))" 2>/dev/null; then
        echo "  ✓ JSON syntax valid"
    else
        echo "  ✗ JSON syntax INVALID"
    fi
    rm /tmp/test-config.json
else
    echo "  ✗ JSONEOF heredoc FAILED"
fi

# 测试 3: 测试 Python 单行命令
echo "[Test 3] Testing Python one-liner..."
echo '{"test": "value"}' > /tmp/test.json
if python3 -c 'import json; config = json.load(open("/tmp/test.json")); config["new"] = "added"; json.dump(config, open("/tmp/test.json", "w"), indent=2)'; then
    echo "  ✓ Python one-liner OK"
    if grep -q '"new": "added"' /tmp/test.json; then
        echo "  ✓ JSON modification successful"
    else
        echo "  ✗ JSON modification FAILED"
    fi
    rm /tmp/test.json
else
    echo "  ✗ Python one-liner FAILED"
fi

# 测试 4: 测试条件语句
echo "[Test 4] Testing conditional logic..."
if [ "$EnableSandbox" == "true" ]; then
    echo "  ✓ Sandbox would be enabled"
else
    echo "  ✓ Sandbox would be disabled"
fi

# 测试 5: 测试变量替换
echo "[Test 5] Testing variable substitution..."
TEST_VAR="test-value"
echo "Variable: $TEST_VAR" > /tmp/test-var.txt
if grep -q "test-value" /tmp/test-var.txt; then
    echo "  ✓ Variable substitution OK"
    rm /tmp/test-var.txt
else
    echo "  ✗ Variable substitution FAILED"
fi

echo ""
echo "=========================================="
echo "All tests completed!"
echo "=========================================="
