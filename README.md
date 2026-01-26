# Homelab Setup

This homelab is currently broken down into these services:

- A network group handles a local DNS server and reverse proxy.
  - Pihole: Used as DNS Server
  - Caddy: Used as Reverse proxy
- A media group that handles Movie & TV Shows, with endpoints to request and watch content, as well as manage all services.
  - Prowlarr: Indexes torrent trackers for downstream services to search for content
  - Sonarr: Manages TV Shows
- Radarr: Manages Movies
  - Janitorr: Automatic removal of content
  - qBittorrent: Manages content torrents
  - tor: Network to access certain indexers through the tor network
  - Jellyfin: Media library server
  - Jellyseerr: Handles media requests

## 1. WireGuard

Follow the instructions in the `homelab/wireguard` direcotry to setup a VPN connection between your home server and any number of clients. This assumes you install WireGuard directly on the host.

If you follow this guide, and are only using one server, your DNS server will just be the same IP as the host machine. (`10.0.0.1`)
Otherwise, you will need to add the server IP assigned through WireGuard of your DNS server (e.g. Pihole).

## Docker containers

1. Install docker and docker compose: `sudo apt-get install docker docker-compose`
2. Copy all contents from this folder to a `~/docker` folder on the host machine

```
cp -r homelab/* ~/docker/
```

3. Start all services up by running this while in `~/docker`:

```
sudo docker compose up -d
```

4. Head into `media` and follow the `README.md`. Should be pretty straightforward.
5. Head into `networking` and follow the `README.md`. You should ensure that the IPs used here should be updated in the WireGuard configs.

6. Setup docker engine to start on boot, which should automaticall spin up all containers on boot:

```
sudo systemctl enable docker
```

## Docker Compose Troubleshooting

I've run into this issue:

```
Error response from daemon: failed to create task for container: failed to create shim task: OCI runtime create failed: runc create failed: unable to start container process: can't get final child's PID from pipe: EOF
```

And I solved it by:

```
sudo systemctl stop docker.service
# because I had setup docker to start on boot
sudo systemctl stop docker.socket
sudo systemctl stop containerd.service

systemctl status docker docker.socket containerd

sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd
sudo rm -rf /run/docker
sudo rm -rf /run/containerd

sudo reboot

# After restart
sudo systemctl start containerd
sudo systemctl start docker
# Test docker
sudo docker run --rm alpine echo OK
sudo systemctl enable docker
```
