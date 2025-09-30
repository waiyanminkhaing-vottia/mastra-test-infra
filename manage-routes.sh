#!/bin/bash

# Nginx Route Management Script
# Manages dynamic nginx routes for Next.js and normal applications

set -e

ROUTES_FILE="nginx-routes.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored message
print_msg() {
    local color=$1
    shift
    echo -e "${color}$@${NC}"
}

# Check if jq is installed
check_dependencies() {
    if ! command -v jq &> /dev/null; then
        print_msg "$RED" "❌ Error: jq is required but not installed"
        echo "Install it with: brew install jq (macOS) or apt-get install jq (Linux)"
        exit 1
    fi

    if ! command -v python3 &> /dev/null; then
        print_msg "$RED" "❌ Error: python3 is required but not installed"
        exit 1
    fi
}

# Initialize routes file if it doesn't exist
init_routes_file() {
    if [ ! -f "$ROUTES_FILE" ]; then
        echo '{"routes":[]}' > "$ROUTES_FILE"
        print_msg "$GREEN" "✅ Created $ROUTES_FILE"
    fi
}

# List all routes
list_routes() {
    init_routes_file

    print_msg "$BLUE" "📋 Current Routes:"
    echo

    python3 << 'EOF'
import json

with open('nginx-routes.json', 'r') as f:
    config = json.load(f)

routes = config.get('routes', [])

if not routes:
    print("⚠️  No routes configured")
else:
    for idx, route in enumerate(routes, 1):
        route_type = route.get('route_type', 'normal')
        print(f"{idx}. {route['name']}")
        print(f"   Type: {route_type}")
        print(f"   Path: {route['path']}")
        print(f"   Target: localhost:{route['target_port']}")
        if route_type == 'nextjs':
            print(f"   Pattern: localhost:{route['target_port']}{route['path']}")
        else:
            print(f"   Pattern: localhost:{route['target_port']} (prefix stripped)")
        print()
EOF
}

# Add a new route
add_route() {
    local name=$1
    local path=$2
    local port=$3
    local route_type=$4

    if [ -z "$name" ] || [ -z "$path" ] || [ -z "$port" ]; then
        print_msg "$RED" "❌ Error: Missing required parameters"
        echo "Usage: $0 add <route_name> <path> <port> [nextjs|normal]"
        echo "Example: $0 add dashboard /dashboard 3000 nextjs"
        echo "Example: $0 add api /api 8080 normal"
        exit 1
    fi

    # Validate port is a number
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        print_msg "$RED" "❌ Error: Port must be a number"
        exit 1
    fi

    # Validate path format
    if [[ ! "$path" =~ ^/ ]]; then
        print_msg "$RED" "❌ Error: Path must start with /"
        exit 1
    fi

    # Default to normal if not specified
    [ -z "$route_type" ] && route_type="normal"

    if [ "$route_type" != "nextjs" ] && [ "$route_type" != "normal" ]; then
        print_msg "$RED" "❌ Error: Route type must be 'nextjs' or 'normal'"
        exit 1
    fi

    init_routes_file

    python3 << EOF
import json

with open('$ROUTES_FILE', 'r') as f:
    config = json.load(f)

# Check if route already exists
for route in config['routes']:
    if route['name'] == '$name':
        print("❌ Error: Route '$name' already exists")
        exit(1)
    if route['path'] == '$path':
        print(f"❌ Error: Path '$path' is already used by route '{route['name']}'")
        exit(1)

# Add new route
new_route = {
    'name': '$name',
    'type': 'proxy',
    'route_type': '$route_type',
    'path': '$path',
    'target_port': $port
}

config['routes'].append(new_route)

with open('$ROUTES_FILE', 'w') as f:
    json.dump(config, f, indent=2)

print(f"✅ Added route '$name' successfully")
print(f"   Type: $route_type")
print(f"   Path: $path")
print(f"   Target: localhost:$port")
if '$route_type' == 'nextjs':
    print(f"   Pattern: localhost:$port$path (basePath preserved)")
else:
    print(f"   Pattern: localhost:$port (prefix stripped)")
EOF
}

