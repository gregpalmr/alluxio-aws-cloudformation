#!/bin/bash
#
# SCRIPT: install-prometheus-node-exporter.sh
#

  # Install Prometheus node_exporter for basic mem, cpu, disk, network stats
  yum -y install wget
  wget https://github.com/prometheus/node_exporter/releases/download/v1.3.1/node_exporter-1.3.1.linux-amd64.tar.gz
  tar xvf node_exporter-1.3.1.linux-amd64.tar.gz
  cp node_exporter-1.3.1.linux-amd64/node_exporter /usr/local/bin/
  rm -rf node_exporter-1.3.1.linux-amd64 node_exporter-1.3.1.linux-amd64.tar.gz

  # Setup systemd service
  cat <<EOF > /etc/systemd/system/prometheus-node-exporter.service
  [Unit]
  Description=prometheus-node-exporter
  Documentation=https://github.com/prometheus/node_exporter
  Wants=network-online.target
  After=network-online.target

  [Service]
  Type=simple
  User=root
  Group=root
  ExecStart=/usr/local/bin/node_exporter
  SyslogIdentifier=prometheus-node-exporter
  Restart=always

  [Install]
  WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl start prometheus-node-exporter
  systemctl enable prometheus-node-exporter

# End of script
