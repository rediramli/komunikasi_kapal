#!/usr/bin/env bash
# setup-ssh-key.sh - sekali saja: pasang SSH key REDLAB ke RPi OMR & VPS supaya run.sh tanpa password.
# Akan meminta password root RPi lalu password root VPS (diketik oleh Anda, tidak disimpan).
set -e
KEY=~/.ssh/id_ed25519
[ -f $KEY ] || ssh-keygen -t ed25519 -N '' -f $KEY -C "redlab-testbed"
PUB=$(cat $KEY.pub)
echo "== RPi OMR: masukkan password root RPi"
ssh -o ConnectTimeout=10 root@100.102.109.59 "touch /etc/dropbear/authorized_keys; grep -qF '$PUB' /etc/dropbear/authorized_keys || echo '$PUB' >> /etc/dropbear/authorized_keys; chmod 600 /etc/dropbear/authorized_keys"
echo "== VPS: masukkan password root VPS"
ssh -o ConnectTimeout=10 -p 65222 root@168.144.105.155 "mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; grep -qF '$PUB' ~/.ssh/authorized_keys || echo '$PUB' >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys"
echo "== Tes tanpa password:"
ssh -o BatchMode=yes root@100.102.109.59 'echo "  RPi OK"'
ssh -o BatchMode=yes -p 65222 root@168.144.105.155 'echo "  VPS OK"'
