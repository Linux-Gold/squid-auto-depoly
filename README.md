
# squid-auto-depoly
Quick deployment of squid and ufdbguard on ubuntu 20.04.

1、Switch to the /tmp directory and download the script auto_deploy_squid.sh.

    cd /tmp/ && wget -O /tmp/auto_deploy_squid.sh https://raw.githubusercontent.com/Linux-Gold/squid-auto-depoly/main/auto_deploy_squid.sh

2、Execute the script after giving execute permission to deploy it automatically.

    chmod +x auto_deploy_squid.sh && ./auto_deploy_squid.sh -q

