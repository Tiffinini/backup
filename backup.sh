#!/bin/bash
BACKUP_TO_SERVER=192.168.122.162
BACKUP_REMOTE_SERVER_USER=backup_user
BACKUP_TO_DIR=wiki_backup

BACKUP_FROM_DIR=/root/bookstack_new/vol_data
ENCRYPTED_LOCAL_MOUNTPOINT=/mnt/ro_enc_bookstack
LOCAL_KEYFILE=/root/wikibackup.key

WEBHOOK_URL="https://discord.com/api/webhooks/1303680827246514188/CGdw1RBoQgH0Os9Hgv-h6Vk1nOl8CnB9wTELHANnZAg7auA7OQ4e_7-RtiyGxnI06a48"

CRYPT_COMMAND="gocryptfs --ro --one-file-system --reverse --passfile $LOCAL_KEYFILE"
SYNC_COMMAND="rsync -P -a -z --delete --numeric-ids --rsync-path='sudo rsync'"

check_mountpoint_empty() {
	if [ -z "$(ls -A $ENCRYPTED_LOCAL_MOUNTPOINT)" ]; then
		return 0
	else
		return 1
	fi
}

check_bin() {
	# Args:
	# 	$1 = Name of binary to check.
	if [ ! -z "$(which $1)" ]; then
		return 0
	else
		return 1
	fi
}

cleanup() {
	fusermount -u $ENCRYPTED_LOCAL_MOUNTPOINT
	rm -rf $ENCRYPTED_LOCAL_MOUNTPOINT
}

post_to_webhook() {
	# Args:
	# 	$1 = Message to send.
	if [ -n "$WEBHOOK_URL" ]; then
		curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST --data "{\"content\": \"💾 ⋆⋆ **BACKUP** ⋆⋆ $1\"}" $WEBHOOK_URL
	fi
}

# Ensure required binaries are present.
if ! check_bin rsync; then
	echo "Error: rsync is not installed."
	exit 1
fi

if ! check_bin gocryptfs; then
	echo "Error: gocryptfs is not installed."
	exit 1
fi

if ! check_bin fusermount; then
	echo "Error: fuse is not installed."
	exit 1
fi

# Mount an encrypted version of the filesystem to be backed up.
# Check to ensure the directory to be backed up is initilized for gocryptfs.
if [ ! -f "$BACKUP_FROM_DIR/.gocryptfs.reverse.conf" ]; then
	echo "Error: gocryptfs isn't initilized for the target backup directory."
	echo "Run this command in order to initilize it:"
	echo "gocryptfs --reverse --init $BACKUP_FROM_DIR"
	echo "Then add the decryption password to the keyfile at: $LOCAL_KEYFILE"
	exit 1
fi

if [ ! -f "$LOCAL_KEYFILE" ]; then
	echo "Error: Couldn't find keyfile required for directory encryption."
	echo "Place keyfile with encryption key at $LOCAL_KEYFILE"
	exit 1
fi

# Check to ensure the target to mount the encrypted view is empty.
mkdir -p $ENCRYPTED_LOCAL_MOUNTPOINT

if ! check_mountpoint_empty; then
	echo "The target to mount the encrypted view, $ENCRYPTED_LOCAL_MOUNTPOINT, is not empty!"
	echo "Attempting to fix by unmounting..."

	cleanup

	if ! check_mountpoint_empty; then
		echo "$ENCRYPTED_LOCAL_MOUNTPOINT is still not empty after attempting to fix."
		echo "Manual intervention required. Aborting."
		post_to_webhook ":warning: ERROR: Encrypted mountpoint $ENCRYPTED_LOCAL_MOUNTPOINT wasn't empty and couldn't fix! Backup aborted!"
		exit 1
	fi

	echo "Fix succeeded! Ready to mount."
fi

if $CRYPT_COMMAND $BACKUP_FROM_DIR $ENCRYPTED_LOCAL_MOUNTPOINT; then
	echo "Encrypted mount succeeded!"
	echo "Encrypted view of $BACKUP_FROM_DIR is available at $ENCRYPTED_LOCAL_MOUNTPOINT"
else
	echo "Encrypted mount failed."
	post_to_webhook ":warning: ERROR: Mounting encrypted copy of $BACKUP_FROM_DIR failed! Backup aborted!"
	exit 1
fi

# Here we'll perform the backup sync.
post_to_webhook "⏳ Starting encrypted backup of Wiki data..."

while true; do
	if eval "$SYNC_COMMAND $ENCRYPTED_LOCAL_MOUNTPOINT/ $BACKUP_REMOTE_SERVER_USER@$BACKUP_TO_SERVER:$BACKUP_TO_DIR"; then
		echo "Backup succeeded!"
		break
	fi

	sleep 30
done

cleanup
post_to_webhook "✅ Backup of Wiki data succeeded to: \`$BACKUP_REMOTE_SERVER_USER@$BACKUP_TO_SERVER:$BACKUP_TO_DIR\`"

