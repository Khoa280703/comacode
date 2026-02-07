#!/bin/bash
# Shell script sample file - Advanced deployment script with best practices

set -euo pipefail
IFS=$'\n\t'

# ===== Configuration =====
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default configuration
PROJECT_DIR="${PROJECT_DIR:-/app}"
LOG_DIR="${LOG_DIR:-/var/log/deploy}"
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME%.*}_${TIMESTAMP}.log"
BACKUP_DIR="${BACKUP_DIR:-/backups}"
MAX_BACKUPS="${MAX_BACKUPS:-5}"
DEPLOY_ENV="${DEPLOY_ENV:-production}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

# ===== Utility Functions =====

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    case "$level" in
        INFO)  echo -e "${BLUE}[INFO]${NC} ${timestamp} - ${message}" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} ${timestamp} - ${message}" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} ${timestamp} - ${message}" >&2 ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} ${timestamp} - ${message}" ;;
        DEBUG)
            if [[ "$VERBOSE" == "true" ]]; then
                echo -e "[DEBUG] ${timestamp} - ${message}"
            fi
            ;;
    esac

    # Also log to file
    echo "[${level}] ${timestamp} - ${message}" >> "$LOG_FILE" 2>/dev/null || true
}

die() {
    log ERROR "$1"
    exit "${2:-1}"
}

confirm() {
    local message="$1"
    local default="${2:-n}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "Dry run - auto-confirming: $message"
        return 0
    fi

    local prompt
    if [[ "$default" == "y" ]]; then
        prompt="[Y/n]"
    else
        prompt="[y/N]"
    fi

    read -r -p "$message $prompt " response
    response="${response:-$default}"

    [[ "$response" =~ ^[Yy]$ ]]
}

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        die "Required command '$cmd' not found in PATH"
    fi
}

cleanup() {
    local exit_code=$?
    log INFO "Cleaning up..."

    # Remove temporary files
    if [[ -d "${TEMP_DIR:-}" ]]; then
        rm -rf "$TEMP_DIR"
    fi

    if [[ $exit_code -eq 0 ]]; then
        log SUCCESS "Script completed successfully"
    else
        log ERROR "Script failed with exit code: $exit_code"
    fi

    exit $exit_code
}

trap cleanup EXIT

# ===== Main Functions =====

show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] COMMAND

Commands:
    deploy      Deploy the application
    rollback    Rollback to previous version
    status      Check application status
    backup      Create backup only
    restore     Restore from backup

Options:
    -e, --env ENV       Set environment (default: production)
    -d, --dry-run       Show what would be done without doing it
    -v, --verbose       Enable verbose output
    -h, --help          Show this help message

Examples:
    $SCRIPT_NAME deploy
    $SCRIPT_NAME --env staging deploy
    $SCRIPT_NAME --dry-run backup
    $SCRIPT_NAME rollback

EOF
}

check_prerequisites() {
    log INFO "Checking prerequisites..."

    require_command git
    require_command node
    require_command npm
    require_command systemctl

    # Check if running as root for systemctl
    if [[ $EUID -ne 0 ]] && [[ "$DRY_RUN" != "true" ]]; then
        log WARN "Not running as root - some operations may fail"
    fi

    # Ensure directories exist
    mkdir -p "$LOG_DIR" "$BACKUP_DIR"

    log SUCCESS "Prerequisites check passed"
}

create_backup() {
    local backup_name="${1:-app_${TIMESTAMP}}"
    local backup_path="${BACKUP_DIR}/${backup_name}.tar.gz"

    log INFO "Creating backup: $backup_path"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "Dry run - would create backup at $backup_path"
        return 0
    fi

    if [[ ! -d "$PROJECT_DIR" ]]; then
        log WARN "Project directory does not exist: $PROJECT_DIR"
        return 1
    fi

    tar -czf "$backup_path" -C "$(dirname "$PROJECT_DIR")" "$(basename "$PROJECT_DIR")"

    log SUCCESS "Backup created: $backup_path"

    # Cleanup old backups
    cleanup_old_backups
}