# Edit an existing route
edit_route() {
    local name=$1
    local path=$2
    local port=$3
    local route_type=$4

    if [ -z "$name" ] || [ -z "$path" ] || [ -z "$port" ]; then
        print_msg "$RED" "❌ Error: Missing required parameters"
        echo "Usage: $0 edit <route_name> <new_path> <new_port> [nextjs|normal]"
        exit 1
    fi

    # Validate port is a number
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        print_msg "$RED" "❌ Error: Port must be a number"
        exit 1
    fi

    # Validate path format
    if [[ ! "$path" =~ ^/ ]]; then
        print_msg "$RED" "❌ Error: Path must start with /"
        exit 1
    fi

    # Default to normal if not specified
    [ -z "$route_type" ] && route_type="normal"

    if [ "$route_type" != "nextjs" ] && [ "$route_type" != "normal" ]; then
        print_msg "$RED" "❌ Error: Route type must be 'nextjs' or 'normal'"
        exit 1
    fi

    python3 << EOF
import json

with open('$ROUTES_FILE', 'r') as f:
    config = json.load(f)

found = False
for route in config['routes']:
    if route['name'] == '$name':
        found = True
        old_path = route['path']
        old_port = route['target_port']
        old_type = route.get('route_type', 'normal')

        route['path'] = '$path'
        route['target_port'] = $port
        route['route_type'] = '$route_type'

        print(f"✅ Updated route '$name'")
        print(f"   Type: {old_type} → $route_type")
        print(f"   Path: {old_path} → $path")
        print(f"   Port: {old_port} → $port")
        break

if not found:
    print(f"❌ Error: Route '$name' not found")
    exit(1)

with open('$ROUTES_FILE', 'w') as f:
    json.dump(config, f, indent=2)
EOF
}

# Delete a route
delete_route() {
    local name=$1

    if [ -z "$name" ]; then
        print_msg "$RED" "❌ Error: Route name required"
        echo "Usage: $0 delete <route_name>"
        exit 1
    fi

    python3 << EOF
import json

with open('$ROUTES_FILE', 'r') as f:
    config = json.load(f)

initial_count = len(config['routes'])
config['routes'] = [r for r in config['routes'] if r['name'] != '$name']

if len(config['routes']) == initial_count:
    print(f"❌ Error: Route '$name' not found")
    exit(1)

with open('$ROUTES_FILE', 'w') as f:
    json.dump(config, f, indent=2)

print(f"✅ Deleted route '$name'")
EOF
}

# Show usage
show_usage() {
    cat << EOF
Nginx Route Management Script

Usage: $0 <command> [options]

Commands:
  list                                    List all routes
  add <name> <path> <port> [type]        Add a new route
  edit <name> <path> <port> [type]       Edit an existing route
  delete <name>                           Delete a route

Route Types:
  nextjs    - Next.js app with basePath (preserves full path)
  normal    - Normal app (strips path prefix) [default]

Examples:
  # List all routes
  $0 list

  # Add Next.js app with basePath
  $0 add dashboard /dashboard 3000 nextjs

  # Add normal app (prefix stripped)
  $0 add api /api 8080 normal

  # Edit route
  $0 edit dashboard /dash 3001 nextjs

  # Delete route
  $0 delete api

Pattern Behavior:
  Next.js (nextjs): /dashboard → http://localhost:3000/dashboard
  Normal (normal):  /api → http://localhost:8080/ (prefix stripped)

EOF
}

# Main script
main() {
    check_dependencies

    if [ $# -eq 0 ]; then
        show_usage
        exit 1
    fi

    local command=$1
    shift

    case $command in
        list)
            list_routes
            ;;
        add)
            add_route "$@"
            ;;
        edit)
            edit_route "$@"
            ;;
        delete)
            delete_route "$@"
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            print_msg "$RED" "❌ Unknown command: $command"
            echo
            show_usage
            exit 1
            ;;
    esac
}

main "$@"