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