cleanup_old_backups() {
    log INFO "Cleaning up old backups (keeping last $MAX_BACKUPS)..."

    local count
    count=$(find "$BACKUP_DIR" -name "*.tar.gz" -type f | wc -l)

    if [[ $count -gt $MAX_BACKUPS ]]; then
        local to_delete=$((count - MAX_BACKUPS))
        log DEBUG "Removing $to_delete old backup(s)"

        find "$BACKUP_DIR" -name "*.tar.gz" -type f -printf '%T+ %p\n' \
            | sort \
            | head -n "$to_delete" \
            | cut -d' ' -f2- \
            | xargs rm -f
    fi
}

restore_backup() {
    local backup_file="$1"

    if [[ ! -f "$backup_file" ]]; then
        # Try to find it in backup dir
        backup_file="${BACKUP_DIR}/${backup_file}"
        if [[ ! -f "$backup_file" ]]; then
            die "Backup file not found: $1"
        fi
    fi

    log INFO "Restoring from backup: $backup_file"

    if ! confirm "This will overwrite the current deployment. Continue?"; then
        log INFO "Restore cancelled by user"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "Dry run - would restore from $backup_file"
        return 0
    fi

    # Stop the service first
    stop_service

    # Remove current deployment
    rm -rf "$PROJECT_DIR"

    # Extract backup
    tar -xzf "$backup_file" -C "$(dirname "$PROJECT_DIR")"

    # Start the service
    start_service

    log SUCCESS "Restore completed"
}

pull_latest() {
    log INFO "Pulling latest changes from repository..."

    cd "$PROJECT_DIR" || die "Cannot change to project directory"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "Dry run - would pull latest changes"
        git fetch --dry-run origin main 2>&1 || true
        return 0
    fi

    # Stash any local changes
    if ! git diff --quiet; then
        log WARN "Local changes detected, stashing..."
        git stash push -m "Auto-stash before deploy ${TIMESTAMP}"
    fi

    # Pull latest
    git fetch origin main
    git reset --hard origin/main

    log SUCCESS "Repository updated"
}

install_dependencies() {
    log INFO "Installing dependencies..."

    cd "$PROJECT_DIR" || die "Cannot change to project directory"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "Dry run - would install npm dependencies"
        return 0
    fi

    # Check for package-lock.json to use ci instead of install
    if [[ -f "package-lock.json" ]]; then
        npm ci --production
    else
        npm install --production
    fi

    log SUCCESS "Dependencies installed"
}

build_application() {
    log INFO "Building application..."

    cd "$PROJECT_DIR" || die "Cannot change to project directory"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "Dry run - would build application"
        return 0
    fi

    # Run build if script exists
    if npm run | grep -q "build"; then
        NODE_ENV="$DEPLOY_ENV" npm run build
    else
        log WARN "No build script found, skipping..."
    fi

    log SUCCESS "Build completed"
}

run_migrations() {
    log INFO "Running database migrations..."

    cd "$PROJECT_DIR" || die "Cannot change to project directory"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "Dry run - would run migrations"
        return 0
    fi

    if npm run | grep -q "migrate"; then
        npm run migrate
        log SUCCESS "Migrations completed"
    else
        log INFO "No migration script found, skipping..."
    fi
}

start_service() {
    local service_name="${SERVICE_NAME:-app}"
    log INFO "Starting service: $service_name"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "Dry run - would start service $service_name"
        return 0
    fi

    systemctl start "$service_name"

    # Wait for service to be ready
    local retries=10
    local wait_time=3

    for ((i=1; i<=retries; i++)); do
        if systemctl is-active --quiet "$service_name"; then
            log SUCCESS "Service $service_name started successfully"
            return 0
        fi
        log DEBUG "Waiting for service to start (attempt $i/$retries)..."
        sleep $wait_time
    done

    die "Service failed to start after $((retries * wait_time)) seconds"
}

stop_service() {
    local service_name="${SERVICE_NAME:-app}"
    log INFO "Stopping service: $service_name"

    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "Dry run - would stop service $service_name"
        return 0
    fi

    if systemctl is-active --quiet "$service_name"; then
        systemctl stop "$service_name"
        log SUCCESS "Service $service_name stopped"
    else
        log INFO "Service $service_name was not running"
    fi
}

