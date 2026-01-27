# Contributing

Thank you for your interest in contributing to this project!

## How to Contribute

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

## Development Setup

```bash
# Clone your fork
git clone https://github.com/your-username/clawdbot-aws-bedrock.git
cd clawdbot-aws-bedrock

# Test deployment
./scripts/deploy.sh test-stack us-west-2 your-keypair

# Make changes
# ...

# Test changes
./scripts/bedrock-precheck.sh us-west-2
```

## Pull Request Guidelines

- Keep changes focused and atomic
- Update documentation if needed
- Test your changes before submitting
- Follow existing code style
- Add comments for complex logic

## Reporting Issues

When reporting issues, please include:

- AWS region
- CloudFormation stack name
- Error messages
- Relevant logs
- Steps to reproduce

## Code of Conduct

Be respectful and constructive. We're all here to learn and improve.

## Questions?

Open an issue or join the discussion!
