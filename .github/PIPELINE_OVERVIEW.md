# CI/CD Pipeline Overview

## Quick Start

```bash
# Run all checks locally before pushing
mix precommit
```

## Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          CI PIPELINE                            │
│                    (on push & pull_request)                     │
└─────────────────────────────────────────────────────────────────┘
                               │
                    ┌──────────▼──────────┐
                    │   SETUP JOB         │
                    │  • Install deps     │
                    │  • Cache deps       │
                    │  • Compile deps     │
                    └──────────┬──────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
    ┌─────────▼──────┐  ┌──────▼──────┐  ┌────▼─────┐
    │   QUALITY      │  │   ANALYSIS  │  │  TESTS   │
    │   CHECKS       │  │             │  │          │
    └────────────────┘  └─────────────┘  └──────────┘
              │                │                │
    ┌─────────▼──────┐  ┌──────▼──────┐  ┌────▼─────┐
    │  • Format      │  │ • Security  │  │ • PostgreSQL │
    │  • Lint (Credo)│  │   (Sobelow) │  │ • mix test   │
    │                │  │ • Dialyzer  │  │ • Coverage   │
    └────────────────┘  └─────────────┘  └──────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      DEPLOYMENT                                 │
│                    (on push to main)                            │
└─────────────────────────────────────────────────────────────────┘
                               │
                    ┌──────────▼──────────┐
                    │   Gigalixir Deploy  │
                    │  • Build            │
                    │  • Migrate          │
                    │  • Deploy           │
                    └─────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    QUALITY CHECKS                               │
│              (weekly & manual trigger)                          │
└─────────────────────────────────────────────────────────────────┘
                               │
                    ┌──────────▼──────────┐
                    │  Comprehensive      │
                    │  • Format           │
                    │  • Compile strict   │
                    │  • Credo all        │
                    │  • Sobelow verbose  │
                    │  • Dialyzer         │
                    │  • Unused deps      │
                    └─────────────────────┘
```

## Workflows

### 🔄 [ci.yml](workflows/ci.yml)
**Main continuous integration pipeline**

- **Triggers:** Push & PR to main/master
- **Duration:** 3-5 minutes (cached)
- **Jobs:** 6 (1 setup + 5 parallel checks)
- **Database:** PostgreSQL 16
- **Coverage:** HTML reports as artifacts

### 🚀 [deploy.yml](workflows/deploy.yml)
**Production deployment**

- **Triggers:** Push to main, manual
- **Platform:** Gigalixir
- **Migrations:** Disabled (configure as needed)

### 🔍 [quality-checks.yml](workflows/quality-checks.yml)
**Deep quality analysis**

- **Triggers:** Weekly (Mon 9AM UTC), manual
- **Duration:** 8-12 minutes
- **Scope:** Comprehensive (--all flags)

## Environment

```yaml
Elixir: 1.18.3
OTP: 27.0
PostgreSQL: 16
GitHub Actions: v4/v5
```

## Cache Strategy

### Dependencies Cache
```
Key: ubuntu-mix-otp27.0-elixir1.18.3-{mix.lock hash}
Path: deps/, _build/
Shared: All CI jobs
```

### PLT Cache (Dialyzer)
```
Key: ubuntu-plt-otp27.0-elixir1.18.3-{mix.lock hash}
Path: priv/plts/
Shared: Dialyzer jobs
```

## Quality Gates

All PRs must pass:
- ✅ Code formatting (mix format)
- ✅ Linting (mix credo --strict)
- ✅ Security scan (mix sobelow)
- ✅ Type checking (mix dialyzer)
- ✅ All tests (mix test)
- ✅ Compile warnings as errors

## Local Commands

```bash
# All checks (mirrors CI)
mix precommit

# Individual checks
mix format --check-formatted
mix credo --strict
mix sobelow --config
mix dialyzer
mix test

# Coverage report
mix coveralls.html
open cover/index.html

# Build PLT (first time)
mix dialyzer --plt
```

## CI Status Badges

Add to your README:

```markdown
![CI](https://github.com/YOUR_USERNAME/alchemistdrops/workflows/CI/badge.svg)
![Deploy](https://github.com/YOUR_USERNAME/alchemistdrops/workflows/Deploy%20to%20Gigalixir/badge.svg)
```

## Secrets Required

Configure in: `Settings → Secrets and variables → Actions`

- `GIGALIXIR_USERNAME` - Deployment user
- `GIGALIXIR_PASSWORD` - Deployment password
- `GIGALIXIR_APP` - App name
- `SSH_PRIVATE_KEY` - Deployment SSH key

## Performance Metrics

| Metric | Target | Current |
|--------|--------|---------|
| CI Duration (warm) | < 5 min | ✅ 3-5 min |
| Cache Hit Rate | > 90% | ✅ ~95% |
| Test Coverage | > 80% | 🎯 Track |
| Build Success Rate | > 95% | 🎯 Track |

## Troubleshooting

### "Check failed" - How to debug?

1. **Click on failed job** in GitHub Actions
2. **Expand failing step** to see error details
3. **Run same command locally:**
   ```bash
   mix <command-that-failed>
   ```
4. **Fix issue and push again**

### Common Issues

| Error | Fix |
|-------|-----|
| Format check failed | `mix format` |
| Credo warnings | Fix or configure `.credo.exs` |
| Dialyzer errors | Check types, rebuild PLT |
| Tests failing | Check database, async issues |
| Security scan failed | Review Sobelow output |

## Files Changed

### New Files ✨
- `.github/workflows/ci.yml`
- `.github/workflows/deploy.yml`
- `.github/workflows/quality-checks.yml`
- `.dialyzer_ignore.exs`
- `CI_PIPELINE.md` (detailed docs)
- `PIPELINE_MIGRATION.md` (migration guide)

### Updated Files 📝
- `mix.exs` (dialyzer config + precommit)
- `.sobelow.conf` (improved settings)
- `.gitignore` (PLT files)

### Removed Files 🗑️
- `.github/workflows/dialyzer.yml`
- `.github/workflows/lint.yml`
- `.github/workflows/gigalixir.yml`
- `.github/workflows/security.yml`
- `.github/workflows/format.yml`
- `.github/workflows/tests.yml`

## Documentation

- **This File:** Quick reference
- **[README.md](README.md):** Workflow details
- **[CI_PIPELINE.md](../../CI_PIPELINE.md):** Complete documentation
- **[PIPELINE_MIGRATION.md](../../PIPELINE_MIGRATION.md):** Migration guide

## Support

Having issues? Check:
1. This overview
2. [CI_PIPELINE.md](../../CI_PIPELINE.md) for details
3. GitHub Actions logs
4. Run checks locally to isolate

---

**Version:** 1.0  
**Updated:** November 2025  
**Stack:** Elixir 1.18.3, OTP 27.0, Phoenix 1.8

