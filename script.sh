#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status
set -o pipefail  # Exit if any command in a pipeline fails

# Colors for output
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m" # No color

# ASCII Art Section
# Add your ASCII art here
cat << "EOF"
           .--,-``-.                                                                                 
      ,-. /   /     '.                                               ___                             
  ,--/ /|/ ../        ;                                            ,--.'|_                ,-.----.   
,--. :/ |\ ``\  .`-    '                                           |  | :,'          ,--, \    /  \  
:  : ' /  \___\/   \   : .--.--.             .--.--.               :  : ' :        ,'_ /| |   :    | 
|  '  /        \   :   |/  /    '           /  /    '     ,---.  .;__,'  /    .--. |  | : |   | .\ : 
'  |  :        /  /   /|  :  /`./          |  :  /`./    /     \ |  |   |   ,'_ /| :  . | .   : |: | 
|  |   \       \  \   \|  :  ;_            |  :  ;_     /    /  |:__,'| :   |  ' | |  . . |   |  \ : 
'  : |. \  ___ /   :   |\  \    `.          \  \    `. .    ' / |  '  : |__ |  | ' |  | | |   : .  | 
|  | ' \ \/   /\   /   : `----.   \          `----.   \'   ;   /|  |  | '.'|:  | : ;  ; | :     |`-' 
'  : |--'/ ,,/  ',-    ./  /`--'  /         /  /`--'  /'   |  / |  ;  :    ;'  :  `--'   \:   : :    
;  |,'   \ ''\        ;'--'.     /         '--'.     / |   :    |  |  ,   / :  ,      .-./|   | :    
'--'      \   \     .'   `--'---'            `--'---'   \   \  /    ---`-'   `--`----'    `---'.|    
           `--`-,,-'                                     `----'                             `---`    
EOF

# Function to configure Netplan
configure_netplan() {
  echo -e "${GREEN}Current IP addresses assigned by DHCP:${NC}"
  ip -4 addr show | grep inet | awk '{print $2}' | grep -v 127.0.0.1

  # Get the current default gateway
  CURRENT_GATEWAY=$(ip route | grep default | awk '{print $3}')
  echo -e "${GREEN}Current default gateway: ${CURRENT_GATEWAY}${NC}"

  # Interface name
  INTERFACE="ens18"
  echo -e "${GREEN}Configuring interface: ${INTERFACE}${NC}"

  # Prompt the user for static IP configuration
  read -p "Enter the desired static IP (e.g., 192.168.1.100/24) or press Enter for DHCP: " STATIC_IP
  read -p "Enter the default gateway (leave blank to use current gateway: ${CURRENT_GATEWAY}): " GATEWAY
  GATEWAY=${GATEWAY:-$CURRENT_GATEWAY}

  # Prompt for DNS servers
  read -p "Enter DNS servers (comma-separated, e.g., 8.8.8.8,8.8.4.4) or press Enter for default: " DNS_SERVERS
  DNS_SERVERS=${DNS_SERVERS:-"8.8.8.8,8.8.4.4"}

  # Generate Netplan configuration
  NETPLAN_CONFIG="/etc/netplan/50-cloud-init.yaml"
  sudo tee $NETPLAN_CONFIG > /dev/null <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${INTERFACE}:
EOF

  if [ -z "$STATIC_IP" ]; then
    sudo tee -a $NETPLAN_CONFIG > /dev/null <<EOF
      dhcp4: true
EOF
  else
    sudo tee -a $NETPLAN_CONFIG > /dev/null <<EOF
      dhcp4: false
      addresses:
        - ${STATIC_IP}
      routes:
        - to: 0.0.0.0/0
          via: ${GATEWAY}
EOF
  fi

  sudo tee -a $NETPLAN_CONFIG > /dev/null <<EOF
      nameservers:
        addresses: [${DNS_SERVERS}]
EOF

  # Adjust file permissions
  sudo chmod 600 $NETPLAN_CONFIG

  echo -e "${GREEN}Netplan configuration saved to ${NETPLAN_CONFIG}${NC}"
  echo -e "${GREEN}Applying Netplan configuration...${NC}"
  sudo netplan apply

  echo -e "${GREEN}Network configuration applied successfully.${NC}"
}

