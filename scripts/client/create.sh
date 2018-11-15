#!/bin/bash

read -p 'Enter Common Name for client profile: ' client
read -p 'Enter CA Username: ' causer
read -p 'Enter CA Hostname/IP: ' cahost

cd ~/EasyRSA*/
echo | ./easyrsa gen-req $client nopass
cp pki/private/$client.key ~/client-configs/keys/
scp pki/reqs/$client.req $causer@$cahost:/tmp

ssh $causer@$cahost "
cd ~/EasyRSA*/
./easyrsa import-req /tmp/$client.req $client
echo 'yes' | ./easyrsa sign-req client $client
"

scp $causer@$cahost:~/EasyRSA*/pki/issued/$client.crt /tmp
cp /tmp/$client.crt ~/client-configs/keys/

sudo cp ~/EasyRSA*/ta.key ~/client-configs/keys/
sudo cp /etc/openvpn/ca.crt ~/client-configs/keys/

KEY_DIR=~/client-configs/keys
OUTPUT_DIR=~/client-configs/files
BASE_CONFIG=~/openvpn-installer/conf/client.conf
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