check_status() {
    local service_name="${SERVICE_NAME:-app}"

    echo "===== Deployment Status ====="
    echo ""
    echo "Environment: $DEPLOY_ENV"
    echo "Project Dir: $PROJECT_DIR"
    echo ""

    if [[ -d "$PROJECT_DIR" ]]; then
        echo "Git Info:"
        cd "$PROJECT_DIR"
        git log -1 --format="  Commit: %h%n  Author: %an%n  Date: %ai%n  Message: %s" 2>/dev/null || echo "  Not a git repository"
        echo ""
    fi

    echo "Service Status:"
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        echo -e "  ${GREEN}●${NC} $service_name is running"
        systemctl status "$service_name" --no-pager -l 2>/dev/null | head -15
    else
        echo -e "  ${RED}●${NC} $service_name is not running"
    fi
    echo ""

    echo "Recent Backups:"
    find "$BACKUP_DIR" -name "*.tar.gz" -type f -printf '  %T+ %p\n' 2>/dev/null | sort -r | head -5 || echo "  No backups found"
}

deploy() {
    log INFO "Starting deployment to $DEPLOY_ENV environment"
    echo "========================================"

    check_prerequisites
    create_backup
    pull_latest
    install_dependencies
    build_application
    run_migrations

    log INFO "Restarting service..."
    stop_service
    start_service

    log SUCCESS "Deployment completed successfully!"
    echo "========================================"

    check_status
}

rollback() {
    log INFO "Starting rollback..."

    local latest_backup
    latest_backup=$(find "$BACKUP_DIR" -name "*.tar.gz" -type f -printf '%T+ %p\n' | sort -r | head -1 | cut -d' ' -f2-)

    if [[ -z "$latest_backup" ]]; then
        die "No backups found to rollback to"
    fi

    log INFO "Rolling back to: $latest_backup"
    restore_backup "$latest_backup"
}

# ===== Main Entry Point =====

main() {
    local command=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -e|--env)
                DEPLOY_ENV="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            deploy|rollback|status|backup|restore)
                command="$1"
                shift
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done

    if [[ -z "$command" ]]; then
        show_usage
        exit 1
    fi

    log INFO "Running command: $command (env: $DEPLOY_ENV, dry-run: $DRY_RUN)"

    case "$command" in
        deploy)   deploy ;;
        rollback) rollback ;;
        status)   check_status ;;
        backup)   create_backup ;;
        restore)  restore_backup "${2:-}" ;;
        *)        die "Unknown command: $command" ;;
    esac
}

main "$@"

# ===== Additional Utility Functions =====

# Associative arrays (bash 4+)
declare -A CONFIG=(
    [database_host]="localhost"
    [database_port]="5432"
    [database_name]="myapp"
    [redis_host]="localhost"
    [redis_port]="6379"
    [api_timeout]="30"
    [max_retries]="3"
)

declare -A ENVIRONMENTS=(
    [development]="dev.example.com"
    [staging]="staging.example.com"
    [production]="api.example.com"
)

# Indexed arrays
declare -a SERVERS=(
    "web-01.example.com"
    "web-02.example.com"
    "web-03.example.com"
    "db-01.example.com"
    "cache-01.example.com"
)

declare -a REQUIRED_PORTS=(80 443 8080 5432 6379)

# ===== String Manipulation =====

string_utils() {
    local str="Hello, World! Welcome to Bash."

    # Length
    echo "Length: ${#str}"

    # Substring
    echo "Substring (0-5): ${str:0:5}"
    echo "Substring (7-): ${str:7}"

    # Default values
    local undefined_var
    echo "Default: ${undefined_var:-default_value}"
    echo "Assign default: ${undefined_var:=assigned_value}"
    echo "Error if unset: ${undefined_var:?Variable is required}"
    echo "Alternate value: ${str:+has value}"

    # Pattern substitution
    echo "First replacement: ${str/o/0}"
    echo "All replacements: ${str//o/0}"
    echo "Prefix removal: ${str#Hello, }"
    echo "Suffix removal: ${str%Welcome*}"
    echo "Longest prefix removal: ${str##*!}"
    echo "Longest suffix removal: ${str%%!*}"

    # Case conversion (bash 4+)
    echo "Uppercase: ${str^^}"
    echo "Lowercase: ${str,,}"
    echo "Capitalize first: ${str^}"
}