# Function to install dependencies
dependencies() {
  echo -e "${GREEN}Updating system...${NC}"
  sudo apt update && sudo apt upgrade -y && sudo apt dist-upgrade -y && sudo apt autoremove -y

  echo -e "${GREEN}Installing dependencies...${NC}"
  sudo apt install -y curl wget vim apt-transport-https gnupg
}

# Function to install k3s server
install_server() {
  echo -e "${GREEN}Installing k3s server...${NC}"
  curl -sfL https://get.k3s.io | sh -
  sudo systemctl enable k3s
  sudo systemctl start k3s

  echo -e "${GREEN}Exporting KUBECONFIG...${NC}"
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  echo "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml" >> ~/.bashrc
  source ~/.bashrc

  SERVER_IP=$(hostname -I | awk '{print $1}')
  NODE_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)

  echo -e "${GREEN}k3s server installation complete.${NC}"
}

# Function to install k3s node
install_node() {
  read -p "Enter the server IP: " SERVER_IP
  read -p "Enter the node token: " NODE_TOKEN

  echo -e "${GREEN}Installing k3s node...${NC}"
  curl -sfL https://get.k3s.io | K3S_URL=https://${SERVER_IP}:6443 K3S_TOKEN=${NODE_TOKEN} sh -

  echo -e "${GREEN}k3s node installation complete.${NC}"
}

# Function to install Prometheus and Grafana
install_monitoring() {
  echo -e "${GREEN}Installing Helm...${NC}"
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

  echo -e "${GREEN}Adding Helm repositories for Prometheus and Grafana...${NC}"
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm repo add grafana https://grafana.github.io/helm-charts
  helm repo update

  echo -e "${GREEN}Creating namespace for monitoring...${NC}"
  kubectl create namespace monitoring || echo "Namespace 'monitoring' already exists"

  echo -e "${GREEN}Installing Prometheus...${NC}"
  helm install prometheus prometheus-community/prometheus --namespace monitoring

  echo -e "${GREEN}Installing Grafana...${NC}"
  helm install grafana grafana/grafana --namespace monitoring \
      --set adminPassword=admin \
      --set service.type=NodePort

  echo -e "${GREEN}Waiting for Grafana to be ready...${NC}"
  kubectl wait --namespace monitoring \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/name=grafana \
      --timeout=120s

  echo -e "${GREEN}Setting up port-forward for Grafana...${NC}"
  GRAFANA_PORT=$(kubectl -n monitoring get svc grafana -o jsonpath="{.spec.ports[?(@.port==3000)].nodePort}")
  echo -e "${GREEN}Grafana is accessible at: http://<your-node-ip>:${GRAFANA_PORT}${NC}"
  echo -e "${GREEN}Default credentials - User: admin, Password: admin${NC}"
}


# Main script logic
echo -e "${GREEN}Choose an option:${NC}"
echo "1) Configure network (Netplan)"
echo "2) Install k3s server"
echo "3) Install k3s node"
read -p "Enter your choice (1/2/3): " CHOICE

case $CHOICE in
  1)
    configure_netplan
    ;;
  2)
    dependencies
    install_server
    install_monitoring
    ;;
  3)
    dependencies
    install_node
    ;;
  *)
    echo -e "${RED}Invalid choice. Exiting.${NC}"
    exit 1
    ;;
esac

if [[ $CHOICE -eq 2 ]]; then
  echo -e "${GREEN}Installation Complete!${NC}"
  echo -e "${GREEN}Server IP: ${SERVER_IP}${NC}"
  echo -e "${GREEN}Node Token: ${NODE_TOKEN}${NC}"

  echo -e "${GREEN}Cluster Node Information:${NC}"
  kubectl get nodes

  echo -e "${GREEN}Service Information:${NC}"
  kubectl get svc -A
fi