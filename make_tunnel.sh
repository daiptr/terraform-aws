#!/bin/bash
exec &> /tmp/make_tunnel.txt
sudo yum update -y
sleep 20s

sudo sysctl net.ipv4.ip_forward=1
sleep 5
sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination 10.0.1.50:80
sleep 5
sudo iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination 10.0.1.50:443
sleep 5
sudo iptables -t nat -A POSTROUTING -j MASQUERADE