# ===== Arithmetic Operations =====

math_operations() {
    local a=10
    local b=3

    # Arithmetic expansion
    echo "Addition: $((a + b))"
    echo "Subtraction: $((a - b))"
    echo "Multiplication: $((a * b))"
    echo "Division: $((a / b))"
    echo "Modulo: $((a % b))"
    echo "Exponent: $((a ** b))"

    # Increment/Decrement
    echo "Pre-increment: $((++a))"
    echo "Post-increment: $((a++))"

    # Compound assignment
    ((a += 5))
    ((a -= 2))
    ((a *= 3))

    # Bitwise operations
    echo "AND: $((a & b))"
    echo "OR: $((a | b))"
    echo "XOR: $((a ^ b))"
    echo "Left shift: $((a << 2))"
    echo "Right shift: $((a >> 1))"

    # Ternary operator
    local max=$(( a > b ? a : b ))
    echo "Max: $max"

    # Floating point with bc
    echo "Float division: $(echo "scale=2; $a / $b" | bc)"
    echo "Square root: $(echo "scale=4; sqrt($a)" | bc)"
}

# ===== Process Substitution =====

process_substitution_examples() {
    # Compare two commands
    diff <(ls /dir1 2>/dev/null) <(ls /dir2 2>/dev/null) || true

    # Feed command output as file
    while read -r line; do
        echo "Processing: $line"
    done < <(find . -name "*.sh" -type f 2>/dev/null | head -5)

    # Multiple inputs
    paste <(cut -d: -f1 /etc/passwd) <(cut -d: -f3 /etc/passwd) 2>/dev/null | head -3

    # Redirect to command
    tee >(gzip > output.gz) >(wc -l > linecount.txt) > /dev/null <<< "test data" 2>/dev/null || true
}

# ===== Here Documents =====

heredoc_examples() {
    # Basic heredoc
    cat <<EOF
This is a heredoc.
Variables are expanded: $USER
Commands work: $(date)
EOF

    # Heredoc without variable expansion
    cat <<'EOF'
This is a literal heredoc.
Variables are NOT expanded: $USER
Commands are NOT executed: $(date)
EOF

    # Heredoc with indentation (use tabs)
    cat <<-EOF
		This is indented with tabs.
		Tabs are stripped.
	EOF

    # Herestring
    while read -r word; do
        echo "Word: $word"
    done <<< "one two three"

    # Heredoc to command
    mysql --help 2>/dev/null <<EOF || true
SELECT * FROM users;
EOF

    # Assign heredoc to variable
    local sql_query
    sql_query=$(cat <<EOF
SELECT id, name, email
FROM users
WHERE active = true
ORDER BY created_at DESC
LIMIT 10;
EOF
)
    echo "$sql_query"
}

# ===== Advanced Control Structures =====

control_structures() {
    local value=5

    # Extended test with regex
    local email="user@example.com"
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo "Valid email"
    fi

    # Pattern matching
    local filename="document.pdf"
    case "$filename" in
        *.txt) echo "Text file" ;;
        *.pdf) echo "PDF file" ;;
        *.jpg|*.png|*.gif) echo "Image file" ;;
        *.sh|*.bash) echo "Shell script" ;;
        *) echo "Unknown file type" ;;
    esac

    # C-style for loop
    for ((i=0; i<10; i+=2)); do
        echo "Even: $i"
    done

    # Brace expansion in loop
    for server in server{1..5}.example.com; do
        echo "Checking $server"
    done

    # Until loop
    local counter=0
    until ((counter >= 5)); do
        echo "Counter: $counter"
        ((counter++))
    done

    # Select menu
    PS3="Select an option: "
    select opt in "Option 1" "Option 2" "Option 3" "Quit"; do
        case $REPLY in
            1) echo "You chose option 1" ;;
            2) echo "You chose option 2" ;;
            3) echo "You chose option 3" ;;
            4) break ;;
            *) echo "Invalid option" ;;
        esac
    done <<< "4"  # Auto-select quit for demo
}

