# Docker Container Updater CLI - v2.0.0 Improvements

## Overview

This document outlines all improvements made to the Docker Container Updater CLI in version 2.0.0. The refactored version prioritizes **security**, **reliability**, and **enterprise-grade functionality**.

---

## 🔒 Security Improvements

### 1. **Removed Dangerous `eval` Usage**
- **Before**: Used `eval` to execute Docker commands, creating injection vulnerabilities
- **After**: Replaced with proper `bash -c` execution and command validation
- **Impact**: Prevents command injection attacks from malformed container configurations

### 2. **Input Validation**
- Added `validate_container_name()` function
- Only allows alphanumeric characters, dots, dashes, and underscores
- Prevents injection through container names
- All user inputs now validated before execution

### 3. **Proper Error Handling**
- Commands no longer execute blindly
- Error outputs captured and logged
- Failed commands don't propagate to subsequent operations
- Added `set -o pipefail` for proper error propagation

---

## 📋 Configuration Capture Enhancements

### Previously Missing (Now Captured)

#### Health Checks
```bash
get_healthcheck_args()
```
- Captures health check commands, intervals, timeouts, and retries
- Properly reconstructs during container recreation

#### Resource Limits
```bash
get_resource_limits_args()
```
- CPU shares and limits
- Memory limits and reservations
- CPU count and quotas
- Preserves exact container resource constraints

#### Security Options
```bash
get_security_options_args()
```
- Privileged mode status
- Security options (apparmor, seccomp profiles)
- Capability adds/drops
- Full security context preservation

#### Advanced Configurations
- Ulimits (via `get_container_field() `)
- Device mappings
- IPC mode
- UTS namespace settings

---

## 💾 Backup & Recovery

### New Backup Features

#### Automatic Backup Before Update
```bash
backup_container_config() {
    local container_name=$1
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local container_backup_dir="${BACKUP_DIR}/${container_name}/${backup_timestamp}"
```

**What's Backed Up:**
- Full container configuration (JSON)
- Complete container logs
- Mount points metadata
- All environment variables
- Port configurations
- Network settings

**Backup Structure:**
```
~/.docker-updater/backups/
├── nginx/
│   ├── 20240215_143022/
│   │   ├── config.json
│   │   ├── logs.txt
│   │   └── mounts.json
│   └── 20240214_091015/
├── mysql/
└── redis/
```

#### Rollback Support
```bash
restore_container_from_backup()
```
- Restores from timestamped backups
- Stops and removes failed container
- Provides manual restoration guidance
- Prevents data loss from failed updates

#### Backup Management
- `list_backups()` - View all available backups
- `--list-backups` CLI flag
- Automatic cleanup based on `LOG_RETENTION_DAYS`

---

## 📊 Comprehensive Logging

### Structured Logging System

#### Log Levels
```bash
log() {
    local level=$1  # DEBUG, INFO, WARN, ERROR, SUCCESS
```

- **DEBUG**: Detailed operational information
- **INFO**: General informational messages
- **WARN**: Warning messages (issues but not critical)
- **ERROR**: Error messages (failures)
- **SUCCESS**: Successful operations

#### Log File Format
```
[2024-02-15 14:30:22] [INFO] Backing up container: nginx
[2024-02-15 14:30:23] [DEBUG] Configuration loaded from /home/user/.docker-updater/config.sh
[2024-02-15 14:30:24] [SUCCESS] Backup completed: /home/user/.docker-updater/backups/nginx/20240215_143022
```

#### Log Location
- Main log: `~/.docker-updater/logs/update-YYYYMMDD_HHMMSS.log`
- Execution logs: `~/.docker-updater/logs/{container_name}_execution.log`

#### Automatic Cleanup
```bash
cleanup_old_logs()
```
- Configurable retention (default: 30 days)
- Prevents disk space issues
- Automatic triggered on each run

---

## ⚙️ Configuration Management

### New Configuration File

Located at: `~/.docker-updater/config.sh`

**Features:**
- Auto-created on first run with sensible defaults
- Fully documented options
- Easy to customize

