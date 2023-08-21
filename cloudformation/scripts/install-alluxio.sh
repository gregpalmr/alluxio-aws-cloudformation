#!/bin/bash
#
# SCRIPT: install-alluxio.sh
#

  function print_err {
     echo " Script install-alluxio.sh - ERROR: $1 "
  }
  function fail_with_error {
     print_err "$1 ... exiting script. "
     exit -1
  }

  # Get the script arguments
  #
  if [ $# -ne 9 ]; then
       fail_with_error "Incorrect number of arguments passed. Requires 9 arguments: NODE_TYPE, AWS_STACK_NAME, AWS_REGION, ALLUXIO_S3_BUCKET_NAME, ALLUXIO_DOWNLOAD_URL, ALLUXIO_LICENSE_DOWNLOAD_URL, MASTER_HEAP_MEMORY_SIZE, WORKER_HEAP_MEMORY_SIZE, WORKER_COUNT."
  fi

  THIS_NODE_TYPE="$1"                 # master or worker
  AWS_STACK_NAME="$2"
  AWS_REGION="$3"
  ALLUXIO_S3_BUCKET_NAME="$4"
  ALLUXIO_DOWNLOAD_URL="$5"
  ALLUXIO_LICENSE_DOWNLOAD_URL="$6"
  MASTER_HEAP_MEMORY_SIZE="$7"
  WORKER_HEAP_MEMORY_SIZE="$8"
  WORKER_COUNT="$9"

  echo "Script install-alluxio.sh has started."
  echo "Script Arguments:"
  echo "MASTER_HEAP_MEMORY_SIZE = $MASTER_HEAP_MEMORY_SIZE"
  echo "WORKER_HEAP_MEMORY_SIZE = $WORKER_HEAP_MEMORY_SIZE"
  echo "WORKER_COUNT = $WORKER_COUNT"

  # Setup Alluxio Environment
  export ALLUXIO_HOME=/opt/alluxio
  export PATH=$PATH:$ALLUXIO_HOME/bin
  echo "export ALLUXIO_HOME=/opt/alluxio" > /etc/profile.d/alluxio.sh
  echo "export PATH=\$PATH:\$ALLUXIO_HOME/bin" >> /etc/profile.d/alluxio.sh

  # Increase the number of files that can be opened at one time
  cat <<EOF >>/etc/security/limits.conf
* hard nofile 500000
* soft nofile 500000
alluxio  hard nofile 500000
alluxio  soft nofile 500000
EOF
  sysctl -p

  STAGING_S3_BUCKET=s3://$ALLUXIO_S3_BUCKET_NAME

  # Get this Alluxio node's private ip address (use only the IMDSv2 method)
  # Get a token that lasts for 6 hours
  IMDSv2_TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
  # Then get this node's IP address
  THIS_IP_ADDRESS=$(curl -H "X-aws-ec2-metadata-token: $IMDSv2_TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

  # Create the Alluxio user and group
  groupadd --gid 1030 alluxio
  useradd --home /opt/alluxio --no-create-home --uid 1030 --gid alluxio alluxio

  # Install Alluxio tar file contents
  #
  if [ ! -d /opt/alluxio ]; then

    url=${ALLUXIO_DOWNLOAD_URL}

    # Install Alluxio RPM
    if [[ "$url" == *s3:* ]] || [[ "$url" == *S3:* ]]; then
      aws s3 --region $AWS_REGION cp $url /root/
      tar -xvzpf /root/$(basename $url) -C /opt/
    elif [[ "$url" == *http* ]] || [[ "$url" == *HTTP* ]]; then
      curl -O $url
      tar -xvzpf $(basename $url) -C /opt/
    else
      fail_with_error "Parameter \"ALLUXIO_DOWNLOAD_URL\" not specified as either an s3:// or http:// URI. Specified as: $url "
    fi

    if [ $? != 0 ]; then
      fail_with_error "Unable to download Alluxio install tarball."
    fi

    # Add symbolic link to Alluxio install directory
    ln -s /opt/alluxio-*/ /opt/alluxio

    # Chown to alluxio user
    chown -R alluxio:alluxio /opt/alluxio-*

    # Download the Alluxio license file, if provided
    license_url=${ALLUXIO_LICENSE_DOWNLOAD_URL}

    if [[ "$license_url" != "NONE" ]]; then
      if [[ "$license_url" == *s3:* ]] || [[ "$license_url" == *S3:* ]]; then
        aws s3 --region $AWS_REGION cp $license_url /root/license.json
        cp /root/license.json /opt/alluxio/license.json
      elif [[ "$license_url" == *http* ]] || [[ $license_url == *HTTP* ]]; then
        curl -o /root/license.json $license_url
        cp /root/license.json /opt/alluxio/license.json
      else
        fail_with_error "Parameter \"ALLUXIO_LICENSE_DOWNLOAD_URL\" not specified as either an s3:// or http:// URI. Specified as: $url "
      fi

      if [ $? != 0 ]; then
        fail_with_error "Unable to download Alluxio license file."
      fi
    fi
  fi

  # If this is a MASTER node, configure the master
  #
  if [ "$THIS_NODE_TYPE" == "master" ] || [ "$THIS_NODE_TYPE" == "MASTER" ]; then
    echo " Configuring a master node"

    # Create the folder in the S3 bucket for the root.ufs
    aws s3api put-object --bucket ${ALLUXIO_S3_BUCKET_NAME} --key "alluxio_ufs/$AWS_STACK_NAME/"

  fi # end if THIS_NODE_TYPE = MASTER

  # If this is a WORKER node, setup the worker
  #
  if [ "$THIS_NODE_TYPE" == "worker" ] || [ "$THIS_NODE_TYPE" == "WORKER" ]; then
    echo " Configuring a worker node"

  fi # end if THIS_NODE_TYPE = WORKER

  # Calcluate 2/3 of RAM for the Alluxio worker node MEM Ramdisk
  yum -y install bc
  total_mem=$(grep ^MemFree /proc/meminfo | awk '{print $2}')
  # Calculate 2/3 of the available MEM
  twoThirdsKb=$(echo "$total_mem * 0.66" | bc --mathlib --quiet)
  # Convert KB to GB
  twoThirdsGb=$(printf "%.2f\n" `echo "$twoThirdsKb / 1024 / 1024" | bc --mathlib --quiet`)
  # if calc didn't work, then just use 2GB for ramdisk
  if ! [[ "$twoThirdsGb" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    twoThirdsGb=2
  fi
  twoThirdsGb=$(printf "%.2fGB\n" $twoThirdsGb )

  # Add the ip addresses of all Alluxio nodes to /etc/hosts and conf/masters, conf/workers files
  #
  sleep 30
  instance_ids=$(aws ec2 --region $AWS_REGION describe-instances --query 'Reservations[*].Instances[*].InstanceId' --filters "Name=tag-key,Values=aws:cloudformation:stack-name" "Name=tag-value,Values=${AWS::StackName}" --output=text | tr '\n' ' ')

  # Get all the master nodes and put their ip addresses in /opt/alluxio/conf/masters 
  echo "" >> /etc/hosts
  echo "# Alluxio cluster master hostnames" >> /etc/hosts

  rm -f $ALLUXIO_HOME/conf/masters

  for next_instance_id in $instance_ids
  do
    IP_ADDRESS=""
    IP_ADDRESS=$(aws ec2 --region $AWS_REGION describe-instances --query 'Reservations[*].Instances[*].PrivateIpAddress' --instance-ids $next_instance_id --filters "Name=tag-key,Values=Name" "Name=tag-value,Values=$AWS_STACK_NAME-Alluxio-Master" --output=text)
    FQDN=$(aws ec2 --region $AWS_REGION describe-instances --query 'Reservations[*].Instances[*].PrivateDnsName' --instance-ids $next_instance_id --filters "Name=tag-key,Values=Name" "Name=tag-value,Values=$AWS_STACK_NAME-Alluxio-Master" --output=text)
    
    if [ $IP_ADDRESS != "" ]; then

      # Add ip address to /etc/host file
      echo "$IP_ADDRESS     $FQDN" >> /etc/hosts

      # Add ip address to conf/masters
      echo "$IP_ADDRESS" >> $ALLUXIO_HOME/conf/masters 
    fi 
  done 

  # Get all the worker nodes and put their ip addresses in /opt/alluxio/conf/workers 
  echo "" >> /etc/hosts
  echo "# Alluxio cluster worker hostnames" >> /etc/hosts

  rm -f $ALLUXIO_HOME/conf/workers

  for next_instance_id in $instance_ids
  do
    IP_ADDRESS=""
    IP_ADDRESS=$(aws ec2 --region $AWS_REGION describe-instances --query 'Reservations[*].Instances[*].PrivateIpAddress' --instance-ids $next_instance_id --filters "Name=tag-key,Values=Name" "Name=tag-value,Values=$AWS_STACK_NAME-Alluxio-Worker" --output=text)
    FQDN=$(aws ec2 --region $AWS_REGION describe-instances --query 'Reservations[*].Instances[*].PrivateDnsName' --instance-ids $next_instance_id --filters "Name=tag-key,Values=Name" "Name=tag-value,Values=$AWS_STACK_NAME-Alluxio-Worker" --output=text)
    
    if [ $IP_ADDRESS != "" ]; then

      # Add ip address to /etc/host file
      echo "$IP_ADDRESS     $FQDN" >> /etc/hosts

      # Add IP address to conf/workers
      echo "$IP_ADDRESS" >> $ALLUXIO_HOME/conf/workers 
    fi 
  done 

  # Create the EMBEDDED journal address property containing all three master nodes
  JOURNAL_URLS=""
  for master_hostname in `cat /opt/alluxio/conf/masters`; do 
    JOURNAL_URLS+="$master_hostname:19200,"
  done
  JOURNAL_URLS=$(echo $JOURNAL_URLS | sed "s/,$//") # strip off trailing comma

  # Setup alluxio-env.sh to increase the Heap memory for masters and workers
  cat <<EOF > $ALLUXIO_HOME/conf/alluxio-env.sh
#!/usr/bin/env bash
#

# Java 1.8 syntax:
#ALLUXIO_MASTER_JAVA_OPTS="-Xmx${MASTER_HEAP_MEMORY_SIZE}g -Xms${MASTER_HEAP_MEMORY_SIZE}g -XX:MaxDirectMemorySize=8g -XX:+PrintSafepointStatistics -XX:PrintSafepointStatisticsCount=1 -XX:+SafepointTimeout -XX:SafepointTimeoutDelay=10000 -XX:-UseBiasedLocking -Dio.netty.noUnsafe=true -XX:+PrintGCDetails -verbose:gc -XX:+PrintGCTimeStamps -Xloggc:/opt/alluxio/logs/gc_master.log"
#ALLUXIO_WORKER_JAVA_OPTS="-Xmx${WORKER_HEAP_MEMORY_SIZE}g -Xms${WORKER_HEAP_MEMORY_SIZE}g -XX:MaxDirectMemorySize=8g -XX:+PrintSafepointStatistics -XX:PrintSafepointStatisticsCount=1 -XX:+SafepointTimeout -XX:SafepointTimeoutDelay=10000 -XX:-UseBiasedLocking -Dio.netty.noUnsafe=true -XX:+PrintGCDetails -verbose:gc -XX:+PrintGCTimeStamps -Xloggc:/opt/alluxio/logs/gc_worker.log"

# Java 1.11 syntax:
ALLUXIO_MASTER_JAVA_OPTS="-XX:+UseG1GC -Xmx${MASTER_HEAP_MEMORY_SIZE}g -Xms${MASTER_HEAP_MEMORY_SIZE}g -XX:MaxDirectMemorySize=8g -XX:MaxNewSize=16g -XX:MetaspaceSize=268435456 -XX:NewSize=14g -XX:MaxGCPauseMillis=10000 -Xlog:safepoint -Xlog:gc=info:file=/opt/alluxio/logs/gc.log:time,uptime,level,tags:filecount=5,filesize=100m "
ALLUXIO_WORKER_JAVA_OPTS="-XX:+UseG1GC -Xmx${WORKER_HEAP_MEMORY_SIZE}g -Xms${WORKER_HEAP_MEMORY_SIZE}g -XX:MaxDirectMemorySize=8g -XX:MaxNewSize=16g -XX:MetaspaceSize=268435456 -XX:NewSize=14g -XX:MaxGCPauseMillis=10000 -Xlog:safepoint -Xlog:gc=info:file=/opt/alluxio/logs/gc.log:time,uptime,level,tags:filecount=5,filesize=100m "

EOF

  # Setup metrics sink for Prometheus
  cat <<EOF > $ALLUXIO_HOME/conf/metrics.properties
# FILE: metrics.properties
#
sink.prometheus.class=alluxio.metrics.sink.PrometheusMetricsServlet
EOF

  # Setup alluxio-site.properties
  #
  cat <<EOF > $ALLUXIO_HOME/conf/alluxio-site.properties
  # FILE: alluxio-site.properties
  #
  alluxio.home=/opt/alluxio

  # Configure the Alluxio master
  alluxio.master.hostname=$THIS_IP_ADDRESS

  # Alluxio Web UI Settings
  alluxio.master.web.port=19999
  alluxio.web.login.enabled=false
  alluxio.web.login.username=admin
  alluxio.web.login.password=changeme

  # Configure the EMBEDDED (RAFT based) Journal 
  alluxio.master.journal.type=EMBEDDED
  alluxio.master.embedded.journal.addresses=$JOURNAL_URLS
  alluxio.master.journal.folder=/opt/alluxio/journal
  alluxio.master.daily.backup.enabled=true
  alluxio.master.daily.backup.time=08:00
  alluxio.master.backup.delegation.enabled=true

  # Configure RocksDB based metastore
  alluxio.master.metastore=ROCKS
  alluxio.master.metastore.dir=/opt/alluxio/metastore

  # Configure user block size, writetype and readtype
  alluxio.user.block.size.bytes.default=16M
  alluxio.user.file.writetype.default=CACHE_THROUGH
  alluxio.user.file.readtype.default=CACHE

  # Configure S3 as the root under storage system (UFS)
  alluxio.master.mount.table.root.ufs=s3://${ALLUXIO_S3_BUCKET_NAME}/alluxio_ufs/${AWS::StackName}

  # Configure a single storage tier in Alluxio (MEM)
  alluxio.worker.tieredstore.levels=1
        
  # Configure the tier to be a memory tier 
  alluxio.worker.tieredstore.level0.alias=MEM
  alluxio.worker.tieredstore.level0.dirs.path=/mnt/ramdisk
  alluxio.worker.tieredstore.level0.dirs.mediumtype=MEM
  alluxio.worker.tieredstore.level0.dirs.quota=$twoThirdsGb

EOF

  # Chown to alluxio:alluxio
  chown -R alluxio:alluxio /opt/alluxio-*

  # If this is a MASTER node, start the master daemons
  #
  if [ "$THIS_NODE_TYPE" == "master" ] || [ "$THIS_NODE_TYPE" == "MASTER" ]; then
    # Format Alluxio journal
    su - alluxio bash -c "$ALLUXIO_HOME/bin/alluxio formatJournal"

    # Start the Alluxio masters
    #
    su - alluxio bash -c "$ALLUXIO_HOME/bin/alluxio-start.sh master"
    sleep 2
    su - alluxio bash -c "$ALLUXIO_HOME/bin/alluxio-start.sh job_master"
  
    su - alluxio bash -c "$ALLUXIO_HOME/bin/alluxio-start.sh proxy"
    sleep 2
  fi

  # If this is a WORKER node, start the worker daemons
  #
  if [ "$THIS_NODE_TYPE" == "worker" ] || [ "$THIS_NODE_TYPE" == "WORKER" ] || [ "$WORKER_COUNT" == 0 ]; then

       # Mount the ram disk (as root)
       $ALLUXIO_HOME/bin/alluxio-mount.sh Mount local
       sleep 2

       # Format the Alluxio worker nodes
       su - alluxio bash -c "$ALLUXIO_HOME/bin/alluxio formatWorker"
       sleep 2

       # Start the Alluxio worker node processes
       su - alluxio bash -c "$ALLUXIO_HOME/bin/alluxio-start.sh worker NoMount"
       sleep 2

       su - alluxio bash -c "$ALLUXIO_HOME/bin/alluxio-start.sh job_worker"
       sleep 2
  fi

  # Start the Alluxio proxy service on this node
  su - alluxio bash -c "$ALLUXIO_HOME/bin/alluxio-start.sh proxy"
  sleep 2

  # Finalize install, and return 
  echo "Script install-alluxio.sh has completed."
  until curl -Iks http://localhost:19999; do
    echo waiting for Alluxio website availability on port 19999
    sleep 5
  done

  echo "{ \"Status\" : \"SUCCESS\", \"UniqueId\" : \"${AWS::StackName}\", \"Data\" : \"Ready\", \"Reason\" : \"Website Available\" }" > $statusFile
  curl -T $statusFile '${AvailabilityWaitHandle}'
  #aws cloudformation --region ${AWS::Region} signal-resource --stack-name ${AWS::StackName} --logical-resource-id AvailabilityWaitCondition --unique-id ${AWS::StackName} --status SUCCESS


# End of script

