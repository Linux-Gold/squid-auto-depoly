#!/bin/bash 
#this for quickly deployments on ubuntu 20.04
#Author Amos
#data 5/29/2023

# Check Ubuntu version
if [ "$(lsb_release -rs)" != "20.04" ]; then
  echo "This script is only compatible with Ubuntu 20.04."
  exit 1
fi

# Check if Squid is installed
if dpkg -s squid | grep -q "Status: install"; then
    echo "Squid is already installed. Uninstalling..."
    sudo apt-get purge -y squid > /dev/null 2>&1
fi

# Check if ufdbGuard is installed
if dpkg -s ufdbguard | grep -q "Status: install"; then
    echo "ufdbGuard is already installed. Uninstalling..."
    sudo apt-get purge -y ufdbguard > /dev/null 2>&1
fi

# Disable UFW
ufw disable > /dev/null 2>&1

# Change to the /tmp directory
cd /tmp/

# Download required packages
echo "Downloading packages..."
if [ -e ufdbguard_1.35.5-ubuntu20.04_amd64.deb ] && [ -e squid_4.10-1ubuntu1.4_amd64.deb ] && [ -e squid-common_4.10-1ubuntu1.4_all.deb ]; then
    echo "All packages already exist."
else
    wget https://www.urlfilterdb.com/files/downloads/ufdbguard_1.35.5-ubuntu20.04_amd64.deb 2> /dev/null
    wget https://launchpad.net/~ubuntu-security-proposed/+archive/ubuntu/ppa/+build/21654497/+files/squid_4.10-1ubuntu1.4_amd64.deb 2> /dev/null
    wget https://launchpad.net/~ubuntu-security-proposed/+archive/ubuntu/ppa/+build/21654497/+files/squid-common_4.10-1ubuntu1.4_all.deb 2> /dev/null
fi

# Install downloaded packages
echo "Installing packages..."
apt install --allow-downgrades ./ufdbguard_1.35.5-ubuntu20.04_amd64.deb ./squid_4.10-1ubuntu1.4_amd64.deb ./squid-common_4.10-1ubuntu1.4_all.deb -y > /dev/null 2>&1

if [ $? -eq 0 ]; then
  echo -e  "\033[32mInstallation Success.\033[0m"
else
  echo "Installation failed."
fi

# Download and extract blacklists
echo "Downloading and extracting blacklists..."
if [ -e blacklists.tar.gz ]; then
    echo "Download blacklists.tar.gz completed."
else
    curl -O ftp://ftp.ut-capitole.fr/pub/reseau/cache/squidguard_contrib/blacklists.tar.gz 2> /dev/null
fi

if [ $? -eq 0 ]; then
    echo "Download blacklists.tar.gz completed."
else
    echo -e "\e[1;31mDownload blacklist failed.\e[0m"
    exit 1
fi

tar -xzf blacklists.tar.gz -C /var/ufdbguard 2> /dev/null

# Create directories for blacklists
mkdir -p /var/ufdbguard/blacklists/{alwaysallow,alwaysdeny}
touch /var/ufdbguard/blacklists/alwaysallow/domains
touch /var/ufdbguard/blacklists/alwaysdeny/domains
ufdbConvertDB /var/ufdbguard/blacklists/ > /dev/null 2>&1

# Configure crontab
mkdir -p /opt/scripts/
touch /opt/scripts/update_blacklist_squid_ufdb.sh

cat << EOF > /opt/scripts/update_blacklist_squid_ufdb.sh
# Stop services
systemctl stop squid.service
systemctl stop ufdbguard.service

# Parse command line arguments
SKIP_CURL=false

while getopts "s" opt; do
  case $opt in
    s)
      SKIP_CURL=true
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# Update blacklist
if [ "$SKIP_CURL" = false ]; then
  curl -L "ftp://ftp.ut-capitole.fr/pub/reseau/cache/squidguard_contrib/blacklists.tar.gz" -o "/tmp/blacklists.tar.gz"
  tar -xzf /tmp/blacklists.tar.gz -C /var/ufdbguard
  rm -f /tmp/blacklists.tar.gz
