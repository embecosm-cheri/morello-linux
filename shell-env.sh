#!/usr/bin/env sh

# Init the container
if [[ -z $(getent passwd $UID) ]]; then
  # Create user/group and assign /morello permission
  groupadd -g $GID $GID
  useradd -u $UID -g $GID -s /bin/bash $UID

  USER_PASSWORD="morello"
  echo $UID:$USER_PASSWORD | chpasswd
fi

# Chmod /morello and change user
chown $UID:$GID /morello

# Run bash to keep container alive
tail -f /dev/null