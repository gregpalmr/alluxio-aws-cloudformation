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
  useradd --home /home/alluxio --uid 1030 --gid alluxio alluxio

  # Install Alluxio tar file contents
  #
  if [ ! -d /opt/alluxio ]; then

    url=${ALLUXIO_DOWNLOAD_URL}

    # Install Alluxio from tar file
    echo "Downloading Alluxio install file: $url"
    if [[ "$url" == *s3:* ]] || [[ "$url" == *S3:* ]]; then
      aws s3 --region $AWS_REGION cp $url /root/
      tar -xzpf /root/$(basename $url) -C /opt/
    elif [[ "$url" == *http* ]] || [[ "$url" == *HTTP* ]]; then
      curl -O $url
      tar -xzpf $(basename $url) -C /opt/
    else
      fail_with_error "Parameter \"ALLUXIO_DOWNLOAD_URL\" not specified as either an s3:// or http:// URI. Specified as: $url "
    fi

    if [ "$?" != 0 ] || [! -f /root/$(basename $url) ]; then
      fail_with_error "Unable to download Alluxio install file: $url"
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

      if [ "$?" != 0 ]; then
        fail_with_error "Unable to download Alluxio license file."
      fi
    fi
  fi

  echo " Configuring Alluxio node type: $THIS_NODE_TYPE"

  # If this is a MASTER node, configure the master
  #
  if [ "$THIS_NODE_TYPE" == "master" ] || [ "$THIS_NODE_TYPE" == "MASTER" ]; then

    # Create the folder in the S3 bucket for the root.ufs
    aws s3api put-object --bucket ${ALLUXIO_S3_BUCKET_NAME} --key "alluxio_root_ufs/$AWS_STACK_NAME/"
  fi # end if THIS_NODE_TYPE = MASTER

  # If this is a WORKER node, setup the worker
  #
  if [ "$THIS_NODE_TYPE" == "worker" ] || [ "$THIS_NODE_TYPE" == "WORKER" ]; then
    echo ""

    # If this worker has NVMe disks, set them up for use by Alluxio worker
    #

    # Get a list of all nvme drives
    NVME_DISKS=$(lsblk | grep disk | grep nvme | awk '{print $1 }' | sort)

    diskno=1

    for NEXT_DISK in $(echo $NVME_DISKS); do

      # Skip any NVMe drives that are already mounted or have data
      is_mounted=$(df | grep /dev/${NEXT_DISK})
      if [ "$is_mounted" != "" ]; then
        # This drive is mounted, skip it
        echo " Skipping /dev/${NEXT_DISK} because is already mounted."
        continue
      fi

      # Skip any NVMe drives that already have data in them
      #has_data=$(file -s /dev/${NEXT_DISK} | awk '{ print $2 }')
      #if [ "$has_data" != "data" ]; then
      #  echo " Skipping /dev/${NEXT_DISK} because is not empty and cannot mkfs."
      #  continue
      #fi

      echo " Making file system on /dev/${NEXT_DISK} to mount on /nvme${diskno}"

      mkfs -t xfs /dev/${NEXT_DISK}
      if [ "$?" != 0 ]; then
        echo "Error running \"mkfs -t xfs /dev/${NEXT_DISK}\". Skipping."
        continue
      fi

      mkdir -p /nvme${diskno}
      mount /dev/${NEXT_DISK} /nvme${diskno}

      result=$(df -h | grep ${NEXT_DISK})
      if [ "$?" != 0 ]; then
        echo "Error mounting /nvme${diskno} on /dev/${NEXT_DISK}\". Skipping."
        continue
      fi

      # Change permissions so the alluxio user can access the nvme storage
      chown alluxio:alluxio /nvme${diskno}

      # Get the UUID for the newly mounted disk
      uuid=$(blkid | grep ${NEXT_DISK} | awk '{ print $2 }' | sed 's/"//g')
      if [[ "$uuid" != *"UUID"* ]]; then
        echo "Error getting UUID of disk /dev/${NEXT_DISK}. Skipping."
        continue
      fi

      # Add the mount to the /etc/fstab file
      echo "$uuid /nvme${diskno}  xfs    defaults,noatime  1   1" >> /etc/fstab

      # Setup properties in alluxio-site.properties file
      tieredstore_level0_dirs_alias="SSD"
      tieredstore_level0_dirs_path="$tieredstore_level0_dirs_path,/nvme${diskno}"
      tieredstore_level0_dirs_path=$(echo $tieredstore_level0_dirs_path | sed 's/^[[:blank:]]*,//')
      available_space="270GB"  # TODO: calculate this at 90 % of available disk
      tieredstore_level0_dirs_quota="$tieredstore_level0_dirs_quota,$available_space"
      tieredstore_level0_dirs_quota=$(echo $tieredstore_level0_dirs_quota | sed 's/^[[:blank:]]*,//')

      diskno=$((diskno += 1))
    done

    # If no NVMe drives were available, revert to using 2/3 of RAM for cache storage
    if [ "$tieredstore_level0_dirs_path" == "" ]; then
    
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
      echo "Calculated the RAM disk as 2/3 of available RAM: $twoThirdsGb"

      tieredstore_level0_dirs_alias=MEM
      tieredstore_level0_dirs_path="/mnt/ramdisk"
      tieredstore_level0_dirs_quota="$twoThirdsGb"

    fi

  fi # end if THIS_NODE_TYPE = WORKER


  # Add the ip addresses of all Alluxio nodes to /etc/hosts and conf/masters, conf/workers files
  #
  sleep 30
  instance_ids=$(aws ec2 --region $AWS_REGION describe-instances --query 'Reservations[*].Instances[*].InstanceId' --filters "Name=tag-key,Values=aws:cloudformation:stack-name" "Name=tag-value,Values=${AWS_STACK_NAME}" --output=text | tr '\n' ' ')
  echo "Got list of this cluster's EC2 instances: $instance_ids"

  # Get all the master nodes and put their ip addresses in /opt/alluxio/conf/masters 
  echo "" >> /etc/hosts
  echo "# Alluxio cluster master hostnames" >> /etc/hosts

  rm -f $ALLUXIO_HOME/conf/masters

  for next_instance_id in $instance_ids
  do
    IP_ADDRESS=""
    IP_ADDRESS=$(aws ec2 --region $AWS_REGION describe-instances --query 'Reservations[*].Instances[*].PrivateIpAddress' --instance-ids $next_instance_id --filters "Name=tag-key,Values=Name" "Name=tag-value,Values=$AWS_STACK_NAME-Alluxio-Master" --output=text)
    FQDN=$(aws ec2 --region $AWS_REGION describe-instances --query 'Reservations[*].Instances[*].PrivateDnsName' --instance-ids $next_instance_id --filters "Name=tag-key,Values=Name" "Name=tag-value,Values=$AWS_STACK_NAME-Alluxio-Master" --output=text)
    
    if [ "$IP_ADDRESS" != "" ]; then

      # Add ip address to /etc/host file
      echo "$IP_ADDRESS     $FQDN" >> /etc/hosts

      # Add ip address to conf/masters
      echo "Adding master node entry to $ALLUXIO_HOME/conf/masters: $IP_ADDRESS"
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
    
    if [ "$IP_ADDRESS" != "" ]; then

      # Add ip address to /etc/host file
      echo "$IP_ADDRESS     $FQDN" >> /etc/hosts

      # Add IP address to conf/workers
      echo "Adding worker node entry to $ALLUXIO_HOME/conf/workers: $IP_ADDRESS"
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
  alluxio.master.backup.directory=s3://${ALLUXIO_S3_BUCKET_NAME}/alluxio_root_ufs/${AWS_STACK_NAME}/alluxio_backups
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
  alluxio.master.mount.table.root.ufs=s3://${ALLUXIO_S3_BUCKET_NAME}/alluxio_root_ufs/${AWS_STACK_NAME}