# ===== Function Advanced Patterns =====

# Function with local variables and return
calculate_fibonacci() {
    local n="$1"
    local result

    if ((n <= 1)); then
        result=$n
    else
        local a b
        a=$(calculate_fibonacci $((n - 1)))
        b=$(calculate_fibonacci $((n - 2)))
        result=$((a + b))
    fi

    echo "$result"
}

# Function returning array via nameref (bash 4.3+)
get_server_list() {
    local -n result_array="$1"
    result_array=("server1" "server2" "server3")
}

# Function with default parameters
greet() {
    local name="${1:-World}"
    local greeting="${2:-Hello}"
    echo "$greeting, $name!"
}

# Variadic function
print_all() {
    local prefix="$1"
    shift
    for item in "$@"; do
        echo "$prefix: $item"
    done
}

# ===== Signal Handling and Traps =====

setup_signal_handlers() {
    # Cleanup on various signals
    trap 'echo "Received SIGINT"; exit 130' INT
    trap 'echo "Received SIGTERM"; exit 143' TERM
    trap 'echo "Received SIGHUP"; reload_config' HUP
    trap 'echo "Script error on line $LINENO"; exit 1' ERR
    trap 'echo "Script exiting"; cleanup' EXIT

    # Debug trap (runs before each command)
    trap 'echo "DEBUG: $BASH_COMMAND"' DEBUG

    # Ignore signals
    trap '' PIPE  # Ignore broken pipe
}

reload_config() {
    log INFO "Reloading configuration..."
    # Re-source config files
    [[ -f ~/.bashrc ]] && source ~/.bashrc
}

# ===== File Operations =====

file_operations() {
    local file="/tmp/test_file_$$"
    local dir="/tmp/test_dir_$$"

    # Create temp file
    : > "$file"

    # File tests
    [[ -e "$file" ]] && echo "File exists"
    [[ -f "$file" ]] && echo "Is regular file"
    [[ -d "$dir" ]] || mkdir -p "$dir"
    [[ -r "$file" ]] && echo "File is readable"
    [[ -w "$file" ]] && echo "File is writable"
    [[ -x "$file" ]] || chmod +x "$file"
    [[ -s "$file" ]] || echo "File is empty"
    [[ -L "$file" ]] || echo "Not a symlink"

    # File comparisons
    local file2="/tmp/test_file2_$$"
    : > "$file2"
    [[ "$file" -nt "$file2" ]] && echo "file is newer"
    [[ "$file" -ot "$file2" ]] && echo "file is older"
    [[ "$file" -ef "$file2" ]] || echo "Not same inode"

    # Secure temp file
    local tmpfile
    tmpfile=$(mktemp) || exit 1
    echo "Temp file: $tmpfile"

    # Cleanup
    rm -f "$file" "$file2" "$tmpfile"
    rmdir "$dir" 2>/dev/null
}

# ===== Parallel Execution =====

parallel_execution() {
    local pids=()
    local results=()

    # Start background jobs
    for i in {1..5}; do
        (
            sleep $((RANDOM % 3))
            echo "Job $i completed"
        ) &
        pids+=($!)
    done

    echo "Started ${#pids[@]} background jobs"

    # Wait for all jobs
    for pid in "${pids[@]}"; do
        if wait "$pid"; then
            results+=("$pid: success")
        else
            results+=("$pid: failed")
        fi
    done

    printf '%s\n' "${results[@]}"
}