fi

ufdbConvertDB /var/ufdbguard/blacklists/

# Update squid
rm -f /var/spool/squid/netdb.state
squid -z

# Update ubdbGuard
rm -f /tmp/ufdbguardd-03977
/usr/sbin/ufdbguardd -U ufdb -c /etc/ufdbGuard.conf

# Restart services
systemctl restart ufdbguard.service
systemctl restart squid.service

EOF
chmod +x /opt/scripts/update_blacklist_squid_ufdb.sh

# Add the task to crontab
echo "0 5 * * 7 /opt/scripts/update_blacklist_squid_ufdb.sh" >> mycron
crontab mycron
if [ $? -eq 0 ]; then
  echo -e  "\033[32mCreate crontab task Success.\033[0m"
else
  echo "\e[1;31mCreate crontab task failed.\e[0m"
fi
rm mycron


# Configure ufdbGuard
cat << EOF > /etc/ufdbGuard.conf
logdir "/var/ufdbguard/logs"
dbhome "/var/ufdbguard/blacklists"
logblock on
logpass on
logall on
squid-version "4.10"
squid-uses-active-bumping off
url-lookup-result-during-database-reload allow
url-lookup-result-when-fatal-error allow
ufdb-log-url-details on
ufdb-show-url-details on
check-proxy-tunnels log-only
safe-search off
lookup-reverse-ip off
use-ipv6-on-wan off
upload-crash-reports off
fast-refresh on
madvise-hugepages on
max-logfile-size  200000000
http-server { port = 8080, interface = all, images = /var/ufdbguard/images }
source allSystems {
   ipv4 10.0.0.0/8
}

#category alwaysallow {
#   domainlist        "alwaysallow/domains"
#   redirect          http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi?admin=%A&color=orange&size=normal&clientaddr=%a&clientname=%n&clientuser=%i&clientgroup=%s&category=%t&url=%u
#}

category alwaysdeny {
   domainlist        "alwaysdeny/domains"
   redirect          "http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi?admin=%A&color=orange&size=normal&clientaddr=%a&clientname=%n&clientuser=%i&clientgroup=%s&category=%t&url=%u"
}

#############
category adult {
   domainlist      "adult/domains"
   redirect "http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi?admin=%A&color=orange&size=normal&clientaddr=%a&clientname=%n&clientuser=%i&clientgroup=%s&category=%t&url=%u"
}

category violence {
   domainlist      "agressif/domains"
   redirect "http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi?admin=%A&color=orange&size=normal&clientaddr=%a&clientname=%n&clientuser=%i&clientgroup=%s&category=%t&url=%u"
}

category arjel {
   domainlist      "arjel/domains"
}

category associations_religieuses {
   domainlist      "associations_religieuses/domains"
   redirect "http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi?admin=%A&color=orange&size=normal&clientaddr=%a&clientname=%n&clientuser=%i&clientgroup=%s&category=%t&url=%u"
}

category astrology {
   domainlist      "astrology/domains"
}

category audio-video {
   domainlist      "audio-video/domains"
   redirect "http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi?admin=%A&color=orange&size=normal&clientaddr=%a&clientname=%n&clientuser=%i&clientgroup=%s&category=%t&url=%u"
}

category bitcoin {
   domainlist      "bitcoin/domains"
}

category ads {
   domainlist      "publicite/domains"
   redirect "http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi?admin=%A&mode=transparent&color=orange&size=normal&clientaddr=%a&clientname=%n&clientuser=%i&clientgroup=%s&category=%t&url=%u"
}

category celebrity {
   domainlist      "celebrity/domains"
}

