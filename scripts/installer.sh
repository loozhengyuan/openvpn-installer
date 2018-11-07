#!/bin/bash

##########################
# SETTING OPENVPN SERVER #
##########################

sudo apt update -y
sudo apt upgrade -y
sudo apt install unattended-upgrades ufw openvpn curl -y

read -p 'Enter CA Username: ' causer
read -p 'Enter CA Hostname/IP: ' cahost

ssh-keygen -b 4096 -t rsa  -N ""
ssh-copy-id $causer@$cahost

latest=$(curl -s https://api.github.com/repos/OpenVPN/easy-rsa/releases/latest | grep -oP '"tag_name": "v\K(.*)(?=")')
if [ ! -d "~/EasyRSA-$latest/" ]; then
    wget -P ~/ https://github.com/OpenVPN/easy-rsa/releases/download/v$latest/EasyRSA-nix-$latest.tgz
    cd ~ && tar xvf EasyRSA-nix-$latest.tgz
else
    echo "WARNING: EasyRSA-$latest is already the latest version, skipping installation..."
fi

#########################################
# CREATING CERTIFICATE AUTHORITY SERVER #
#########################################

ssh -t $causer@$cahost "
sudo apt update -y
sudo apt upgrade -y
sudo apt install unattended-upgrades ufw curl -y
latest=$(curl -s https://api.github.com/repos/OpenVPN/easy-rsa/releases/latest | grep -oP '"tag_name": "v\K(.*)(?=")')
if [ ! -d "~/EasyRSA-$latest/" ]; then
    wget -P ~/ https://github.com/OpenVPN/easy-rsa/releases/download/v$latest/EasyRSA-nix-$latest.tgz
    cd ~ && tar xvf EasyRSA-nix-$latest.tgz
else
    echo "WARNING: EasyRSA-$latest is already the latest version, skipping installation..."
fi
cd ~/EasyRSA-$latest/
if [ ! -d "~/EasyRSA-$latest/pki" ]; then
    ./easyrsa init-pki
    echo | ./easyrsa build-ca nopass
else
    echo "WARNING: ~/EasyRSA-$latest/pki is not empty, skipping init-pki and build-ca..."
fi
"

######################################
# INITIALISING CERTS FOR OVPN SERVER #
######################################

read -p 'Name of OpenVPN Server (lowercase; no spaces): ' server

cd ~/EasyRSA-$latest/
./easyrsa init-pki
echo | ./easyrsa gen-req $server nopass
sudo cp ~/EasyRSA-$latest/pki/private/$server.key /etc/openvpn/
scp ~/EasyRSA-$latest/pki/reqs/$server.req $causer@$cahost:/tmp

ssh $causer@$cahost "
cd ~/EasyRSA-$latest/
./easyrsa import-req /tmp/$server.req $server
echo 'yes' | ./easyrsa sign-req server $server
"

scp $causer@$cahost:~/EasyRSA*/pki/issued/$server.crt /tmp
scp $causer@$cahost:~/EasyRSA*/pki/ca.crt /tmp

sudo cp /tmp/{$server.crt,ca.crt} /etc/openvpn/
cd ~/EasyRSA-$latest/
./easyrsa gen-dh
sudo openvpn --genkey --secret ta.key
sudo cp ~/EasyRSA-$latest/ta.key /etc/openvpn/
sudo cp ~/EasyRSA-$latest/pki/dh.pem /etc/openvpn/

#############################
# OVPN SERVER CONFIGURATION #
#############################

mkdir -p ~/client-configs/keys
mkdir -p ~/client-configs/files
chmod -R 700 ~/client-configs

sudo cp ~/ovpn-helper/server.conf /etc/openvpn/
sudo cp ~/ovpn-helper/client.conf /etc/openvpn/

sudo sed -i -e "s/cert server.crt/cert $server.crt/g" /etc/openvpn/server.conf
sudo sed -i -e "s/key server.key/key $server.key/g" /etc/openvpn/server.conf

sudo sed -i '/net.ipv4.ip_forward=1/s/^#//g' /etc/sysctl.conf
sudo sysctl -p
ip route | grep -oP 'default(.*)\K(eth)(\d)'

sudo tee -a /etc/ufw/before.rules << EOF
# START OPENVPN RULES
# NAT table rules
*nat
:POSTROUTING ACCEPT [0:0] 
# Allow traffic from OpenVPN client to eth0 (change to the interface you discovered!)
-A POSTROUTING -s 10.8.0.0/8 -o eth0 -j MASQUERADE
COMMIT
# END OPENVPN RULES
EOF

sudo sed -i -e 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/g' /etc/default/ufw

sudo ufw allow 1194/udp
sudo ufw allow OpenSSH
sudo ufw disable
sudo ufw --force enable

######################################
# INITIALISING CERTS FOR OVPN CLIENT #
######################################

read -p 'Name of client profile to be ADDED: ' client

cd ~/EasyRSA*/
echo | ./easyrsa gen-req $client nopass
sudo cp ~/EasyRSA-$latest/pki/private/$client.key ~/client-configs/keys/
scp ~/EasyRSA-$latest/pki/reqs/$client.req $causer@$cahost:/tmp

ssh $causer@$cahost "
cd ~/EasyRSA-$latest/
./easyrsa import-req /tmp/$client.req $client
echo 'yes' | ./easyrsa sign-req client $client
"

scp $causer@$cahost:~/EasyRSA*/pki/issued/$client.crt /tmp
cp /tmp/$client.crt ~/client-configs/keys/

sudo cp ~/EasyRSA*/ta.key ~/client-configs/keys/
sudo cp /etc/openvpn/ca.crt ~/client-configs/keys/

KEY_DIR=~/client-configs/keys
OUTPUT_DIR=~/client-configs/files
BASE_CONFIG=~/ovpn-helper/client.conf
FULL_HOSTNAME=$(hostname -f)

touch $OUTPUT_DIR/$client@$FULL_HOSTNAME.ovpn
sudo cat $BASE_CONFIG | sudo tee $OUTPUT_DIR/$client@$FULL_HOSTNAME.ovpn
sudo echo -e '\n\n<ca>' | sudo tee -a $OUTPUT_DIR/$client@$FULL_HOSTNAME.ovpn
sudo cat $KEY_DIR/ca.crt | sudo tee -a $OUTPUT_DIR/$client@$FULL_HOSTNAME.ovpn
sudo echo -e '</ca>\n\n<cert>' | sudo tee -a $OUTPUT_DIR/$client@$FULL_HOSTNAME.ovpn
sudo cat $KEY_DIR/$client.crt | sudo tee -a $OUTPUT_DIR/$client@$FULL_HOSTNAME.ovpn
sudo echo -e '</cert>\n\n<key>' | sudo tee -a $OUTPUT_DIR/$client@$FULL_HOSTNAME.ovpn
sudo cat $KEY_DIR/$client.key | sudo tee -a $OUTPUT_DIR/$client@$FULL_HOSTNAME.ovpn
sudo echo -e '</key>\n\n<tls-auth>' | sudo tee -a $OUTPUT_DIR/$client@$FULL_HOSTNAME.ovpn
sudo cat $KEY_DIR/ta.key | sudo tee -a $OUTPUT_DIR/$client@$FULL_HOSTNAME.ovpn
sudo echo -e '</tls-auth>' | sudo tee -a $OUTPUT_DIR/$client@$FULL_HOSTNAME.ovpn

echo "You may now access the config file at ~/client-configs/files/$client@$FULL_HOSTNAME.ovpn"

################
# START SERVER #
################

sudo systemctl start openvpn@server
sudo systemctl status openvpn@server
sudo systemctl enable openvpn@server