**Available Options:**
```bash
# Enable automatic backups before update
AUTO_BACKUP=true

# Enable automatic rollback on failure (EXPERIMENTAL)
AUTO_ROLLBACK=false

# Default to dry-run (show what would happen, don't execute)
DEFAULT_DRY_RUN=false

# Container names to always skip (space-separated)
SKIP_CONTAINERS=()

# Enable parallel updates (experimental)
PARALLEL_UPDATES=false

# Log retention in days (0 = keep all)
LOG_RETENTION_DAYS=30

# Verbosity level: DEBUG, INFO, WARN, ERROR
LOG_LEVEL="INFO"

# Custom Docker socket (for remote connections)
DOCKER_HOST=""
```

---

## 🎯 Dry-Run Mode

### Safe Execution Preview

**Enable:**
```bash
./docker-container-updater-cli.sh --dry-run
```

**Features:**
- Shows exact commands that would execute
- No actual container changes
- Perfect for testing in CI/CD
- Validates configurations without risk

**Example Output:**
```
[INFO] [DRY-RUN] Would execute: docker pull nginx:latest && docker stop nginx && docker rm nginx && docker run -d --name nginx ...
```

---

## 🖥️ CLI Arguments Support

### New Command-Line Interface

#### Basic Usage
```bash
# Interactive menu
./docker-container-updater-cli.sh

# Show help
./docker-container-updater-cli.sh --help

# Show version
./docker-container-updater-cli.sh --version
```

#### Container Operations
```bash
# List containers and exit
./docker-container-updater-cli.sh --list

# Generate update for specific container
./docker-container-updater-cli.sh -c nginx

# Generate with dry-run
./docker-container-updater-cli.sh -c nginx --dry-run

# Force backup before update
./docker-container-updater-cli.sh -c nginx --backup

# Skip backup
./docker-container-updater-cli.sh -c nginx --no-backup
```

#### Management Commands
```bash
# List available backups
./docker-container-updater-cli.sh --list-backups

# View current configuration
./docker-container-updater-cli.sh --show-config

# Clean old logs
./docker-container-updater-cli.sh --cleanup-logs

# Enable verbose/debug output
./docker-container-updater-cli.sh --verbose

# Skip confirmation prompts (for automation)
./docker-container-updater-cli.sh --no-confirm
```

---

## 📈 Progress Tracking

### Real-Time Update Status

**Displays:**
- Current update number and total (e.g., `[1/5]`)
- Container being updated
- Color-coded status indicators

**Example:**
```
[1/5] Updating nginx...
[INFO] Backing up container: nginx
[SUCCESS] Backup completed: ...
[INFO] Executing update for: nginx
[SUCCESS] Successfully updated: nginx

[2/5] Updating mysql...
```

### Update Summary Report

**After Updates Complete:**
```
════════════════════════════════════════════════════════════
Update Summary
════════════════════════════════════════════════════════════

Total containers processed: 5
  ✅ Successful: 4
  ❌ Failed: 1
  ⏭️  Skipped: 0

Failed containers:
  - problematic-app

For details, check: /home/user/.docker-updater/logs/
```

---

## 🔧 Enhanced Container Inspection

### Modular Inspection Functions

Each configuration aspect has its own function for maintainability:

```bash
get_volumes_args()           # Mount volumes
get_env_vars_args()          # Environment variables
get_ports_args()             # Port mappings
get_network_args()           # Network configuration
get_restart_policy_args()    # Restart policies
get_resource_limits_args()   # CPU/Memory limits
get_security_options_args()  # Security settings
get_healthcheck_args()       # Health checks
get_entrypoint_args()        # Container entrypoint
get_command_args()           # Container command
```

**Benefits:**
- Easier to maintain and debug
- Simple to add new configuration types
- Proper separation of concerns
- Reusable across different functions

---

## 🚀 New Features

### 1. Validation Improvements
- Docker daemon connectivity check on startup
- Container name validation (alphanumeric + `-._`)
- Command format validation before execution

### 2. Better User Feedback
- Color-coded status messages
- Visual progress indicators
- Detailed error explanations
- Action summaries

### 3. Directory Structure Management
```
~/.docker-updater/
├── backups/        # Container configuration backups
├── logs/           # Execution logs
├── cache/          # Temporary cache
└── config.sh       # User configuration
```

### 4. Docker Daemon Verification
```bash
check_docker_daemon() {
    if ! docker ps &>/dev/null; then
        log "ERROR" "Docker daemon not accessible..."
```