category chat {
   domainlist      "chat/domains"
   redirect "http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi?admin=%A&color=orange&size=normal&clientaddr=%a&clientname=%n&clientuser=%i&clientgroup=%s&category=%t&url=%u"
}

category child {
   domainlist      "child/domains"
}

category cryptojacking {
   domainlist      "cryptojacking/domains"
}

category dangerous_material {
   domainlist      "dangerous_material/domains"
}

category dating {
   domainlist      "dating/domains"
   redirect "http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi?admin=%A&color=orange&size=normal&clientaddr=%a&clientname=%n&clientuser=%i&clientgroup=%s&category=%t&url=%u"
}

category ddos {
   domainlist      "ddos/domains"
}

category dialer {
   domainlist      "dialer/domains"
}

category download {
   domainlist      "download/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category educational_games {
   domainlist      "educational_games/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category exceptions_liste_bu {
   domainlist      "exceptions_liste_bu/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category filehosting {
   domainlist      "filehosting/domains"
}

category gambling {
   domainlist      "gambling/domains"
   redirect "http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi?admin=%A&color=orange&size=normal&clientaddr=%a&clientname=%n&clientuser=%i&clientgroup=%s&category=%t&url=%u"
}

category games {
   domainlist      "games/domains"
   redirect "http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi?admin=%A&color=orange&size=normal&clientaddr=%a&clientname=%n&clientuser=%i&clientgroup=%s&category=%t&url=%u"
}

category doh {
   domainlist      "doh/domains"
}

category hacking {
   domainlist      "hacking/domains"
}

category lingerie {
   domainlist      "lingerie/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category liste_blanche {
   domainlist      "liste_blanche/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category liste_bu {
   domainlist      "liste_bu/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category mail {
   domainlist      "forums/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category malware {
   domainlist      "malware/domains"
   redirect "http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi?admin=%A&color=orange&size=normal&clientaddr=%a&clientname=%n&clientuser=%i&clientgroup=%s&category=%t&url=%u"
}

category manga {
   domainlist      "manga/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category marketingware {
   domainlist      "marketingware/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category mixed_adult {
   domainlist      "mixed_adult/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category mobile-phone {
   domainlist      "mobile-phone/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category phishing {
   domainlist      "phishing/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category press {
   domainlist      "press/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category proxy {
   domainlist      "redirector/domains"
   redirect "http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi?admin=%A&color=orange&size=normal&clientaddr=%a&clientname=%n&clientuser=%i&clientgroup=%s&category=%t&url=%u"
}

category radio {
   domainlist      "radio/domains"
   redirect "http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi?admin=%A&color=orange&size=normal&clientaddr=%a&clientname=%n&clientuser=%i&clientgroup=%s&category=%t&url=%u"
}

category reaffected {
   domainlist      "reaffected/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category remote-control {
   domainlist      "remote-control/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category sect {
   domainlist      "sect/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category sexual_education {
   domainlist      "sexual_education/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category shortener {
   domainlist      "shortener/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category social_networks {
   domainlist      "social_networks/domains"
   redirect "http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi?admin=%A&color=orange&size=normal&clientaddr=%a&clientname=%n&clientuser=%i&clientgroup=%s&category=%t&url=%u"
}

category special {
   domainlist      "special/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category strict_redirector {
   domainlist      "strict_redirector/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category strong_redirector {
   domainlist      "strong_redirector/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category tricheur {
   domainlist      "tricheur/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category update {
   domainlist      "update/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category stalkerware {
   domainlist      "stalkerware/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi
}

category warez {
   domainlist      "warez/domains"
   redirect "http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi?admin=%A&color=orange&size=normal&clientaddr=%a&clientname=%n&clientuser=%i&clientgroup=%s&category=%t&url=%u"

}

category webmail {
   domainlist      "webmail/domains"
   redirect "http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi?admin=%A&color=orange&size=normal&clientaddr=%a&clientname=%n&clientuser=%i&clientgroup=%s&category=%t&url=%u"

}

