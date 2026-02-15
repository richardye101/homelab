# Setup

1. Ensure file sharing is setup on the host, in `/file_sharing`.
2. For immich, setup using the [community script](https://community-scripts.github.io/ProxmoxVE/scripts?id=immich):

```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/immich.sh)"
```

> I turned OpenVino off, and listed cifs, nfs in the allowed mount types during install.

3. Once setup, ssh into the LXC run this to get the user id and group id:

```
getent passwd | grep immich
```

Say it shows:

```
immich:x:999:991::/opt/immich:/usr/sbin/nologin
```

Then on the proxmox host, the PID and GID are `100999` and `100991`

4. On the proxmox host, create and set the file permissions for the new ZFS share (Assuming ZFS is already setup):

```
groupadd immich
useradd -r -g immich immich
sudo usermod -u 100999 -o immich
sudo groupmod -g 100991 -o immich
sudo usermod -aG immich immich

zfs create sharedpool/immich
zfs set atime=off sharedpool/immich # optional, disables access-time updates
zfs set compression=lz4 sharedpool/immich
# Set record size for typical workloads (optional, e.g., media files):
zfs set recordsize=1M sharedpool/immich

chown -R immich:immich /sharedpool/immich
chmod -R 775 /sharedpool/immich
find /sharedpool/immich -type d -exec chmod g+s {} +
```

5. Set the mount point for the immich LXC on the host, replacing <CTID> with the ID of the LXC on proxmox:

```
pct set <CTID> --mp0 /sharedpool/immich,mp=/data
```

6. In the immich LXC, replace the upload location with the following.
   Use this command: `vi /opt/immich/.env`

```
IMMICH_MEDIA_LOCATION=/data/upload
```

7. Update the symlinks:

```
mv /opt/immich/app/upload /opt/immich/app/upload-orig
ln -s /data/upload /opt/immich/app/upload
chown -R immich:immich /opt/immich/app/upload

mv /opt/immich/app/machine-learning/upload /opt/immich/app/machine-learning/upload-orig
ln -s /data/upload /opt/immich/app/machine-learning/upload
chown -R immich:immich /opt/immich/app/machine-learning/upload
```
