#!/bin/bash
#
# SCRIPT: install-prometheus.sh
#

  # Install Prometheus
  groupadd --system prometheus
  useradd -s /sbin/nologin --system -g prometheus prometheus
  curl -L -O https://github.com/prometheus/prometheus/releases/download/v2.36.0/prometheus-2.36.0.linux-amd64.tar.gz
  tar xvf prometheus-*.tar.gz
  cd prometheus-*.linux-amd64/
  mv prometheus promtool /usr/local/bin/
  mkdir -p /etc/prometheus
  mv prometheus.yml  /etc/prometheus/prometheus.yml.template
  mv consoles/ console_libraries/ /etc/prometheus/
  cd ..
  rm -rf prometheus-*

  cat <<EOF > /etc/prometheus/prometheus.yml
global:
  scrape_interval:     15s # Set the scrape interval to every 15 seconds. Default is every 1 minute.
  evaluation_interval: 15s # Evaluate rules every 15 seconds. The default is every 1 minute.
  # scrape_timeout is set to the global default (10s).

# Alertmanager configuration
alerting:
  alertmanagers:
  - static_configs:
    - targets:
      # - alertmanager:9093

# Load rules once and periodically evaluate them according to the global 'evaluation_interval'.
rule_files:
  # - "first_rules.yml"
  # - "second_rules.yml"

# A scrape configuration containing exactly one endpoint to scrape:

scrape_configs:
  - job_name: node
    static_configs:
    - targets: [ {{MASTER_NODE_EXPORTER_URLS}}, {{WORKER_NODE_EXPORTER_URLS}}

  - job_name: "alluxio master"
    metrics_path: '/metrics/prometheus/'
    static_configs:
    - targets: [ {{MASTER_METRICS_URLS}} ]

  - job_name: "alluxio worker"
    metrics_path: '/metrics/prometheus/'
    static_configs:
    - targets: [ {{WORKER_METRICS_URLS}} ]
EOF

  # Setup the alluxio master node hostnames in prometheus.yml file

  instance_ids=$(aws ec2 --region ${AWS::Region} describe-instances --query 'Reservations[*].Instances[*].InstanceId' --filters "Name=tag-key,Values=aws:cloudformation:stack-name" "Name=tag-value,Values=${AWS::StackName}" --output=text | tr '\n' ' ')

  master_metrics_urls=""
  worker_metrics_urls=""
  for next_instance_id in $instance_ids
  do
    NODE_TYPE=$(aws ec2 --region ${AWS::Region} describe-instances --instance-ids $next_instance_id --query 'Reservations[].Instances[].Tags[?Key==`alluxio-node-type`].Value[]' --output text)
    PRIVATE_IP_ADDRESS=$(aws ec2 --region ${AWS::Region} describe-instances --query 'Reservations[*].Instances[*].PrivateIpAddress' --instance-ids $next_instance_id --output=text)
    FQDN=$(aws ec2 --region ${AWS::Region} describe-instances --query 'Reservations[*].Instances[*].PrivateDnsName' --instance-ids $next_instance_id --output=text)

    # Get the master and worker node_exporter urls (i.e. master1:9100,master2:9100, master3:9100)
    if [ "$NODE_TYPE" == "MASTER" ]; then
      if $master_metrics_urls != ""; then $master_metrics_urls+=","; fi
      master_metrics_urls+= "\'$FQDN:9100\'"
    elif [ "$NODE_TYPE" == "WORKER" ]; then
      if $worker_metrics_urls != ""; then $worker_metrics_urls+=","; fi
      worker_metrics_urls+= "\'$FQDN:9100\'"
    fi

    # Get the master and worker metrics urls (i.e. master1:19999,master2:19999, master3:19999)
    if [ "$NODE_TYPE" == "MASTER" ]; then
      if $master_metrics_urls != ""; then $master_metrics_urls+=","; fi
      master_metrics_urls+= "\'$FQDN:19999\'"
    elif [ "$NODE_TYPE" == "WORKER" ]; then
      if $worker_metrics_urls != ""; then $worker_metrics_urls+=","; fi
      worker_metrics_urls+= "\'$FQDN:29999\'"
    fi
  done

  # Add private hostname to prometheus.yml file
  sed -i "s/{{MASTER_METRICS_URLS}}/$master_metrics_urls/g" /etc/prometheus/prometheus.yml
  sed -i "s/{{WORKER_METRICS_URLS}}/$worker_metrics_urls/g" /etc/prometheus/prometheus.yml

  # Setup the systemd service
  cat <<EOF > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
Documentation=https://prometheus.io/docs/introduction/overview/
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
Environment="GOMAXPROCS=4"
User=prometheus
Group=prometheus
ExecReload=/bin/kill -HUP $MAINPID
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --web.listen-address=0.0.0.0:9090 \
  --web.external-url=

SyslogIdentifier=prometheus
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  mkdir -p /var/lib/prometheus/
  chown -R prometheus:prometheus /var/lib/prometheus/
  systemctl daemon-reload
  systemctl start prometheus
  systemctl enable prometheus
  systemctl status prometheus

# End of script