category vpn {
   domainlist      "vpn/domains"
   redirect http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi

}
#############



acl {
   allSystems  {
      pass !alwaysdeny !adult !warez !ads !audio-video !dangerous_material !cryptojacking !violence !malware !phishing !cryptojacking !download !educational_games !filehosting !mixed_adult !proxy any
      redirect          "http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi?admin=%A&color=orange&size=normal&clientaddr=%a&clientname=%n&clientuser=%i&clientgroup=%s&category=%t&url=%u"
   }

   default {
      pass !alwaysdeny  any
      redirect          "http://cgibin.urlfilterdb.com/cgi-bin/URLblocked.cgi?admin=%A&color=orange&size=normal&clientaddr=%a&clientname=%n&clientuser=%i&clientgroup=%s&category=%t&url=%u"
  }
}

EOF

# Configure Squid
cat << EOF > /etc/squid/squid.conf
acl localnet src 10.0.0.0/8             # RFC 1918 local private network (LAN)

acl Safe_ports port 80          # http
acl Safe_ports port 443         # https

http_access deny !Safe_ports
http_access allow localhost manager
http_access deny manager
http_access allow localhost
http_access allow localnet
http_access deny all

http_port 3128 intercept
http_port 3127

cache_store_log daemon:/var/log/squid/store.log
coredump_dir /var/spool/squid

url_rewrite_program /usr/sbin/ufdbgclient -m 4 -l /var/log/squid/
url_rewrite_children 16 startup=8 idle=2 concurrency=4

refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern ^gopher:        1440    0%      1440
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .               0       20%     4320

wccp2_router 10.1.15.5 10.1.15.6
wccp2_forwarding_method gre
wccp2_return_method gre
wccp2_assignment_method hash

append_domain .resourcepro0.resourcepro.com
dns_nameservers 119.29.29.29 223.5.5.5
EOF

# Flush tunnel configuration
ip tunnel del line1 &> /dev/null
ip tunnel del line2 &> /dev/null

modprobe ip_gre

# Build the tunnel with Cisco ASA
ipv4_address=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
ip tunnel add line1 mode gre remote 222.173.121.34 local $ipv4_address dev eth0
ip tunnel add line2 mode gre remote 219.147.4.163 local $ipv4_address dev eth0

ip link set line1 up
ip link set line2 up

# kernel parameters
echo "1" > /proc/sys/net/ipv4/ip_forward
echo "0" > /proc/sys/net/ipv4/conf/default/rp_filter
echo "0" > /proc/sys/net/ipv4/conf/all/rp_filter
echo "0" > /proc/sys/net/ipv4/conf/eth0/rp_filter
echo "0" > /proc/sys/net/ipv4/conf/lo/rp_filter
echo "0" > /proc/sys/net/ipv4/conf/line1/rp_filte
echo "0" > /proc/sys/net/ipv4/conf/line2/rp_filter

# Flush iptables nat table
iptables -F -t nat

# Redirect all data from GRE tunnel to local port 3128
iptables -t nat -A PREROUTING -i line1 -p tcp -m tcp --dport 80 -j DNAT --to-destination $ipv4_address:3128
iptables -t nat -A PREROUTING -i line2 -p tcp -m tcp --dport 80 -j DNAT --to-destination $ipv4_address:3128


# Start services
echo "Stopping squid.service..."
systemctl stop squid.service
echo "Stopping ufdbguard.service..."
systemctl stop ufdbguard.service
rm -f /var/spool/squid/netdb.state
rm -f /tmp/ufdbguardd-*
echo "Starting ufdbguardd..."
/usr/sbin/ufdbguardd -U ufdb -c /etc/ufdbGuard.conf
echo "Restarting ufdbguard.service..."
systemctl restart ufdbguard.service
echo "Restarting squid.service..."
systemctl restart squid.service
if [ $? -eq 0 ]; then
    echo -e "\033[32mDeployment success!\033[0m"
fi
