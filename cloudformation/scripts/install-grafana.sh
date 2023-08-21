#!/bin/bash
#
# SCRIPT: install-grafana.sh
#

  # Install Grafana

  cat <<EOF > /etc/yum.repos.d/grafana.repo
[grafana]
name=grafana
baseurl=https://packages.grafana.com/oss/rpm
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://packages.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

  yum -y install grafana

  # Setup default data source as prometheus
  cat <<EOF > /etc/grafana/provisioning/datasources/default.yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
EOF

  cat <<EOF > /etc/grafana/provisioning/datasources/datasources.yaml
apiVersion: 1

datasources:
  # <string, required> name of the datasource. Required
  - name: Prometheus
    type: prometheus
    access: proxy
    orgId: 1
    uid: 'KaXNuaQ7z'
    url: 'http://localhost:9090'
    user:
    database:
    basicAuth: false
    basicAuthUser:
    basicAuthPassword:
    withCredentials:
    isDefault: true
    jsonData:
      httpMethod: 'POST'
      tlsAuth: false
      tlsAuthWithCACert: false
    secureJsonData:
      tlsCACert: '...'
      tlsClientCert: '...'
      tlsClientKey: '...'
      password:
      basicAuthPassword:
    version: 1
    editable: false
EOF

  systemctl restart grafana-server
  systemctl status grafana-server

  # Point your web browser to <monitor host>:3000
  # Default userid and password: admin/admin

# end of script
