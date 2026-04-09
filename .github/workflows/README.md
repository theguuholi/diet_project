# GitHub Actions Workflows

This directory contains the CI/CD workflows for the Alchemistdrops project.

## Workflows Overview

### 🔄 CI Pipeline (`ci.yml`)

**Triggers:** Push and Pull Requests to `main`/`master` branches

The main continuous integration pipeline that ensures code quality and correctness. It runs in parallel after a shared setup job:

#### Jobs:
1. **Setup** - Installs and caches dependencies
2. **Format** - Validates code formatting with `mix format --check-formatted`
3. **Lint** - Runs Credo static code analysis with `--strict` mode
4. **Security** - Performs security scanning with Sobelow
5. **Dialyzer** - Runs static type analysis
6. **Test** - Executes test suite with PostgreSQL service and generates coverage reports

**Features:**
- ✅ Shared dependency caching across all jobs
- ✅ Parallel job execution for faster feedback
- ✅ Unique cache keys based on OTP, Elixir, and mix.lock
- ✅ Warnings treated as errors
- ✅ Coverage reports uploaded as artifacts
- ✅ Uses Elixir 1.18.3 and OTP 27.0

### 🚀 Deployment (`deploy.yml`)

**Triggers:** Push to `main` branch, manual dispatch

Deploys the application to Gigalixir production environment.

**Features:**
- ✅ Automatic deployment on main branch updates
- ✅ Manual trigger option via `workflow_dispatch`
- ✅ Uses latest GitHub Actions (v4/v5)

### 🔍 Quality Checks (`quality-checks.yml`)

**Triggers:** Manual dispatch, Weekly schedule (Mondays 9 AM UTC)

Comprehensive quality analysis workflow for periodic deep checks.

**Runs:**
- Format checking
- Compilation with warnings as errors
- Credo with `--strict --all` flags
- Sobelow verbose security scan
- Dialyzer type checking
- Unused dependency detection

**Features:**
- ✅ Comprehensive analysis in a single job
- ✅ Scheduled weekly runs
- ✅ Manual trigger capability
- ✅ Generates summary report in GitHub Actions UI

## Environment Configuration

All workflows use:
- **Elixir:** 1.18.3
- **OTP:** 27.0
- **Test Environment:** PostgreSQL 16
- **Action Versions:** Latest stable (v4/v5)

## Caching Strategy

### Dependency Cache
```yaml
Key: $OS-mix-otp$OTP_VERSION-elixir$ELIXIR_VERSION-$HASH(mix.lock)
Path: deps, _build
```

### PLT Cache (Dialyzer)
```yaml
Key: $OS-plt-otp$OTP_VERSION-elixir$ELIXIR_VERSION-$HASH(mix.lock)
Path: priv/plts
```

This ensures:
- Fast CI runs (cache hits on unchanged dependencies)
- Unique caches per Elixir/OTP combination
- Automatic cache invalidation on dependency changes

## Required Secrets

For deployment to work, configure these secrets in your GitHub repository:

- `GIGALIXIR_USERNAME` - Your Gigalixir account username
- `GIGALIXIR_PASSWORD` - Your Gigalixir account password
- `GIGALIXIR_APP` - Your Gigalixir app name
- `SSH_PRIVATE_KEY` - SSH key for Gigalixir deployment

## Local Development

To run the same checks locally:

```bash
# Run all precommit checks
mix precommit

# Individual checks
mix format --check-formatted
mix credo --strict
mix sobelow --config
mix dialyzer
mix test

# With coverage
mix coveralls.html
```

## Performance

The CI pipeline is optimized for speed:
- Setup job runs once and caches for all others
- Parallel execution of format, lint, security, dialyzer, and tests
- Typical run time: 3-5 minutes with warm cache
- Cold cache (first run): 8-12 minutes

## Troubleshooting

### Cache Issues
If you encounter strange compilation errors, try:
```bash
# In GitHub Actions UI
Re-run jobs > Re-run all jobs (clears cache on retry)
```

### Failed Dialyzer
Dialyzer PLT cache may need rebuild. The workflow automatically handles this, but locally:
```bash
mix dialyzer --plt
```

### Failed Tests
Tests require PostgreSQL. Ensure database service is running correctly in the workflow.

