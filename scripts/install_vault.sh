#!/usr/bin/env bash

which unzip curl socat jq route dig vim sshpass || {
  apt-get update -y
  apt-get install unzip socat jq dnsutils net-tools vim curl sshpass -y 
}

# Stop vault if running previously
sudo systemctl stop vault
sleep 5
sudo systemctl status vault


echo $DOMAIN
rm -fr /tmp/vault/data
which unzip curl jq /sbin/route vim sshpass || {
  apt-get update -y
  apt-get install unzip jq net-tools vim curl sshpass -y 
}

mkdir -p /vagrant/pkg/
# insall vault

which vault || {
  pushd /vagrant/pkg
  [ -f vault_${VAULT}_linux_amd64.zip ] || {
    sudo wget https://releases.hashicorp.com/vault/${VAULT}/vault_${VAULT}_linux_amd64.zip
  }

  popd
  pushd /tmp

  sudo unzip /vagrant/pkg/vault_${VAULT}_linux_amd64.zip
  sudo chmod +x vault
  sudo mv vault /usr/local/bin/vault
  popd
}

hostname=$(hostname)

#lets kill past instance
sudo killall vault &>/dev/null
sudo killall vault &>/dev/null
sudo killall vault &>/dev/null

sleep 10

# Create vault user
sudo useradd --system --home /etc/vault.d --shell /bin/false vault

# Create vault service

cat << EOF > /etc/systemd/system/vault.service

[Unit]
Description="HashiCorp Vault - A tool for managing secrets"
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/config.hcl

[Service]
User=vault
Group=vault
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
Capabilities=CAP_IPC_LOCK+ep
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/config.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitIntervalSec=60
StartLimitBurst=3

[Install]
WantedBy=multi-user.target

EOF

# Copy vault configuration inside /etc/vault.d
sudo mkdir -p /etc/vault.d

cat << EOF > /etc/vault.d/config.hcl

listener "tcp" {
  address          = "0.0.0.0:8200"
  cluster_address  = "10.10.46.11:8201"
  tls_disable      = "true"
}

storage "consul" {
  address = "127.0.0.1:8500"
  path    = "vault/"
}

api_addr = "http://10.10.46.11:8200"
cluster_addr = "https://10.10.46.11:8201"

EOF

#start vault
sudo systemctl enable vault
sudo systemctl start vault
journalctl -f -u vault.service > /vagrant/logs/${hostname}.log &
sudo systemctl status vault
echo vault started
sleep 3 

export VAULT_ADDR=http://127.0.0.1:8200 

# Change configuration file
sudo chown --recursive vault:vault /etc/vault.d
sudo chmod 640 /etc/vault.d/config.hcl



# setup .bash_profile
grep VAULT_ADDR ~/.bash_profile || {
  echo export VAULT_ADDR=http://127.0.0.1:8200 | sudo tee -a ~/.bash_profile
}

source ~/.bash_profile

vault operator init > /vagrant/keys.txt
vault operator unseal $(cat /vagrant/keys.txt | grep "Unseal Key 1:" | cut -c15-)
vault operator unseal $(cat /vagrant/keys.txt | grep "Unseal Key 2:" | cut -c15-)
vault operator unseal $(cat /vagrant/keys.txt | grep "Unseal Key 3:" | cut -c15-)
vault login $(cat /vagrant/keys.txt | grep "Initial Root Token:" | cut -c21-)

sudo usermod -aG docker vagrant


vault secrets enable database

docker run -e 'ACCEPT_EULA=Y' -e 'SA_PASSWORD=YourStrong@Passw0rd' -p 1433:1433 -d mcr.microsoft.com/mssql/server:2017-latest

sleep 10         
         

vault write database/config/my-mssql-database \
    plugin_name=mssql-database-plugin \
    connection_url='sqlserver://{{username}}:{{password}}@localhost:1433' \
    allowed_roles="my-role" \
    username="sa" \
    password="YourStrong@Passw0rd"


vault write database/roles/my-role \
    db_name=my-mssql-database \
    creation_statements="CREATE LOGIN [{{name}}] WITH PASSWORD = '{{password}}';\
        CREATE USER [{{name}}] FOR LOGIN [{{name}}];\
        GRANT SELECT ON SCHEMA::dbo TO [{{name}}];" \
    default_ttl="1h" \
    max_ttl="24h"

vault policy write apps /vagrant/apps-policy.hcl
vault token create -policy="apps" > /vagrant/apps_token.txt


#VAULT_TOKEN=s.BKCct7sICNLw7k9MHwbKkZU2 vault read database/creds/my-role
#docker ps
#docker exec -it vigilant_vaughan "bash"
#/opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P "YourStrong@Passw0rd"
#select * from master.sys.server_principals
#go