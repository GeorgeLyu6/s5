#!/usr/bin/env bash
# =============================================================================
# 一键部署 Dante SOCKS5 代理脚本 (Debian/Ubuntu)
#
# 用法：
#   sudo bash install_socks5.sh
#
# 功能：
#   1. 安装 dante-server
#   2. 创建代理用户 proxyuser
#   3. 生成并部署 /etc/danted.conf
#   4. 配置 UFW 或 iptables 防火墙开放 1080 端口
#   5. 启动并开启开机自启 danted 服务
# =============================================================================

set -e

# -- 配置项（可根据需要修改）
SOCKS_PORT=1080
PROXY_USER="proxyuser"
PROXY_PASS="changeme"         # 安全起见，运行后请手动改密码
UNPRIV_USER="nobody"
INTERNAL_IF="0.0.0.0"         # 监听所有地址
EXTERNAL_IF="eth0"            # 外网网卡名称，可用 `ip addr` 查看

# 检查是否 root
if [[ $EUID -ne 0 ]]; then
  echo "请以 root 用户或 sudo 权限运行此脚本"
  exit 1
fi

echo "=== 更新系统并安装 dante-server ==="
apt update
apt install -y dante-server

echo "=== 创建代理用户：${PROXY_USER} ==="
id -u $PROXY_USER &>/dev/null || \
  useradd -M -s /usr/sbin/nologin $PROXY_USER
echo "${PROXY_PASS}" | passwd --stdin $PROXY_USER 2>/dev/null || \
  echo -e "${PROXY_PASS}\n${PROXY_PASS}" | passwd $PROXY_USER

echo "=== 生成 Dante 配置 /etc/danted.conf ==="
cat >/etc/danted.conf <<EOF
# Dante SOCKS5 代理配置
internal: ${INTERNAL_IF} port = ${SOCKS_PORT}
external: ${EXTERNAL_IF}

# 认证方式：用户名/密码
method: username

# 特权/非特权用户
user.privileged: root
user.notprivileged: ${UNPRIV_USER}
user.libwrap: ${UNPRIV_USER}

# 客户端访问控制
client pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  log: connect error
}

# 转发规则
pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  protocol: tcp udp
  log: connect error
}
EOF

echo "=== 配置防火墙，开放端口 ${SOCKS_PORT} ==="
if command -v ufw &>/dev/null; then
  ufw allow ${SOCKS_PORT}/tcp
else
  iptables -I INPUT -p tcp --dport ${SOCKS_PORT} -j ACCEPT
  # 持久化 iptables（Debian/Ubuntu）
  apt install -y iptables-persistent
  netfilter-persistent save
fi

echo "=== 启动并开启 danted 服务 ==="
systemctl restart danted
systemctl enable danted

echo "=== 部署完成 ==="
echo "请使用以下信息登录 SOCKS5："
echo "  IP: 服务器公网 IP"
echo "  Port: ${SOCKS_PORT}"
echo "  Username: ${PROXY_USER}"
echo "  Password: ${PROXY_PASS}"
echo
echo "建议：首次登录后请立即运行 'passwd ${PROXY_USER}' 修改默认密码。"
