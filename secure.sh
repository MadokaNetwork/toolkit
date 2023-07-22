#!/bin/bash

function display_help() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -u, --username               Specify a username for the new user account."
    echo "  -p, --password               Specify a password for the new user account."
    echo "  -g, --github-username        Specify a GitHub username for the SSH key setup."
    echo "  -P, --ssh-port               Specify a custom SSH port."
    echo "  -s, --hist-size              Specify a custom history size."
    echo "  -t, --auto-logout            Specify a custom auto logout time."
    echo "  -D, --DEBUG                  Enable debug mode."
    echo "      --superuser              Create a superuser with the specified username and password."
    echo "      --disable-history        Disable command history."
    echo "      --auto-logout            Enable automatic logout after a period of inactivity."
    echo "      --secure-ssh             Secure SSH by disabling root login and enforcing key-based authentication."
    echo "      --ALLOW-PASSWORD-INSECURE-LOGIN   Allow insecure login with password even if no valid SSH key exists."
    echo "      --all                    Run all of the above options."
    echo "  -h, --help                   Display this help message and exit."
}

function init() {
    local DEBUG_MODE=${1:-0}  # Default to 0 if not provided

    for cmd in sudo curl sed; do
        if ! command -v $cmd &> /dev/null; then
            if [ $DEBUG_MODE -eq 1 ]; then
                echo "Installing missing tool: $cmd"
                sudo apt-get update
                sudo apt-get install -yy $cmd
            else
                sudo apt-get update -qq
                sudo apt-get install -qq -yy $cmd
            fi
        fi
    done
}

function superuser() {
    local USERNAME=$1
    local PASSWORD=$2
    local ROOT_PASSWORD=$(openssl rand -base64 32)

    sudo useradd -m -s /bin/bash -p $(openssl passwd -1 $PASSWORD) $USERNAME
    usermod -aG sudo $USERNAME
    echo "root:$ROOT_PASSWORD" | sudo chpasswd
}


