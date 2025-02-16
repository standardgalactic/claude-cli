#!/bin/bash
set -e

# Debug mode
DEBUG=false
[ "$1" = "--debug" ] && DEBUG=true

# Configuration
INSTALL_DIR="$HOME/.claude-cli"
REPO_URL="https://raw.githubusercontent.com/goodlux/claude-cli/main"
SCRIPT_FILES=("bin/claude-cli" "bin/lib/context.sh" "bin/lib/settings.sh" "bin/lib/shell.sh")
CONFIG_FILE="config/config.yml.example"

# ASCII Art function
show_terminal_art() {
    local BLUE=$(tput setaf 4)
    local RESET=$(tput sgr0)
    echo
    echo "${BLUE}"
    cat << "EOF"
▄████▄   ██▓    ▄▄▄       █    ██  ▓█████▄ ▓█████ 
▒██▀ ▀█  ▓██▒   ▒████▄     ██  ▓██▒▒██▀ ██▌▓█   ▀ 
▒▓█    ▄ ▒██░   ▒██  ▀█▄  ▓██  ▒██░░██   █▌▒███   
▒▓▓▄ ▄██▒▒██░   ░██▄▄▄▄██ ▓▓█  ░██░░▓█▄   ▌▒▓█  ▄ 
▒ ▓███▀ ░░██████▒▓█   ▓██▒▒▒█████▓ ░▒████▓ ░▒████▒
░ ░▒ ▒  ░░ ▒░▓  ░▒▒   ▓▒█░░▒▓▒ ▒ ▒  ▒▒▓  ▒ ░░ ▒░ ░
  ░  ▒   ░ ░ ▒  ░ ▒   ▒▒ ░░░▒░ ░ ░  ░ ▒  ▒  ░ ░  ░
░          ░ ░    ░   ▒    ░░░ ░ ░  ░ ░  ░    ░   
░ ░          ░  ░     ░  ░   ░        ░       ░  ░
░                                    ░             
EOF
    echo "${RESET}"
    sleep 0.5
}

# Debug function
debug() {
    if [ "$DEBUG" = true ]; then
        echo -e "\033[0;35m[DEBUG]\033[0m $1"
    fi
}

# Print colorized status messages
info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }
error() { echo -e "\033[0;31m[ERROR]\033[0m $1" >&2; }

# Check for required dependencies
check_dependencies() {
    debug "Checking dependencies..."
    local missing_deps=()
    
    for cmd in curl jq yq; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        error "Missing required dependencies: ${missing_deps[*]}"
        echo "Please install them first:"
        echo "  - For Ubuntu/Debian: sudo apt-get install ${missing_deps[*]}"
        echo "  - For macOS: brew install ${missing_deps[*]}"
        exit 1
    fi
}

# Create installation directory structure
setup_directory() {
    debug "Creating directory structure at $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/bin/lib" "$INSTALL_DIR/cache"
}

# Handle API key input with proper terminal handling
setup_credentials() {
    if [ -f "$INSTALL_DIR/credentials" ]; then
        info "Existing credentials file found"
        return 0
    fi
    
    # Save current terminal settings
    if [ -t 0 ]; then
        OLD_TTY=$(stty -g)
    fi
    
    # Create credentials file first
    echo "# Anthropic API credentials" > "$INSTALL_DIR/credentials"
    echo "# Get your API key from: https://console.anthropic.com/dashboard" >> "$INSTALL_DIR/credentials"
    chmod 600 "$INSTALL_DIR/credentials"
    
    # Only prompt for API key if we have a terminal
    if [ -t 0 ]; then
        echo "Please enter your Anthropic API key"
        echo "You can find your API key at: https://console.anthropic.com/dashboard"
        echo "If you don't have one yet, press Enter to skip and add it later"
        echo -n "API key: "
        
        # Read API key with proper terminal handling
        read -r api_key </dev/tty
        
        # Restore terminal settings
        stty "$OLD_TTY"
        
        if [ -n "$api_key" ]; then
            echo "ANTHROPIC_API_KEY=$api_key" >> "$INSTALL_DIR/credentials"
            success "API key configured"
        else
            echo "ANTHROPIC_API_KEY=your_api_key_here" >> "$INSTALL_DIR/credentials"
            info "No API key provided. You can add it later by editing $INSTALL_DIR/credentials"
        fi
    else
        # If no terminal, create with placeholder
        echo "ANTHROPIC_API_KEY=your_api_key_here" >> "$INSTALL_DIR/credentials"
        info "No terminal detected. Please edit $INSTALL_DIR/credentials to add your API key"
    fi
}