# Job pool with max concurrent jobs
job_pool() {
    local max_jobs=4
    local jobs=()

    for task in {1..10}; do
        # Wait if at max capacity
        while ((${#jobs[@]} >= max_jobs)); do
            for i in "${!jobs[@]}"; do
                if ! kill -0 "${jobs[$i]}" 2>/dev/null; then
                    unset 'jobs[i]'
                fi
            done
            jobs=("${jobs[@]}")  # Re-index array
            sleep 0.1
        done

        # Start new job
        (
            echo "Starting task $task"
            sleep $((RANDOM % 5))
            echo "Completed task $task"
        ) &
        jobs+=($!)
    done

    # Wait for remaining jobs
    wait
    echo "All tasks completed"
}

# ===== Network Operations =====

network_utils() {
    local host="google.com"
    local port=443

    # Check if host is reachable
    if ping -c 1 -W 2 "$host" &>/dev/null; then
        echo "$host is reachable"
    fi

    # Check if port is open
    if timeout 2 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
        echo "Port $port is open on $host"
    fi

    # Get external IP
    local external_ip
    external_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "unknown")
    echo "External IP: $external_ip"

    # DNS lookup
    local dns_result
    dns_result=$(dig +short "$host" 2>/dev/null | head -1)
    echo "DNS: $host -> $dns_result"

    # HTTP request with curl
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" "https://$host" 2>/dev/null || echo "000")
    echo "HTTP status: $response"
}

# ===== Docker Operations =====

docker_utils() {
    # Check if docker is available
    if ! command -v docker &>/dev/null; then
        log WARN "Docker not installed"
        return 1
    fi

    # List running containers
    echo "Running containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true

    # Container health check
    check_container_health() {
        local container="$1"
        local status
        status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null)
        echo "Container $container health: ${status:-unknown}"
    }

    # Docker compose operations
    docker_compose_up() {
        local compose_file="${1:-docker-compose.yml}"
        if [[ -f "$compose_file" ]]; then
            docker-compose -f "$compose_file" up -d
        else
            log ERROR "Compose file not found: $compose_file"
            return 1
        fi
    }

    # Build and push image
    docker_build_push() {
        local image="$1"
        local tag="${2:-latest}"
        local dockerfile="${3:-Dockerfile}"

        docker build -t "${image}:${tag}" -f "$dockerfile" . || return 1
        docker push "${image}:${tag}" || return 1
    }
}

# ===== Kubernetes Operations =====

kubectl_utils() {
    # Check if kubectl is available
    if ! command -v kubectl &>/dev/null; then
        log WARN "kubectl not installed"
        return 1
    fi

    # Get current context
    local context
    context=$(kubectl config current-context 2>/dev/null || echo "none")
    echo "Current context: $context"

    # List pods with status
    list_pods() {
        local namespace="${1:---all-namespaces}"
        kubectl get pods "$namespace" -o wide 2>/dev/null || true
    }

    # Watch pod logs
    watch_pod_logs() {
        local pod="$1"
        local container="${2:-}"
        local namespace="${3:-default}"

        local cmd="kubectl logs -f -n $namespace $pod"
        [[ -n "$container" ]] && cmd+=" -c $container"
        eval "$cmd" 2>/dev/null || true
    }

    # Rollout status
    check_rollout() {
        local deployment="$1"
        local namespace="${2:-default}"
        kubectl rollout status deployment/"$deployment" -n "$namespace" --timeout=300s
    }

    # Scale deployment
    scale_deployment() {
        local deployment="$1"
        local replicas="$2"
        local namespace="${3:-default}"
        kubectl scale deployment/"$deployment" --replicas="$replicas" -n "$namespace"
    }

    # Port forward
    port_forward() {
        local pod="$1"
        local ports="$2"  # e.g., "8080:80"
        local namespace="${3:-default}"
        kubectl port-forward -n "$namespace" "$pod" "$ports" &
        echo "Port forwarding PID: $!"
    }
}

# ===== Git Operations =====

git_utils() {
    # Check if in git repo
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        log ERROR "Not in a git repository"
        return 1
    fi

    # Get current branch
    local branch
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD)
    echo "Current branch: $branch"

    # Get last commit info
    git log -1 --format="Last commit: %h - %s (%an, %ar)"

    # Check for uncommitted changes
    if ! git diff --quiet; then
        echo "Uncommitted changes detected"
    fi

    # List recent branches
    echo "Recent branches:"
    git for-each-ref --sort=-committerdate --count=5 \
        --format='%(refname:short) (%(committerdate:relative))' refs/heads/

    # Git stash operations
    git_stash_save() {
        local message="${1:-WIP}"
        git stash push -m "$message"
    }

    git_stash_apply() {
        local index="${1:-0}"
        git stash apply "stash@{$index}"
    }

    # Interactive rebase helper
    git_squash_commits() {
        local count="${1:-2}"
        git rebase -i "HEAD~$count"
    }

    # Create release tag
    git_create_release() {
        local version="$1"
        local message="${2:-Release $version}"
        git tag -a "v$version" -m "$message"
        git push origin "v$version"
    }
}

