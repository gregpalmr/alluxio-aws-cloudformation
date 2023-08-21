#!/bin/bash
#
# SCRIPT: install-java.sh
#

  # Install Java 1.11
  yum -y install java-11-amazon-corretto

  # Setup environment
  export JAVA_HOME=/usr/lib/jvm/jre-11
  export PATH=$PATH:$JAVA_HOME/bin
  echo "export JAVA_HOME=/usr/lib/jvm/jre-11" > /etc/profile.d/jre.sh
  echo "export PATH=\$PATH:\$JAVA_HOME/bin" >> /etc/profile.d/jre.sh

# End of script
