#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display containers with index
display_containers() {
    echo -e "${CYAN}=== Running Containers ===${NC}"
    echo -e "Index | Container Name | Image | Ports | Status"
    echo -e "------|----------------|-------|-------|--------"
    
    IFS=$'\n'
    local index=1
    for container in $(docker ps --format "{{.Names}}|{{.Image}}|{{.Ports}}|{{.Status}}"); do
        IFS='|' read -r name image ports status <<< "$container"
        printf "%-5s | %-14s | %-20s | %-15s | %s\n" "[$index]" "$name" "$(echo $image | cut -c1-20)" "$(echo $ports | cut -c1-15)" "$(echo $status | cut -c1-15)"
        CONTAINERS[$index]="$name"
        IMAGES[$index]="$image"
        index=$((index + 1))
    done
    unset IFS
    
    TOTAL_CONTAINERS=$((index - 1))
}

# Function to properly format command array for docker run
format_command() {
    local container_name=$1
    local cmd=$(docker inspect $container_name --format '{{json .Config.Cmd}}')
    
    if [ "$cmd" = "null" ] || [ -z "$cmd" ]; then
        echo ""
        return
    fi
    
    # Remove brackets and quotes, then format properly
    cmd=$(echo "$cmd" | sed 's/[][]//g' | sed 's/"//g' | sed 's/,/ /g')
    echo "$cmd"
}

# Function to generate update command for a container
generate_update_command() {
    local container_name=$1
    local container_id=$(docker inspect $container_name --format '{{.Id}}' 2>/dev/null)
    
    if [ -z "$container_id" ]; then
        echo -e "${RED}Container '$container_name' not found${NC}"
        return 1
    fi
    
    # Get container info
    local image=$(docker inspect $container_name --format '{{.Config.Image}}')
    local image_name=$(echo $image | cut -d: -f1)
    local image_tag=$(echo $image | cut -d: -f2)
    
    echo -e "\n${YELLOW}=== Container: $container_name ===${NC}"
    echo "Image: $image"
    
    # Get mounts/volumes
    local volumes=$(docker inspect $container_name --format '{{range .Mounts}}-v {{.Source}}:{{.Destination}} {{end}}')
    
    # Get environment variables
    local env_vars=$(docker inspect $container_name --format '{{range .Config.Env}}-e {{.}} {{end}}')
    
    # Get port mappings
    local ports=$(docker inspect $container_name --format '{{range $p, $conf := .NetworkSettings.Ports}}-p {{(index $conf 0).HostPort}}:{{$p}} {{end}}')
    
    # Get network
    local network=$(docker inspect $container_name --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}')
    local network_arg=""
    if [ "$network" != "bridge" ] && [ ! -z "$network" ]; then
        network_arg="--network $network"
    fi
    
    # Get restart policy
    local restart_policy=$(docker inspect $container_name --format '{{.HostConfig.RestartPolicy.Name}}')
    local restart_arg=""
    if [ "$restart_policy" != "no" ]; then
        restart_arg="--restart $restart_policy"
    fi
    
    # Get other options
    local options=""
    
    # Check for privileged mode
    if [ "$(docker inspect $container_name --format '{{.HostConfig.Privileged}}')" = "true" ]; then
        options="$options --privileged"
    fi
    
    # Get entrypoint if customized
    local entrypoint=$(docker inspect $container_name --format '{{json .Config.Entrypoint}}')
    if [ "$entrypoint" != "null" ]; then
        # Format entrypoint properly
        local formatted_entrypoint=$(echo "$entrypoint" | sed 's/[][]//g' | sed 's/"//g' | sed 's/,/ /g')
        if [ ! -z "$formatted_entrypoint" ]; then
            # Take only the first part as entrypoint (Docker expects executable)
            local first_entrypoint=$(echo "$formatted_entrypoint" | awk '{print $1}')
            options="$options --entrypoint $first_entrypoint"
        fi
    fi
    
    # Get command properly formatted
    local cmd=$(format_command "$container_name")
    
    # Build the docker run command
    local run_command="docker run -d --name $container_name"
    
    [ ! -z "$network_arg" ] && run_command="$run_command $network_arg"
    [ ! -z "$restart_arg" ] && run_command="$run_command $restart_arg"
    [ ! -z "$volumes" ] && run_command="$run_command $volumes"
    [ ! -z "$env_vars" ] && run_command="$run_command $env_vars"
    [ ! -z "$ports" ] && run_command="$run_command $ports"
    [ ! -z "$options" ] && run_command="$run_command $options"
    
    run_command="$run_command $image"
    [ ! -z "$cmd" ] && run_command="$run_command $cmd"
    
    # Generate the update command
    echo -e "${GREEN}Update Command:${NC}"
    echo "docker pull $image && \\"
    echo "docker stop $container_name && \\"
    echo "docker rm $container_name && \\"
    echo "$run_command"
    
    # Store the command for batch execution
    UPDATE_COMMANDS["$container_name"]="docker pull $image && docker stop $container_name && docker rm $container_name && $run_command"
    
    echo -e "\n${BLUE}One-liner:${NC}"
    echo "${UPDATE_COMMANDS[$container_name]}"
}

