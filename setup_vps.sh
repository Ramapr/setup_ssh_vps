#!/bin/bash
# Безопасная настройка SSH + UFW + Fail2Ban

SSH_PORT=2222          # Новый порт SSH
VPN_PORT=1194          # Порт OpenVPN
VPN_PROTO=udp          # Протокол OpenVPN (udp или tcp)
# add admin panel
FINALIZE=false         # По умолчанию не отключаем порт 22

# Проверка root
if [[ $EUID -ne 0 ]]; then
   echo "Запусти скрипт от root: sudo $0"
   exit 1
fi

# Проверка аргументов
if [[ "$1" == "--finalize" ]]; then
  FINALIZE=true
  echo "⚠️ Режим финализации: порт 22 будет отключён!"
fi

echo "[1/6] Устанавливаем пакеты..."
apt update && apt install -y ufw fail2ban

echo "[2/6] Настройка SSH..."
# Добавляем новый порт параллельно
if ! grep -q "Port $SSH_PORT" /etc/ssh/sshd_config; then
    echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
fi

# Если финализация, то удаляем Port 22
if $FINALIZE; then
    sed -i '/^Port 22/d' /etc/ssh/sshd_config
    echo "Удалили порт 22 из sshd_config"
fi

systemctl restart ssh

echo "[3/6] Настройка UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp        # пока оставляем стандартный порт
ufw allow $SSH_PORT/tcp
ufw allow $VPN_PORT/$VPN_PROTO
ufw --force enable

# Если финализация, то убираем 22
if $FINALIZE; then
    ufw delete allow 22/tcp
    echo "Порт 22 удалён из UFW"
fi

echo "[4/6] Настройка Fail2Ban..."
cat >/etc/fail2ban/jail.local <<EOL
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = systemd

[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 5

[openvpn]
enabled = true
port = $VPN_PORT
protocol = $VPN_PROTO
filter = openvpn
logpath = /var/log/openvpn*.log
maxretry = 5
EOL

systemctl enable fail2ban
systemctl restart fail2ban

echo "[5/6] Проверка статуса..."
ufw status verbose
fail2ban-client status sshd

echo "[6/6] Завершение..."
if $FINALIZE; then
    echo "✅ Настройка завершена. SSH доступен только на порту $SSH_PORT"
else
    echo "⚠️ Внимание! SSH сейчас доступен на портах 22 и $SSH_PORT."
    echo "Попробуй подключиться: ssh -p $SSH_PORT user@IP"
    echo "Если всё работает — запусти повторно: sudo $0 --finalize"
fi