# ===== Logging and Monitoring =====

log_parser() {
    local log_file="$1"

    # Count log levels
    echo "Log level distribution:"
    grep -oE '\[(INFO|WARN|ERROR|DEBUG)\]' "$log_file" 2>/dev/null \
        | sort | uniq -c | sort -rn || echo "No logs found"

    # Find errors in last hour
    echo "Recent errors:"
    local one_hour_ago
    one_hour_ago=$(date -d '1 hour ago' '+%Y-%m-%d %H:%M' 2>/dev/null || date -v-1H '+%Y-%m-%d %H:%M')
    awk -v since="$one_hour_ago" '$0 >= since && /ERROR/' "$log_file" 2>/dev/null | tail -10

    # Extract unique error messages
    echo "Unique error patterns:"
    grep -oP 'ERROR.*' "$log_file" 2>/dev/null \
        | sed 's/[0-9]\+/N/g' \
        | sort | uniq -c | sort -rn | head -5
}

# System monitoring
monitor_system() {
    echo "=== System Monitor ==="

    # CPU usage
    echo "CPU Usage:"
    top -bn1 | grep "Cpu(s)" | awk '{print "  User: "$2"%, System: "$4"%, Idle: "$8"%"}' 2>/dev/null || true

    # Memory usage
    echo "Memory Usage:"
    free -h 2>/dev/null | awk '/^Mem:/ {print "  Total: "$2", Used: "$3", Free: "$4}' || true

    # Disk usage
    echo "Disk Usage:"
    df -h / 2>/dev/null | awk 'NR==2 {print "  Total: "$2", Used: "$3" ("$5"), Free: "$4}' || true

    # Load average
    echo "Load Average:"
    uptime | awk -F'load average:' '{print "  "$2}'

    # Top processes
    echo "Top 5 CPU Processes:"
    ps aux --sort=-%cpu 2>/dev/null | head -6 | tail -5 | awk '{print "  "$11" ("$3"% CPU)"}' || true

    # Network connections
    echo "Network Connections:"
    ss -tuln 2>/dev/null | grep LISTEN | wc -l | xargs -I{} echo "  {} listening ports" || true
}

# ===== Security Functions =====

security_checks() {
    echo "=== Security Audit ==="

    # Check for world-writable files
    echo "World-writable files in /etc:"
    find /etc -perm -002 -type f 2>/dev/null | head -5 || echo "  None found"

    # Check SUID files
    echo "SUID files:"
    find /usr -perm -4000 -type f 2>/dev/null | wc -l | xargs -I{} echo "  {} SUID files found"

    # Check failed login attempts
    echo "Failed login attempts (last 10):"
    grep "Failed password" /var/log/auth.log 2>/dev/null | tail -5 || echo "  No auth log access"

    # Check open ports
    echo "Listening ports:"
    ss -tuln 2>/dev/null | grep LISTEN | awk '{print "  "$5}' | head -10 || true

    # Check for updates
    echo "System updates:"
    if command -v apt &>/dev/null; then
        apt list --upgradable 2>/dev/null | wc -l | xargs -I{} echo "  {} packages can be updated"
    fi
}

# Generate random password
generate_password() {
    local length="${1:-16}"
    local charset="${2:-A-Za-z0-9!@#$%^&*}"

    tr -dc "$charset" < /dev/urandom | head -c "$length"
    echo
}

