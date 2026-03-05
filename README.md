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

## 2. Docker containers

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

### Docker Compose Troubleshooting

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

## 3. Backups

This setup currently uses one disk i have plugged into my server. I formatted it as ExFAT so I can access its contents from Windows, Mac or other Linux machines.

Run this because proxmox may not natively include exfat utilities:

```
apt update && apt install exfatprogs -y
```

1. Find the disk in the proxmox console, you should be able to identify it by size, or the fact it is not mounted:

```
lsblk
```

Mine looked like:

```
NAME                         MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
sda                            8:0    0   1.8T  0 disk
├─sda1                         8:1    0   1.8T  0 part
└─sda9                         8:9    0     8M  0 part
sdb                            8:16   0 238.5G  0 disk
├─sdb1                         8:17   0  1007K  0 part
├─sdb2                         8:18   0     1G  0 part
└─sdb3                         8:19   0 237.5G  0 part
  ├─pve-swap                 252:0    0     8G  0 lvm  [SWAP]
  ├─pve-root                 252:1    0  69.4G  0 lvm  /
  ├─pve-data_tmeta           252:2    0   1.4G  0 lvm
  │ └─pve-data-tpool         252:4    0 141.2G  0 lvm
  │   ├─pve-data             252:5    0 141.2G  1 lvm
  │   ├─pve-vm--101--disk--0 252:6    0    32G  0 lvm
  │   └─pve-vm--100--disk--0 252:7    0    20G  0 lvm
  └─pve-data_tdata           252:3    0 141.2G  0 lvm
    └─pve-data-tpool         252:4    0 141.2G  0 lvm
      ├─pve-data             252:5    0 141.2G  1 lvm
      ├─pve-vm--101--disk--0 252:6    0    32G  0 lvm
      └─pve-vm--100--disk--0 252:7    0    20G  0 lvm
sdd                            8:48   0 465.8G  0 disk
```

2. Ensure that disk has no content on it. THese next steps will wipe, and format the disk.

```
fdisk /dev/sdX
```

> Replace `X` with the identifying letter of the drive. I did `fdisk /dev/sdd`

- Create a new GPT table: Type `g` and hit Enter.

- Create a new partition: Type `n`, then hit Enter for all defaults (Partition 1, full size).

- Change the type to ExFAT: Type `t`, then type `11` (Microsoft basic data).

- Write and Exit: Type `w` and hit Enter.

3. Format the drive:

```
mkfs.exfat -L "External_ExFAT" /dev/sdd1
```

> I named mine `"Backup"`

4. Grab the UUID of the drive, not partition:

```
lsblk -f /dev/sdd
```

> ExFAT drives have small UUIDs, mine was `6DE8-52EE`

5. To setup the drive to be automatically mounted on startup, edit your `/etc/fstab`:

```
nano /etc/fstab
```

And place this at the bottom:

```
UUID=6DE8-52EE /backup exfat defaults,nofail,uid=100000,gid=100000,umask=000,x-systemd.device-timeout=10s 0 0
```

> `uid` and `gid` need to be 100000, as thats the root user within unprivledged LXC's. This gives us the greatest felxibility when using this drive as backup.

Run the following commands to set it up and mount the drive:

```
sudo systemctl daemon-reload
sudo mount -a
```

6. In Proxmox, we want to use this drive as a backup for our VMs and LXCs. To do that, we can place the following code in our `/etc/pve/storage.cfg`:

Run :

```
nano /etc/pve/storage.cfg
```

Place this at the bottom

```
dir: backup
        path /backup
        content backup
        prune-backups keep-last=3,keep-daily=7,keep-weekly=4
        is_mountpoint 1
        shared 0
```

> What is_mountpoint 1 does:
> Protection: Proxmox will check if /backup is an active mount point before writing any data.
> Failure Mode: If the drive is unplugged, the backup job will fail with an error instead of silently filling up your local SSD.
>
> keep-last=3: Always keeps the 3 most recent backups, regardless of when they were taken.
> keep-daily=7: Keeps one backup per day for the last week.
> keep-weekly=4: Keeps one backup per week for the last month.