# Function to execute update commands
execute_updates() {
    local selected_containers=("$@")
    
    if [ ${#selected_containers[@]} -eq 0 ]; then
        echo -e "${RED}No containers selected for update${NC}"
        return
    fi
    
    echo -e "\n${YELLOW}=== Starting Updates ===${NC}"
    echo "The following containers will be updated:"
    printf '%s\n' "${selected_containers[@]}"
    
    read -p "Continue with updates? (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "Update cancelled."
        return
    fi
    
    for container in "${selected_containers[@]}"; do
        echo -e "\n${CYAN}Updating $container...${NC}"
        
        # Test command format before executing
        if [[ -z "${UPDATE_COMMANDS[$container]}" ]]; then
            echo -e "${RED}No update command generated for $container${NC}"
            continue
        fi
        
        # Display command
        echo "Command: ${UPDATE_COMMANDS[$container]}"
        
        read -p "Execute this update? (y/N/skip): " exec_confirm
        case $exec_confirm in
            [Yy])
                echo "Executing..."
                if eval "${UPDATE_COMMANDS[$container]}"; then
                    echo -e "${GREEN}✅ $container updated successfully${NC}"
                else
                    echo -e "${RED}❌ Failed to update $container${NC}"
                    echo "Troubleshooting tips:"
                    echo "1. Check if ports are already in use"
                    echo "2. Verify volume paths exist"
                    echo "3. Check Docker logs: docker logs $container"
                    read -p "Continue with remaining containers? (y/N): " continue_confirm
                    if [[ ! $continue_confirm =~ ^[Yy]$ ]]; then
                        echo "Stopping update process."
                        return
                    fi
                fi
                ;;
            [Ss]*)
                echo "Skipping $container"
                ;;
            *)
                echo "Skipping $container"
                ;;
        esac
    done
    
    echo -e "\n${GREEN}=== Update Process Complete ===${NC}"
    echo "Updated containers summary:"
    docker ps --filter "name=$(echo ${selected_containers[@]} | tr ' ' '|')" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
}

# Main execution
echo -e "${CYAN}=== Docker Container Update Helper ===${NC}"
echo ""

# Initialize arrays
declare -A CONTAINERS
declare -A IMAGES
declare -A UPDATE_COMMANDS

# Display running containers
display_containers

if [ $TOTAL_CONTAINERS -eq 0 ]; then
    echo -e "${RED}No running containers found${NC}"
    exit 0
fi

echo ""
echo -e "${CYAN}=== Update Options ===${NC}"
echo "1) Generate update commands for specific containers (by index)"
echo "2) Generate update commands for ALL containers"
echo "3) Generate update commands for containers using 'latest' tag"
echo "4) Generate AND execute updates for specific containers"
echo "5) Generate AND execute updates for ALL containers"
echo "6) Exit"
read -p "Enter choice [1-6]: " choice

case $choice in
    1)
        echo -e "\n${YELLOW}Enter container indices (space-separated, e.g., 1 3 5):${NC}"
        read -p "Indices: " indices
        
        echo ""
        for idx in $indices; do
            if [[ $idx =~ ^[0-9]+$ ]] && [ $idx -ge 1 ] && [ $idx -le $TOTAL_CONTAINERS ]; then
                container_name="${CONTAINERS[$idx]}"
                generate_update_command "$container_name"
            else
                echo -e "${RED}Invalid index: $idx${NC}"
            fi
        done
        ;;
    2)
        echo -e "\n${YELLOW}Generating update commands for all running containers...${NC}"
        for idx in $(seq 1 $TOTAL_CONTAINERS); do
            container_name="${CONTAINERS[$idx]}"
            generate_update_command "$container_name"
        done
        ;;
    3)
        echo -e "\n${YELLOW}Generating update commands for containers using 'latest' tag...${NC}"
        found_latest=0
        for idx in $(seq 1 $TOTAL_CONTAINERS); do
            container_name="${CONTAINERS[$idx]}"
            image="${IMAGES[$idx]}"
            if [[ "$image" == *":latest" ]] || [[ "$image" == *":main" ]]; then
                generate_update_command "$container_name"
                found_latest=1
            fi
        done
        if [ $found_latest -eq 0 ]; then
            echo "No containers using 'latest' or 'main' tag found."
        fi
        ;;
    4)
        echo -e "\n${YELLOW}Enter container indices to update (space-separated, e.g., 1 3 5):${NC}"
        read -p "Indices: " indices
        
        selected_containers=()
        for idx in $indices; do
            if [[ $idx =~ ^[0-9]+$ ]] && [ $idx -ge 1 ] && [ $idx -le $TOTAL_CONTAINERS ]; then
                container_name="${CONTAINERS[$idx]}"
                selected_containers+=("$container_name")
                # Generate command first (stores in UPDATE_COMMANDS array)
                generate_update_command "$container_name" > /dev/null 2>&1
            else
                echo -e "${RED}Invalid index: $idx${NC}"
            fi
        done
        
        execute_updates "${selected_containers[@]}"
        ;;
    5)
        echo -e "\n${YELLOW}Updating ALL running containers...${NC}"
        selected_containers=()
        for idx in $(seq 1 $TOTAL_CONTAINERS); do
            container_name="${CONTAINERS[$idx]}"
            selected_containers+=("$container_name")
            # Generate command first (stores in UPDATE_COMMANDS array)
            generate_update_command "$container_name" > /dev/null 2>&1
        done
        
        execute_updates "${selected_containers[@]}"
        ;;
    6)
        echo "Exiting..."
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}=== Important Notes ===${NC}"
echo "1. Always test update commands in a development environment first"
echo "2. For production containers, consider using Docker Compose for easier updates"
echo "3. Database containers may require special procedures (backup, stop, etc.)"
echo "4. Some container configurations (healthchecks, resource limits) may not be captured"
echo "5. If you encounter issues, check Docker logs: docker logs <container-name>"
