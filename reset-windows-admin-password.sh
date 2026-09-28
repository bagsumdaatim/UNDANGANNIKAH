#!/bin/bash
# Reset the local Windows Administrator password to:
# bola121Gila
#
# For the DigitalOcean Ubuntu-based Recovery Console.
# Current known Windows OS partition: /dev/vda2

set -e

MNT="/mnt/win"
WINPART="/dev/vda2"
SAM="$MNT/Windows/System32/config/SAM"
PASSWORD="bola121Gila"

echo "=== Windows Administrator Password Reset ==="

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: jalankan sebagai root."
    exit 1
fi

mkdir -p "$MNT"

echo "[1/5] Memastikan tool tersedia..."
if ! command -v ntfs-3g >/dev/null 2>&1 || ! command -v chntpw >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq || true
    apt-get install -y ntfs-3g chntpw
fi

if [ ! -b "$WINPART" ]; then
    echo "ERROR: $WINPART tidak ditemukan."
    exit 1
fi

echo "[2/5] Mounting Windows..."
umount "$MNT" 2>/dev/null || true

if ! mount -t ntfs-3g -o rw "$WINPART" "$MNT"; then
    echo "ERROR: gagal mount $WINPART."
    echo "Pastikan Windows tidak dalam kondisi hibernasi/dirty."
    exit 1
fi

if [ ! -f "$SAM" ]; then
    echo "ERROR: SAM tidak ditemukan di:"
    echo "$SAM"
    umount "$MNT" 2>/dev/null || true
    exit 1
fi

echo "[3/5] Membuat backup SAM..."
BACKUP="${SAM}.backup-$(date +%Y%m%d-%H%M%S)"
cp -a "$SAM" "$BACKUP"
echo "[OK] Backup: $BACKUP"

echo "[4/5] Mengatur password Administrator menjadi: $PASSWORD"
echo
echo "PENTING: chntpw hanya dapat mengubah ke password baru jika"
echo "akun memiliki password/hash yang masih tersedia. Jika akun sudah"
echo "blank, tool ini biasanya hanya dapat melakukan CLEAR, bukan SET."
echo

# This version of chntpw uses menu-driven password editing.
# Sequence: 2 = set new password, enter password, q = quit, y = save.
# Use RID 0x1f4 for the built-in Administrator.
LOG="/tmp/chntpw-reset.log"

set +e
printf "2\n%s\nq\ny\n" "$PASSWORD" | chntpw -u 0x1f4 "$SAM" 2>&1 | tee "$LOG"
RC=${PIPESTATUS[1]}
set -e

if [ "$RC" -ne 0 ]; then
    echo
    echo "ERROR: chntpw gagal (kode $RC)."
    echo "Backup SAM: $BACKUP"
    exit 1
fi

if grep -qiE 'Sorry, unable to edit since password seems blank|No change' "$LOG"; then
    echo
    echo "ERROR: akun Administrator sudah BLANK."
    echo "Pada versi chntpw ini, password blank tidak dapat langsung"
    echo "diganti menjadi password baru secara offline."
    echo
    echo "Solusi: boot Windows, login Administrator, lalu jalankan:"
    echo "  net user Administrator $PASSWORD"
    echo
    echo "Backup SAM tetap aman di:"
    echo "$BACKUP"
    exit 2
fi

if ! grep -qiE 'password changed|Password.*changed|new password|SAM.*OK|OK' "$LOG"; then
    echo
    echo "PERINGATAN: chntpw tidak memberikan konfirmasi perubahan yang jelas."
    echo "Periksa log: $LOG"
    echo "Backup SAM: $BACKUP"
    exit 3
fi

echo "[5/5] Menyimpan perubahan..."
sync
umount "$MNT"

echo
echo "=== SELESAI ==="
echo "Administrator sekarang diarahkan ke password: $PASSWORD"
echo "Kembalikan boot DigitalOcean ke Local Disk lalu reboot."
echo "Untuk RDP gunakan username: .\Administrator"
