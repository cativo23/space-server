# Contributing to Space Server

Thanks for your interest in contributing! This project is a personal infrastructure setup, but contributions are welcome.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/space-server.git`
3. Create a feature branch: `git checkout -b feature/your-feature-name`
4. Make your changes
5. Test your changes locally
6. Commit with conventional commits: `git commit -m "feat: add new feature"`
7. Push to your fork: `git push origin feature/your-feature-name`
8. Open a Pull Request

## Commit Convention

We use [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` - New features
- `fix:` - Bug fixes
- `docs:` - Documentation changes
- `chore:` - Maintenance tasks
- `refactor:` - Code refactoring
- `test:` - Test additions or changes

## Code Style

- Use Docker Compose v2 syntax
- Keep configurations DRY (Don't Repeat Yourself)
- Document environment variables in `.env.example`
- Test changes in a local environment before submitting

## Testing

Before submitting a PR:

```bash
# Validate docker-compose files
docker compose config

# Test services start correctly
docker compose up -d

# Check logs for errors
docker compose logs
```

## Questions?

Open an issue for discussion before starting major changes.