# Install files from either local or remote source
install_files() {
    if [ "$USE_LOCAL" = true ]; then
        debug "Installing from local repository"
        info "Installing from local files..."
        
        for file in "${SCRIPT_FILES[@]}"; do
            debug "Copying $file"
            local dir=$(dirname "$INSTALL_DIR/$file")
            mkdir -p "$dir"
            if [ -f "./$file" ]; then
                cp "./$file" "$INSTALL_DIR/$file"
                chmod 755 "$INSTALL_DIR/$file"
                success "Copied $file"
            else
                error "Missing local file: ./$file"
                exit 1
            fi
        done
        
        if [ ! -f "$INSTALL_DIR/config.yml" ]; then
            debug "Copying config file"
            cp "./$CONFIG_FILE" "$INSTALL_DIR/config.yml"
            chmod 644 "$INSTALL_DIR/config.yml"
            success "Copied config.yml"
        fi
    else
        debug "Installing from remote repository"
        info "Downloading from repository..."
        
        for file in "${SCRIPT_FILES[@]}"; do
            debug "Downloading $file"
            local dir=$(dirname "$INSTALL_DIR/$file")
            local url="$REPO_URL/$file"
            mkdir -p "$dir"
            
            if curl --output /dev/null --silent --head --fail "$url"; then
                if ! curl -sSL "$url" -o "$INSTALL_DIR/$file"; then
                    error "Failed to download $file"
                    exit 1
                fi
                chmod 755 "$INSTALL_DIR/$file"
                success "Downloaded $file"
            else
                error "File not found at URL: $url"
                exit 1
            fi
        done
        
        if [ ! -f "$INSTALL_DIR/config.yml" ]; then
            debug "Downloading config file"
            local config_url="$REPO_URL/$CONFIG_FILE"
            if curl --output /dev/null --silent --head --fail "$config_url"; then
                if ! curl -sSL "$config_url" -o "$INSTALL_DIR/config.yml"; then
                    error "Failed to download config file"
                    exit 1
                fi
                chmod 644 "$INSTALL_DIR/config.yml"
                success "Downloaded config.yml"
            else
                error "Config file not found at URL: $config_url"
                exit 1
            fi
        fi
    fi
}

# Configure shell
configure_shell() {
    debug "Configuring shell..."
    local shell_config
    
    case "$SHELL" in
        */zsh) shell_config="$HOME/.zshrc" ;;
        */bash) shell_config="$HOME/.bashrc" ;;
        *) 
            error "Unsupported shell: $SHELL"
            echo "Please manually add: source $INSTALL_DIR/bin/claude-cli"
            return 1
            ;;
    esac
    
    debug "Using shell config: $shell_config"
    
    if ! grep -q "source.*$INSTALL_DIR/bin/claude-cli" "$shell_config"; then
        echo "source $INSTALL_DIR/bin/claude-cli" >> "$shell_config"
        success "Added Claude CLI to $shell_config"
    else
        info "Claude CLI already configured in $shell_config"
    fi
}

# Verify installation
verify_installation() {
    debug "Verifying installation..."
    
    local missing_files=0
    for file in "${SCRIPT_FILES[@]}"; do
        if [ ! -f "$INSTALL_DIR/$file" ]; then
            error "Missing file: $INSTALL_DIR/$file"
            missing_files=1
        fi
    done
    
    if [ $missing_files -eq 0 ]; then
        show_terminal_art
        success "Claude CLI installed successfully!"
        echo
        if ! grep -q "^ANTHROPIC_API_KEY=your_api_key_here$" "$INSTALL_DIR/credentials"; then
            echo "Installation complete! To use Claude CLI:"
            echo "1. Start a new shell or run:"
            echo "   source $INSTALL_DIR/bin/claude-cli"
        else
            echo "Almost done! To complete setup:"
            echo "1. Add your API key by editing $INSTALL_DIR/credentials"
            echo "   Get your key from: https://console.anthropic.com/dashboard"
            echo
            echo "2. Start a new shell or run:"
            echo "   source $INSTALL_DIR/bin/claude-cli"
        fi
        echo
        echo "For more information, visit: https://github.com/goodlux/claude-cli"
    else
        error "Installation verification failed"
        exit 1
    fi
}

# Main installation flow
main() {
    debug "Starting installation..."
    debug "Use local files: $USE_LOCAL"
    
    echo "Installing Claude CLI..."
    [ "$USE_LOCAL" = true ] && echo "Installing from local repository"
    [ "$USE_LOCAL" = false ] && echo "Installing from remote repository"
    
    check_dependencies
    setup_directory
    setup_credentials
    install_files
    configure_shell
    verify_installation
}

main "$@"
# Main installation flow
main() {
    debug "Starting installation..."
    debug "Use local files: $USE_LOCAL"
    
    echo "Installing Claude CLI..."
    [ "$USE_LOCAL" = true ] && echo "Installing from local repository"
    [ "$USE_LOCAL" = false ] && echo "Installing from remote repository"
    
    check_dependencies
    setup_directory
    setup_credentials
    install_files
    configure_shell
    verify_installation
}

main "$@"