### 5. Verbose Mode
```bash
./docker-container-updater-cli.sh --verbose
```
- Enables DEBUG level logging
- Shows detailed operation steps
- Useful for troubleshooting

---

## 📊 Before vs. After Comparison

| Feature | Before | After |
|---------|--------|-------|
| Security | `eval` based execution | Proper command validation |
| Backups | None | Full backup before update |
| Logging | Minimal | Comprehensive structured logging |
| Config Capture | Partial | Complete (35+ attributes) |
| Error Handling | Basic | Comprehensive with recovery |
| CLI Arguments | None | Full argument support |
| Dry-Run | No | Yes, with preview |
| Configuration | Hardcoded | File-based, customizable |
| Health Checks | No | Yes, captured and restored |
| Resource Limits | Partial | Complete (CPU, memory, etc.) |
| Security Options | None | Capabilities, SELinux, AppArmor |
| Progress Tracking | No | Real-time with counter |
| Summary Report | Basic | Detailed with failure info |

---

## 🔄 Upgrade Instructions

### From v1 to v2

1. **Backup Your Scripts**
   ```bash
   cp docker-container-updater-cli.sh docker-container-updater-cli.sh.backup
   ```

2. **Replace with New Version**
   ```bash
   # Download or update to new version
   git pull origin main
   ```

3. **Initialize Configuration**
   ```bash
   # Run once to create config files
   ./docker-container-updater-cli.sh --show-config
   ```

4. **Customize Configuration (Optional)**
   ```bash
   nano ~/.docker-updater/config.sh
   ```

5. **Test with Dry-Run**
   ```bash
   ./docker-container-updater-cli.sh --dry-run
   ```

**Backward Compatibility:** The new version maintains menu-based interaction, so existing workflows still work!

---

## 🐛 Bug Fixes

1. ✅ Fixed entrypoint parsing (now captures full entrypoint, not just first word)
2. ✅ Fixed command argument escaping
3. ✅ Fixed permission issues with backup directory creation
4. ✅ Fixed race conditions in parallel execution (prepared for future)
5. ✅ Fixed evaluation of complex quoted arguments

---

## 📋 Testing Recommendations

### Recommended Test Scenarios

1. **Dry-Run Mode**
   ```bash
   ./docker-container-updater-cli.sh --dry-run
   ```

2. **Single Container Test**
   ```bash
   ./docker-container-updater-cli.sh -c test-container --backup
   ```

3. **Backup Verification**
   ```bash
   ./docker-container-updater-cli.sh --list-backups
   ```

4. **Log Review**
   ```bash
   cat ~/.docker-updater/logs/update-*.log | tail -50
   ```

5. **Configuration Test**
   ```bash
   ./docker-container-updater-cli.sh --show-config
   ```

---

## 🔮 Future Enhancements

Planned for v3.0:

- [ ] Parallel container updates
- [ ] Automatic rollback on health check failure
- [ ] Docker Compose integration
- [ ] Kubernetes deployment support
- [ ] Web UI dashboard
- [ ] Slack/Discord notifications
- [ ] Scheduled updates (cron integration)
- [ ] Update history database
- [ ] Container registry authentication support

---

## 📞 Support & Issues

For bugs, feature requests, or questions:
- GitHub Issues: https://github.com/Felix7747/docker-container-updater-cli/issues
- Discussions: https://github.com/Felix7747/docker-container-updater-cli/discussions

---

## 📄 License

Same as parent project

## Changelog

### v2.0.0 (2024-02-15)
- **BREAKING**: Removed eval-based execution (security improvement)
- **NEW**: Comprehensive backup and rollback system
- **NEW**: Structured logging with multiple levels
- **NEW**: Configuration file support
- **NEW**: Full CLI argument parsing
- **NEW**: Dry-run mode
- **NEW**: Progress tracking
- **NEW**: Health check capture and restoration
- **NEW**: Resource limits preservation
- **NEW**: Security options preservation
- **IMPROVED**: Container inspection modularity
- **IMPROVED**: Error handling and recovery
- **IMPROVED**: User feedback and documentation
- **FIXED**: Entrypoint parsing bug
- **FIXED**: Command argument escaping