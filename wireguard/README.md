Creating a setup guide for myself to remember how I setup wireguard at home.

Referenced guides and tools:

- https://avidadmin.substack.com/p/building-a-home-lab-part-3-installing
- https://www.wireguardconfig.com/qrcode

# Required software

- duckdns (working for me now, but i've heard DynuDNS is also good), for example: mydns.duckdns.org
- wireguard on the server, usually installed on linux like so:

```
sudo apt update && sudo apt upgrade -y
sudo apt install wireguard
```

- wireguard on all the clients, I installed it on Mac and iOS through the app store.

# Setup server

1. On the server, create a folder to store all the setup configs:

```
mkdir ~/wireguard
```

2. Create a public/private key pair for the SERVER:

```
cd ~/wireguard
( umask 0077 && wg genkey | tee privatekey-server | wg pubkey > publickey-server )
```

3. Identify the interface being used for the server's LAN IP (assuming linux):

```
ip a
```

The result looks something like this:

```
me@debian:~/wireguard$ ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute
       valid_lft forever preferred_lft forever
2: ens18: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether bc:24:11:7a:ba:de brd ff:ff:ff:ff:ff:ff
    altname enp0s18
    altname enxbc24117abade
    inet 192.168.0.2/24 brd 192.168.0.255 scope global dynamic noprefixroute ens18
       valid_lft 54509sec preferred_lft 43709sec
    inet6 fe80::bcb1:add3:c256:194d/64 scope link
       valid_lft forever preferred_lft forever
```

So my LAN IP is `192.168.0.2` and my interface is `ens18`

4. Create a `~/wireguard/wg0-server.conf` file, replace `<INTERFACE>` with your interface, `<PRIVATEKEY-SERVER>` with your server private key:

```
[Interface]
Address=10.0.0.1/24 # Make sure this private address range is not in use. /24 gives a small/secure subnet
SaveConfig=true
# this set of PostUp/PostDown only allows VPN clients to send packets in, and makes the VPN client look like it's in the home network.
PostUp=iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o <INTERFACE> -j MASQUERADE;
PostDown=iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o <INTERFACE> -j MASQUERADE;

# this set of PostUp/PostDown accepts traffic coming IN from VPN clients, allow reply traffic back to VPN clients, but only for connections they started, rewrite VPN traffic so it looks like it's coming from the home network
# this is the set you want to access websites (Netflix) while looking like you're at home.
PostUp=iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o ens18 -j MASQUERADE;
PostDown=iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -o ens18 -j MASQUERADE;

ListenPort=51820 # Standard port for WireGuard
PrivateKey=<PRIVATEKEY-SERVER>
```

5. Move the `wg0-server.conf` to `/etc/wireguard/wg0.conf`:

```
sudo cp wg0-server.conf /etc/wireguard/wg0.conf
```

6. Allow packets to be port-forwarded to WireGuard:

```
sudo sysctl -w net.ipv4.ip_forward=1
```

7. Bring up the wireguard interface `wg0`:

```
sudo wg-quick up wg0
```

# Setup client (Mac)

1. With Wireguard installed, click `+` -> `Add empty tunnel...`

2. You will see already generated Public and Private Key pair. Note them down, i stored them on the server at `~/wireguard/publickey-mac` and `~/wireguard/privatekey-mac`.

3. Fill out the text box like so:

```
[Interface]
PrivateKey = <PREPOPULATED-PRIVATE-KEY>
Address = 10.0.0.2/8 # replace the 2 with any number between 3-255 for additional clients
# needed so DNS requests look as if they're coming from the home network. I'm running pihole on the same server i'm connecting to, so I'm using it's actual IP through wireguard. Since I'm running pihole on the same server as wireguard, i gave it 10.0.0.1
DNS = <ROUTER-IP-ADDRESS/PIHOLE-DNS-SERVER-ADDRESS>

[Peer]
PublicKey = <PUBLICKEY-SERVER>
AllowedIPs = 10.0.0.1/32
Endpoint = <PUBLIC-IP-ADDRESS>:51820
PersistentKeepalive = 60
```

The PUBLIC-IP-ADDRESS will be the DuckDNS domain you obtained earlier (`mydns.duckdns.org`).
You can alternatively get the PUBLIC-IP-ADDRESS at whatismyipaddress.com, which is the public IP for your entire home network. This may change though, so I'd recommend setting up Duck/Dynu DNS.

4. On the server, you'll need to add this client as a peer, append this at the bottom of your `wg0-server.conf`:

```
[Peer]
PublicKey = <PUBLICKEY-MAC>
AllowedIPs = 10.0.0.2/32
```

5. Move the `wg0-server.conf` to `/etc/wireguard/wg0.conf`:

```
sudo cp wg0-server.conf /etc/wireguard/wg0.conf
```

7. Restart the WireGuard interface:

```
sudo wg-quick down wg0
sudo wg-quick up wg0
```

# Setup client (iPhone)

1. Install WireGuard
2. Generate a public/private key pair (with the same command as the server key generation)
3. Create a `wg0-iphone.conf` file. I used [the WireGuard QR Code Generator](https://www.wireguardconfig.com/qrcode) to convert the following into a QR code for my phone:

```
[Interface]
PrivateKey = <PRIVATEKEY-IPHONE>
Address = 10.0.0.3/8
# needed so DNS requests look as if they're coming from the home network. I'm running pihole on the same server i'm connecting to, so I'm using it's actual IP through wireguard. Since I'm running pihole on the same server as wireguard, i gave it 10.0.0.1
DNS = <ROUTER-IP-ADDRESS/PIHOLE-DNS-SERVER-ADDRESS>

[Peer]
PublicKey = <PUBLICKEY-SERVER>
AllowedIPs = 10.0.0.1/32
Endpoint = mydns.duckdns.org:51820
PersistentKeepalive = 60
```

4. Scan the QR code on WireGuard installed on the phone

5. On the server, you'll need to add this phone as a peer, append this at the bottom of your `wg0-server.conf`:

```
[Peer]
PublicKey = <PUBLICKEY-IPHONE>
AllowedIPs = 10.0.0.3/32
```

6. Move the `wg0-server.conf` to `/etc/wireguard/wg0.conf`:

```
sudo cp wg0-server.conf /etc/wireguard/wg0.conf
```

7. Restart the WireGuard interface:

```
sudo wg-quick down wg0
sudo wg-quick up wg0
```

# Setup client (linux)

You get the drill at this point I think:

1. Install WireGuard
2. Generate a public/private key pair (with the same command as the server key generation)
3. Create a `wg0-client.conf` for the client, and place in the client's `/etc/wireguard/wg0.conf`. Looks like so:

```
[Interface]
PrivateKey = <PRIVATEKEY-CLIENT>
Address = 10.0.0.4/32
# needed so DNS requests look as if they're coming from the home network. I'm running pihole on the same server i'm connecting to, so I'm using it's actual IP through wireguard. Since I'm running pihole on the same server as wireguard, i gave it 10.0.0.1
DNS = <ROUTER-IP-ADDRESS/PIHOLE-DNS-SERVER-ADDRESS>

[Peer]
PublicKey = <PUBLICKEY-SERVER>
AllowedIPs = 10.0.0.1/32
Endpoint = mydns.duckdns.org:51820
PersistentKeepalive = 60
```

4. Startup wireguard interface:

```
sudo wg-quick up wg0
```

5. On the server, you'll need to add this client as a peer, append this at the bottom of your `wg0-server.conf`:

```
[Peer]
PublicKey = <PUBLICKEY-CLIENT>
AllowedIPs = 10.0.0.4/32
```

6. Move the `wg0-server.conf` to `/etc/wireguard/wg0.conf`:

```
sudo cp wg0-server.conf /etc/wireguard/wg0.conf
```

7. Restart the WireGuard interface:

```
sudo wg-quick down wg0
sudo wg-quick up wg0
```