7. Setup backup strategy for Proxmox:

```
pvesm set backup --prune-backups keep-last=3,keep-daily=7,keep-weekly=4
```

### Immich Backup

To setup this drive as a backup location for immich, run this line in the proxmox host console:

```
pct set 100 -mp0 /backup,mp=/mnt/immich_backup
```

We've already set the mount point on the proxmox host to be owned by `100000:100000`, so the root user in this Immich LXC has the abilty to write to the disk.

1. Setup a cron job to rsync your image library:

```
crontab -e
```

2. I set my backup to be everyday at 5am, with the following arguments.

```
0 5 * * 0 rsync -rvtzh --no-perms --no-owner --no-group --info=progress2 /data/upload/library/ /backup
```

- `r` (recursive): Recursive (copies folders).
- `v` (verbose): Provides detailed output, showing which files are being transferred and giving more information about the operation.
- `t` (time): Preserves times (this is critical so rsync knows which files haven't changed next time).
- `z` (compress): Compresses file data during the transfer, which reduces network usage and can speed up transfers over slow connections (but may add overhead on very fast local networks).
- `h` (human-readable): Outputs numbers, such as file sizes, in human-readable formats (e.g., MB, GB).
- --no-perms: Does not try to match the destination file permissions to the source.
- --no-owner: Does not try to preserve the original owner of the file.
- --no-group: Does not try to preserve the original group of the file.
  > --info=progress2: Provides a simplified, real-time progress bar for the entire transfer rather than individual files. Actually not required for the cronjob, but easy to copy this and run manually and also see the progress.

### VM Backup

1. In the Proxmox WebUI, click Datacenter->Directory Mappings -> Add:

- Name: backup
- Path: `/backup`
- Node: pve-1 (the defualt, assuming you only have one node)

2. In the UI, navigate to your VM (mine is VM 101) and under Hardware, add a Virtiofs:

- Directory ID: backup

3. Restart the VM, and then run:

```
mkdir -p /backup
mount -t virtiofs backup /backup
```

4. Add this in your VM's `/etc/fstab`:

```
backup /backup  virtiofs  defaults  0  0
```

5. I setup a backup cron job for my VM docker containers. This is all their configs and databases, but not the actual media:

```
0 5 * * 0 rsync -rvtzh --no-perms --no-owner --no-group /home/richard/media /backup/media_configs
```

## Crashes

Tweaks i'm making to the proxmox VM:

- Run this on the Proxmox host to allow more "time" for interrupts

```
sysctl -w kernel.perf_event_max_sample_rate=100000
```

- Disable "C-States" (Dell Stability Fix)

The poll_idle and cpuidle_enter mentions in your logs suggest the CPU is crashing while trying to transition between power-saving states.

    Action: In the Dell BIOS, go to Performance > C-States Control and uncheck the box to disable them. This is a common "silver bullet" for Dell micro-PCs running Proxmox that experience random freezes.

- Set ZFS pool limits on the proxmox host:

Create/Edit the config file:

```
vi /etc/modprobe.d/zfs.conf
```

Add the following line (Example for 4GB limit = `4 * 1024^3`):

```
options zfs zfs_arc_max=8589934592
```

Update the boot image:
This is the step most people miss. Since ZFS loads very early in the boot process, you must refresh the initramfs.

```
update-initramfs -u -k all
```

Reboot your Proxmox host.

- Set limits for containers which can take up a lot of memory (`qbittorrent`, `jellyfin`), as well as set the proxmox VM memory limit such that there is at least 2-4 GB of free RAM on the host. For example, I have 16GB host RAM, 6GB assigned to the media VM, 2 assigned to Immich, and 4 alloacted for the ZFS pool.
