#!/bin/bash
#
# Install noVNC components for Abiquo.
#
PROXY_PORT=

usage () {
cat << EOF

    This script installs necessary components to replace Abiquo\'s
    tighvnc viewer with noVNC.


    $0 options:

        -w : Will install noVNC proxy.
        -l : Port where the proxy will listen (mandatory if -w is provided).
        -a : Abiquo API URI (mandatory if -w is provided).
        -u : Abiquo API user (mandatory if -w is provided).
        -p : Abiquo API pass (mandatory if -w is provided).
        -c : Server certificate for the proxy (mandatory if -w is provided).
        -k : Private key file for the certificate (mandatory if -w is provided).

        -i : Address to the noVNC proxy (ADDRESS:PORT)

EOF
}

download_websockify () {
  # Download websockify
  destdir=$(mktemp -d)
  wget http://github.com/kanaka/noVNC/tarball/v0.5.1 \
    -O $destdir/novnc-master.tar.gz
  cd $destdir
  tar xf novnc-master.tar.gz
  mv kanaka-noVNC-* $1
}

install_proxy () {
  proxy_port=${1:-41337}

  # Proxy dependencies
  echo 'Installing proxy dependencies...'
  yum -y install epel-release # python-pip is in epel-release repository
  yum -y install python-pip python-devel openssl-devel ruby rubygems \
    ruby-devel make gcc libxml2 libxml2-devel libxslt libxslt-devel wget
  pip install numpy
  gem install --no-ri --no-rdoc mime-types -v '1.25'
  gem install --no-ri --no-rdoc rest-client -v '1.6.8'
  gem install --no-ri --no-rdoc nokogiri -v '1.5.10'
  echo "Done installing dependencies."

  echo "Setting up noVNC proxy."

  # Download websockify
  destdir=$(mktemp -d)
  wget http://github.com/kanaka/websockify/tarball/master \
    -O $destdir/websockify-master.tar.gz
  cd $destdir
  tar xf websockify-master.tar.gz
  mv kanaka-websockify-* /opt/websockify

  # Websockify service autostart
  if [ -z "$PROXY_CERT" ]; then
    wget https://raw.githubusercontent.com/abiquo/noVNC/master/websockify \
      -O /etc/init.d/websockify
  else
    wget https://raw.githubusercontent.com/abiquo/noVNC/master/websockify-ssl \
      -O /etc/init.d/websockify

    # Replace cert info
    sed -i s:CERT_FILE=.*:CERT_FILE=${PROXY_CERT}:g \
      /etc/init.d/websockify
    sed -i s:KEY_FILE=.*:KEY_FILE=${PROXY_KEY}:g \
      /etc/init.d/websockify
  fi
  sed -i s/WEBSOCKIFY_PORT=41337/WEBSOCKIFY_PORT=${proxy_port}/g \
    /etc/init.d/websockify
  sed -i s:WEBSOCKIFY=.*/websockify:WEBSOCKIFY=\\\$BINDIR/websockify.py:g \
    /etc/init.d/websockify
  chmod +x /etc/init.d/websockify
  chkconfig websockify on

  # noVNC tokens script
  wget https://raw.githubusercontent.com/abiquo/noVNC/master/novnc_tokens.rb \
    -O /opt/websockify/novnc_tokens.rb
  chmod +x /opt/websockify/novnc_tokens.rb

  # Set up cron for tokens.
  cat << EOF > /etc/cron.d/novnc_tokens
# VNC Proxy (set to run every minute in the example)
* * * * * root /opt/websockify/novnc_tokens.rb -a ${ABIQUO_API_URL} -u ${ABIQUO_API_USER} -p ${ABIQUO_API_PASS} -f /opt/websockify/config.vnc
EOF

  service websockify start
}

#
# Replaces tightvnc viewer with noVNC in Abiquo UI
#
setup_ui () {
  # Download websockify
  cd /var/www/html/ui/lib/remoteaccess/
  mv tightvnc tightvnc.old

  # Download websockify
  destdir=$(mktemp -d)
  wget http://github.com/kanaka/noVNC/tarball/v0.5.1 \
    -O $destdir/novnc-master.tar.gz
  cd $destdir
  tar xf novnc-master.tar.gz
  mv kanaka-noVNC-* /var/www/html/ui/lib/remoteaccess/tightvnc

  # Customize files
  destdir=$(mktemp -d)
  wget http://github.com/abiquo/noVNC/tarball/master \
    -O $destdir/abiquo-novnc-files.tar.gz
  cd $destdir
  tar xf abiquo-novnc-files.tar.gz
  cd abiquo-noVNC-*
  mv tightvnc.html /var/www/html/ui/lib/remoteaccess/tightvnc/tightvnc.html
  mv *.js /var/www/html/ui/lib/remoteaccess/tightvnc/include/

  # Replace host and port values for proxy
  proxy_address=$(echo $PROXY_IP | cut -d':' -f1)
  proxy_port=$(echo $PROXY_IP | cut -d':' -f2)
  sed -i s/host\ =.*$/host\ =\ \"${proxy_address}\"/g \
    /var/www/html/ui/lib/remoteaccess/tightvnc/tightvnc.html
  sed -i s/port\ =.*$/port\ =\ ${proxy_port}/g \
    /var/www/html/ui/lib/remoteaccess/tightvnc/tightvnc.html
}

options='wl:a:u:p:i:c:k:h'
while getopts $options option
do
    case $option in
        w  ) PROXY=true;;
        a  ) ABIQUO_API_URL=$OPTARG;;
        u  ) ABIQUO_API_USER=$OPTARG;;
        p  ) ABIQUO_API_PASS=$OPTARG;;
        c  ) PROXY_CERT=$OPTARG;;
        k  ) PROXY_KEY=$OPTARG;;
        i  ) PROXY_IP=$OPTARG;;
        l  ) PROXY_PORT=$OPTARG;;
        h  ) usage; exit 1;;
        *  ) usage; exit 1;;
    esac
done

if [ $OPTIND -eq 1 ]; then
  usage
  exit 1
fi

if [ "$PROXY" == true ]; then
  install_proxy $PROXY_PORT
else
  rpm -qa | grep -q abiquo-ui
  if [ "$?" -eq 0 ]; then
    setup_ui
  else
    echo "Abiquo UI package is not installed. Quitting."
    exit 1
  fi
fi
