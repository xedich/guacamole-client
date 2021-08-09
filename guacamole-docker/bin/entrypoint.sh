#!/usr/bin/env bash
sudo --preserve-env -u guacamole bash -c "export HOME=/home/guacamole && export PATH=\"$PATH:$TOMCAT_HOME/bin\" && /opt/guacamole/bin/start.sh &"

sudo --preserve-env -u guacd bash -c "export LD_LIBRARY_PATH=/usr/local/guacamole/lib && /usr/local/guacamole/sbin/guacd -b 0.0.0.0 -L $GUACD_LOG_LEVEL -f"