function setup_ssh_key() {
    local USERNAME=$1
    local GITHUB_USER=$2
    local ALLOW_PASSWORD=$3
    local DEBUG_MODE=$4

    if [[ $DEBUG_MODE -eq 0 ]]; then
        SSH_KEY=$(curl -s -L https://github.com/$GITHUB_USER.keys)
    else
        SSH_KEY=$(curl -L https://github.com/$GITHUB_USER.keys)
    fi

    if echo $SSH_KEY | grep -q "ssh-"; then
        mkdir /home/$USERNAME/.ssh
        echo $SSH_KEY > /home/$USERNAME/.ssh/authorized_keys 
        chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh/
    else
        if [ $ALLOW_PASSWORD -ne 1 ]; then
            echo "Error: GitHub user $GITHUB_USER does not have a valid SSH key"
            exit 1
        fi
    fi
}


function disable_history() {
    local HISTSIZE_VALUE=${1:-1}

    echo "HISTSIZE=$HISTSIZE_VALUE" | sudo tee -a /etc/profile > /dev/null
    echo "export HISTSIZE" | sudo tee -a /etc/profile > /dev/null
    echo "readonly HISTSIZE" | sudo tee -a /etc/profile > /dev/null
}

function auto_logout() {
    local TMOUT_VALUE=${1:-1800}

    echo "TMOUT=$TMOUT_VALUE" | sudo tee -a /etc/profile > /dev/null
    echo "readonly TMOUT" | sudo tee -a /etc/profile > /dev/null
    echo "export TMOUT" | sudo tee -a /etc/profile > /dev/null
}

function secure_ssh() {
    local USERNAME=$1
    local SSH_PORT=$2
    local ALLOW_PASSWORD=$3



    if [ ! -f /home/$USERNAME/.ssh/authorized_keys ]; then
        echo "Error: .ssh/authorized_keys does not exist for user $USERNAME"
        exit 1
    fi

    sudo sed -i 's/#\?\(PermitRootLogin\s*\).*$/\1 no/' /etc/ssh/sshd_config
    sudo sed -i 's/#\?\(PubkeyAuthentication\s*\).*$/\1 yes/' /etc/ssh/sshd_config

    if [ $ALLOW_PASSWORD -ne 1 ]; then
        sudo sed -i 's/#\?\(PasswordAuthentication\s*\).*$/\1 no/' /etc/ssh/sshd_config
        rm /etc/ssh/sshd_config.d/*.conf
    fi
    
    if [ $ALLOW_PASSWORD -eq 0 ]; then
        sudo sed -i 's/#\?\(PubkeyAuthentication\s*\).*$/\1 yes/' /etc/ssh/sshd_config
    fi

    # Only change Port in sshd_config if SSH_PORT is not 0
    if [ $SSH_PORT -ne 0 ]; then
        sudo sed -i "s/#\?\(Port\s*\).*$/\1 $SSH_PORT/" /etc/ssh/sshd_config
    fi

    sudo sed -i 's/#\?\(ClientAliveInterval\s*\).*$/\1 15/' /etc/ssh/sshd_config
    sudo sed -i 's/#\?\(ClientAliveCountMax\s*\).*$/\1 45/' /etc/ssh/sshd_config
    sudo sed -i 's/#\?\(PermitEmptyPasswords\s*\).*$/\1 no/' /etc/ssh/sshd_config
    sudo systemctl restart sshd
}


function main() {
    local USERNAME=""
    local PASSWORD=""
    local GITHUB_USER=""
    local SSH_PORT=22
    local HISTSIZE_VALUE=1
    local TMOUT_VALUE=1800
    local DEBUG_MODE=0
    local ALLOW_PASSWORD=0

    local SUPERUSER=0
    local DISABLE_HISTORY=0
    local AUTO_LOGOUT=0
    local SECURE_SSH=0

    while (( "$#" )); do
        case "$1" in
            -h|--help)
                display_help
                exit 0
                ;;
            -u|--username)
                USERNAME="$2"
                shift 2
                ;;
            -p|--password)
                PASSWORD="$2"
                shift 2
                ;;
            -g|--github-username)
                GITHUB_USER="$2"
                shift 2
                ;;
            -P|--ssh-port)
                SSH_PORT="$2"
                shift 2
                ;;
            -s|--hist-size)
                HISTSIZE_VALUE="$2"
                shift 2
                ;;
            -t|--auto-logout)
                TMOUT_VALUE="$2"
                shift 2
                ;;
            -D|--DEBUG)
                DEBUG_MODE=1
                shift
                ;;
            --superuser)
                SUPERUSER=1
                shift
                ;;
            --disable-history)
                DISABLE_HISTORY=1
                shift
                ;;
            --auto-logout)
                AUTO_LOGOUT=1
                shift
                ;;
            --secure-ssh)
                SECURE_SSH=1
                shift
                ;;
            --ALLOW-PASSWORD-INSECURE-LOGIN)
                ALLOW_PASSWORD=1
                shift
                ;;
            --all)
                SUPERUSER=1
                DISABLE_HISTORY=1
                AUTO_LOGOUT=1
                SECURE_SSH=1
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "Error: Invalid argument"
                exit 1
        esac
    done

        
    init $DEBUG_MODE

    if [[ $SUPERUSER -eq 1 ]]; then
        if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
            echo "Error: You must specify a username and password when creating a superuser"
            exit 1
        fi
        superuser $USERNAME $PASSWORD
    fi

    # If SSH_PORT is 0, set it to the default value 22
    if [ $SSH_PORT -eq 0 ]; then
        SSH_PORT=22
    fi

    if [[ $SUPERUSER -eq 1 && $SECURE_SSH -eq 1 ]]; then
        if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ] || [ -z "$GITHUB_USER" ]; then
            echo "Error: You must specify a username, password and GitHub username when creating a superuser and setting up secure SSH"
            exit 1
        fi
        setup_ssh_key $USERNAME $GITHUB_USER $ALLOW_PASSWORD $DEBUG_MODE
        secure_ssh $USERNAME $SSH_PORT $ALLOW_PASSWORD 
    elif [[ $SECURE_SSH -eq 1 ]]; then
        if [ -z "$USERNAME" ]; then
            echo "Error: You must specify a username when setting up secure SSH"
            exit 1
        fi
        if [[ ! -z "$GITHUB_USER" ]] || [[ $SUPERUSER -eq 1 ]]; then
            setup_ssh_key $USERNAME $GITHUB_USER $ALLOW_PASSWORD $DEBUG_MODE
        fi
        secure_ssh $USERNAME $SSH_PORT $ALLOW_PASSWORD 
    fi



    if [[ $DISABLE_HISTORY -eq 1 ]]; then
        disable_history $HISTSIZE_VALUE
    fi

    if [[ $AUTO_LOGOUT -eq 1 ]]; then
        auto_logout $TMOUT_VALUE
    fi


    if [[ $1 == '-h' || $1 == '--help' ]]; then
        display_help
        exit 0
    fi
}

# Call the main function with all command line arguments
main "$@"
