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

echo "[1/8] Устанавливаем пакеты..."
apt update && apt install -y ufw fail2ban

echo "[2/8] Настройка SSH..."
# Сделать резервное копирование
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%F_%T)
# Добавляем новый порт параллельно
if ! grep -q "Port $SSH_PORT" /etc/ssh/sshd_config; then
    echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
fi

# Если финализация, то удаляем Port 22
if $FINALIZE; then
    sed -i '/^Port 22/d' /etc/ssh/sshd_config
    echo "Удалили порт 22 из sshd_config"
    ufw delete allow 22/tcp
    echo "Порт 22 удалён из UFW"
    echo "✅ Настройка завершена. SSH доступен только на порту $SSH_PORT"
    echo "- OpenVPN доступен на $VPN_PORT/$VPN_PROTO"
    echo "- Панель OpenVPN Admin UI доступна на 943/tcp"
    echo "- Панель OpenVPN Web Client доступна на 9443/tcp"
    exit 0
fi

sshd -t || { echo "Ошибка в sshd_config, исправь перед продолжением"; exit 1; }
systemctl restart ssh

echo "[3/8] Настройка UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp        # пока оставляем стандартный порт
ufw allow $SSH_PORT/tcp
ufw allow $VPN_PORT/$VPN_PROTO
# OpenVPN Access Server admin UI
ufw allow 943/tcp       # Web Admin UI OpenVPN
ufw allow 9443/tcp      # Web Client UI OpenVPN
ufw --force enable

echo "[4/8] Настройка Fail2Ban..."
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

[openvpnas-admin]
enabled = true
port = 943
protocol = tcp
filter = openvpnas
logpath = /var/log/openvpnas.log
maxretry = 5

[openvpnas-web]
enabled = true
port = 9443
protocol = tcp
filter = openvpnas
logpath = /var/log/openvpnas.log
maxretry = 5
EOL

systemctl enable fail2ban
# systemctl restart fail2ban

echo "[5/8] Проверка статуса..."
ufw status verbose
fail2ban-client status sshd

echo "[6/8] Создание фильтра Fail2Ban для OpenVPN Admin UI..."
cat >/etc/fail2ban/filter.d/openvpnas.conf <<'EOL'
[Definition]
failregex = ^.*web_login.*LOGIN FAILED.*username=.*<HOST>.*$
ignoreregex =
EOL

echo "[7/8] Перезапуск Fail2Ban..."
systemctl restart fail2ban

echo "[8/8] Завершение..."
echo "⚠️ Внимание! SSH сейчас доступен на портах 22 и $SSH_PORT."
echo "- OpenVPN доступен на $VPN_PORT/$VPN_PROTO"
echo "- Панель OpenVPN Admin UI доступна на 943/tcp"
echo "- Панель OpenVPN Web Client доступна на 9443/tcp"
echo ""
echo "Попробуй подключиться по новому SSH: ssh -p $SSH_PORT user@IP"
echo "Если всё работает — запусти повторно: sudo $0 --finalize"