EOF

  if [ "$THIS_NODE_TYPE" == "worker" ] || [ "$THIS_NODE_TYPE" == "WORKER" ]; then
  cat <<EOF >> $ALLUXIO_HOME/conf/alluxio-site.properties

  # Configure a single storage tier in Alluxio (MEM or NVMe/SSD)
  alluxio.worker.tieredstore.levels=1
  alluxio.worker.tieredstore.level0.alias=$tieredstore_level0_dirs_alias
  alluxio.worker.tieredstore.level0.dirs.path=$tieredstore_level0_dirs_path
  alluxio.worker.tieredstore.level0.dirs.quota=$tieredstore_level0_dirs_quota
  
EOF
  fi

  # Chown to alluxio:alluxio
  chown -R alluxio:alluxio /opt/alluxio-*

  # If this is a MASTER node, start the master daemons
  #
  if [ "$THIS_NODE_TYPE" == "master" ] || [ "$THIS_NODE_TYPE" == "MASTER" ]; then
    # Format Alluxio journal
    su - alluxio bash -c "$ALLUXIO_HOME/bin/alluxio formatJournal"

    # Start the Alluxio master node daemons
    
    # if there is a metadata backup in the root ufs S3 bucket, restore it
    cmd="aws s3 ls s3://${ALLUXIO_S3_BUCKET_NAME}/alluxio_root_ufs/${AWS_STACK_NAME}/alluxio_backups/ | grep '.gz$' | awk '{print $4}' | sort | tail -n 1"
    echo " Checking for an Alluxio metadata backup file with the command:"
    echo "$cmd"
    backup_file=$(aws s3 ls s3://${ALLUXIO_S3_BUCKET_NAME}/alluxio_root_ufs/${AWS_STACK_NAME}/alluxio_backups/ | grep '.gz$' | awk '{print $4}' | sort | tail -n 1)
    if [ "$backup_file" != "" ]; then
      cmd="$ALLUXIO_HOME/bin/alluxio-start.sh -i $STAGING_S3_BUCKET/alluxio_root_ufs/$AWS_STACK_NAME/alluxio_backups/$backup_file -a master"
      echo " Starting the Alluxio master and restoring a metadata backup file with the command:"
      echo $cmd
      su - alluxio bash -c "$cmd"
    else
      echo " Starting the Alluxio master without restoring a metadata backup file"
      su - alluxio bash -c "$ALLUXIO_HOME/bin/alluxio-start.sh master"
    fi
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

# End of script

