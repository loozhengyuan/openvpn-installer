#!/bin/bash

read -p 'Name of client profile to be REVOKED: ' client
read -p 'Enter CA Username: ' causer
read -p 'Enter CA Hostname/IP: ' cahost

ssh $causer@$cahost "
cd ~/EasyRSA*/
echo 'yes' | ./easyrsa revoke $client
./easyrsa gen-crl
"

scp $causer@$cahost:~/EasyRSA*/pki/crl.pem /tmp
sudo cp /tmp/crl.pem /etc/openvpn

grep -q -F 'crl-verify crl.pem' /etc/openvpn/server.conf || echo 'crl-verify crl.pem' | sudo tee -a /etc/openvpn/server.conf
sudo systemctl restart openvpn@server