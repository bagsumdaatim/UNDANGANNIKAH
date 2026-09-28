#!/bin/bash
set -u

MNT="/mnt/win"
SAM_REL="Windows/System32/config/SAM"
MOUNTED_BY_US=0

echo "=== Windows Administrator Password Reset ==="

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: jalankan sebagai root."
    exit 1
fi

mkdir -p "$MNT"

if [ -f "$MNT/$SAM_REL" ]; then
    echo "[OK] Windows sudah ter-mount di $MNT"
else
    echo "[1/4] Install tool..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y ntfs-3g chntpw

    echo "[2/4] Mencari partisi Windows..."
    FOUND=""

    while read -r PART FSTYPE TYPE; do
        [ -z "${PART:-}" ] && continue
        [ "$TYPE" = "part" ] || continue
        [ "$FSTYPE" = "ntfs" ] || continue

        umount "$MNT" 2>/dev/null || true

        echo "    Mencoba $PART ..."
        if mount -t ntfs-3g -o rw "$PART" "$MNT" 2>/dev/null; then
            if [ -f "$MNT/$SAM_REL" ]; then
                FOUND="$PART"
                MOUNTED_BY_US=1
                break
            fi
            umount "$MNT" 2>/dev/null || true
        fi
    done < <(lsblk -pnlo NAME,FSTYPE,TYPE)

    if [ -z "$FOUND" ]; then
        echo "ERROR: partisi Windows tidak ditemukan/tidak bisa di-mount."
        exit 1
    fi

    echo "[OK] Windows ditemukan di $FOUND"
fi

SAM="$MNT/$SAM_REL"

if [ ! -f "$SAM" ]; then
    echo "ERROR: SAM tidak ditemukan: $SAM"
    [ "$MOUNTED_BY_US" -eq 1 ] && umount "$MNT" 2>/dev/null || true
    exit 1
fi

echo "[3/4] Backup SAM..."
BACKUP="${SAM}.backup-$(date +%Y%m%d-%H%M%S)"
cp -a "$SAM" "$BACKUP"
echo "[OK] $BACKUP"

echo "[4/4] Mengosongkan password Administrator..."
printf "1
q
y
" | chntpw -u Administrator "$SAM"
RC=$?

if [ "$RC" -ne 0 ]; then
    echo "ERROR: chntpw gagal (kode $RC)."
    [ "$MOUNTED_BY_US" -eq 1 ] && umount "$MNT" 2>/dev/null || true
    exit 1
fi

sync
[ "$MOUNTED_BY_US" -eq 1 ] && umount "$MNT" 2>/dev/null || true

echo
echo "=== SELESAI ==="
echo "Password Administrator sudah dikosongkan."
echo "Boot kembali ke Local Disk lalu reboot."
echo "Setelah masuk Windows, buat password baru dengan:"
echo "net user Administrator *"