# Hash file
hash_file() {
    local file="$1"
    local algorithm="${2:-sha256}"

    case "$algorithm" in
        md5)    md5sum "$file" | awk '{print $1}' ;;
        sha1)   sha1sum "$file" | awk '{print $1}' ;;
        sha256) sha256sum "$file" | awk '{print $1}' ;;
        sha512) sha512sum "$file" | awk '{print $1}' ;;
        *) echo "Unknown algorithm: $algorithm" >&2; return 1 ;;
    esac
}

# ===== CI/CD Integration =====

cicd_utils() {
    # Detect CI environment
    detect_ci() {
        if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
            echo "github"
        elif [[ -n "${GITLAB_CI:-}" ]]; then
            echo "gitlab"
        elif [[ -n "${JENKINS_URL:-}" ]]; then
            echo "jenkins"
        elif [[ -n "${CIRCLECI:-}" ]]; then
            echo "circleci"
        elif [[ -n "${TRAVIS:-}" ]]; then
            echo "travis"
        else
            echo "local"
        fi
    }

    local ci_platform
    ci_platform=$(detect_ci)
    echo "CI Platform: $ci_platform"

    # Set output variable (GitHub Actions style)
    set_output() {
        local name="$1"
        local value="$2"

        case "$ci_platform" in
            github)
                echo "$name=$value" >> "${GITHUB_OUTPUT:-/dev/null}"
                ;;
            gitlab)
                echo "export $name=\"$value\"" >> "${CI_ENV_FILE:-/dev/null}"
                ;;
            *)
                export "$name=$value"
                ;;
        esac
    }

    # Notify build status
    notify_status() {
        local status="$1"
        local message="$2"
        local webhook_url="${SLACK_WEBHOOK:-}"

        if [[ -n "$webhook_url" ]]; then
            local color
            case "$status" in
                success) color="good" ;;
                failure) color="danger" ;;
                *) color="warning" ;;
            esac

            curl -s -X POST -H 'Content-type: application/json' \
                --data "{\"attachments\":[{\"color\":\"$color\",\"text\":\"$message\"}]}" \
                "$webhook_url" >/dev/null || true
        fi
    }
}

# ===== Progress Bar =====

show_progress() {
    local current="$1"
    local total="$2"
    local width="${3:-50}"

    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf "\r["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' ' '
    printf "] %3d%%" "$percentage"

    if ((current == total)); then
        echo
    fi
}

# Demo progress bar
demo_progress() {
    local total=100
    for ((i=0; i<=total; i+=5)); do
        show_progress "$i" "$total"
        sleep 0.1
    done
}

# ===== Menu System =====

show_menu() {
    local title="$1"
    shift
    local options=("$@")

    clear
    echo "╔════════════════════════════════════════╗"
    printf "║ %-38s ║\n" "$title"
    echo "╠════════════════════════════════════════╣"

    for i in "${!options[@]}"; do
        printf "║  %d. %-35s ║\n" "$((i + 1))" "${options[$i]}"
    done

    echo "║  0. Exit                               ║"
    echo "╚════════════════════════════════════════╝"
    echo
    read -r -p "Enter choice: " choice
    echo "$choice"
}

# ===== Configuration Parser =====

parse_ini_file() {
    local file="$1"
    local section=""

    while IFS='=' read -r key value; do
        # Skip empty lines and comments
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue

        # Check for section header
        if [[ "$key" =~ ^\[.*\]$ ]]; then
            section="${key//[\[\]]/}"
            continue
        fi

        # Trim whitespace
        key="${key// /}"
        value="${value## }"
        value="${value%% }"

        # Export as variable
        if [[ -n "$section" ]]; then
            export "${section}_${key}=$value"
        else
            export "$key=$value"
        fi
    done < "$file"
}

parse_json_value() {
    local json="$1"
    local key="$2"

    echo "$json" | grep -oP "\"$key\"\s*:\s*\"?\K[^\",$}]+" | head -1
}

# ===== End of Extended Functions =====

