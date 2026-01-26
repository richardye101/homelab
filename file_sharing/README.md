# Samba Share

## Setup Proxmox and Samba LXC

This is how I've setup my samba share on proxmox.

Create a LXC in proxmox, i've done it on a debian image.

On the host, create a mount point from the host mnt of the disk to the LXC:

```
pct set 100 -mp0 /mnt/ssd500,mp=/data
```

Start the Samba LXC, and install samba:

```
apt update
apt install -y samba smbclient
```

Also install sudo and create a user:

```
apt install sudo
# go through the process to add the user
adduser sambauser

# set pid of sambauser to 0, just like the root
usermod -u 0 -o sambauser
```

Setup sambauser in samba:

```
# set sambauser password
smbpasswd -a sambauser
# enable sambauser
smbpasswd -e sambauser
```

Put this at the bottom of `/etc/samba/smb.conf`:

```
[Media]
   path = /data
   browseable = yes
   read only = no
   guest ok = no
   valid users = sambauser
   force user = sambauser
   force group = sambauser
   create mask = 0664
   directory mask = 0775
```

Which means `/mnt/ssd500` is the same as `/data` on the samba LXC.

Restart samba:

```
systemctl restart smbd nmbd
systemctl enable smbd
```

## Setup Samba in clients

In linux clients:

```
apt install -y cifs-utils
```

Create a file containing the sambauser creds that you created, and place it at `/root/.sambacredentials`:

```
username=sambauser
password=password
```

Place this in your `/etc/fstab`:

```
//SAMBA_IP/Media /data cifs credentials=/root/.sambacredentials,uid=1000,gid=1000,file_mode=0664,dir_mode=0775,vers=3.1.1,_netdev  0  0
```

Which links `/data` on the Samba LXC, which is referred to here as `/Media`, to `/data` on the Linux client.

# NFS and bind mount

So the samba share doesn't work very well because hardlinks through samba is the wrong pattern. It breaks videos. To get around this, i'll bind mount the drive to the media VM, while I NFS share the drive to other VMs as needed. The assumption is that other VMs won't need to create hardlinks.

On the proxmox host, create a user and group and assign to the correct PID/GID, and give it ownership over the mounted drive.

```
groupadd media
useradd -r -g media media
sudo usermod -u 1000 -o media
sudo groupmod -g 1000 -o media
sudo usermod -aG media media
chown -R media:media /mnt/ssd500
chmod -R 775 /mnt/ssd500
find /mnt/ssd 500 -type d -exec chmod g+s {} +
```

Set the VM permissions:

```
qm set 101 -mp0 /mnt/ssd500,mp=/data
```

## ZFS

A ZFS pool is a way to organize storage disks as one filesystem. This is a very common thing to do in homelabs. I'm creating a ZFS pool with a single drive for now:

```
zpool create -f -o ashift=12 sharedpool /dev/sdb
zfs create sharedpool/nfs
zfs set atime=off sharedpool/nfs   # optional, disables access-time updates
zfs set compression=lz4 sharedpool/nfs
# Set record size for typical workloads (optional, e.g., media files):
zfs set recordsize=1M sharedpool/nfs
```

Give permissions to the user:

```
chown -R media:media /sharedpool/nfs
chmod -R 775 /sharedpool/nfs
```

I've encountered issues where my VM crashes, and this may help. On the host, we want to set ARC limits reasonably

```
echo 6442450944 > /sys/module/zfs/parameters/zfs_arc_max
echo 3221225472 > /sys/module/zfs/parameters/zfs_arc_min
```

Edit the following file with these values:

```
nano /etc/modprobe.d/zfs.conf
```

```
options zfs zfs_arc_max=6442450944
options zfs zfs_arc_min=3221225472
```

### Removing ZFS pools

```
# Find the pool to remove
zpool list
sudo zpool destroy poolname

lsblk
# Do this for every partition
sudo zpool labelclear -f /dev/sdX1
sudo wipefs -a /dev/sdX
```

Create a new partition for ext4

```
sudo parted /dev/sdX --script mklabel gpt
sudo parted /dev/sdX --script mkpart primary ext4 0% 100%
sudo mkfs.ext4 /dev/sdX1
```

Test by mounting the new drive partition:

```
sudo mount /dev/sdX1 /mnt/external
df -h | grep sdX
```

## NFS Share

```
apt update
apt install nfs-kernel-server -y
echo "/sharedpool/nfs 10.88.111.0/24(rw,sync,no_subtree_check,no_root_squash)" > /etc/exports
```

Apply the export:

```
exportfs -ra
systemctl restart nfs-kernel-server

# check export
exportfs -v
```

## NFS Client

Setup the NFS share on the client, place this in the `/etc/fstab`:

```
192.168.1.100:/sharedpool/nfs  /mnt/shared nfs4 rw,hard,intr,noatime,nolock,nofail,x-systemd.automount 0 0
```

Then run:

```
sudo systemctl daemon-reload
sudo mount -a
```
