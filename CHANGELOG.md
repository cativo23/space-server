# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Complete migration scripts for automated server migration
- Blog posts documenting migration journey and debugging process
- GitHub issue templates for bug reports and feature requests
- CONTRIBUTING.md with contribution guidelines
- LICENSE file (MIT)

### Changed
- Migrated from laptop server to Hetzner VPS (8GB RAM)
- Updated Uptime Kuma from v1 to v2
- Improved README with complete tech stack documentation

## [1.0.0] - 2026-04-23

### Added
- Initial production deployment on Hetzner VPS
- 15+ containerized services with Docker Compose
- Traefik v3.6 reverse proxy with automatic SSL
- Ghost blog with MySQL backend
- Portfolio frontend and API (Laravel)
- Complete mail server with docker-mailserver + Roundcube
- Monitoring stack: Grafana + Prometheus + Uptime Kuma
- Centralized logging with Dozzle
- Automated migration scripts

### Infrastructure
- Server: Hetzner VPS (8GB RAM, Intel Xeon, Ubuntu 24.04)
- Downtime during migration: 12 minutes
- Services migrated: 15+
- SSL certificates: Let's Encrypt via Traefik

[Unreleased]: https://github.com/cativo23/space-server/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/cativo23/space-server/releases/tag/v1.0.0
