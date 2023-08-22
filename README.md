# alluxio-aws-cloudformation

An AWS Cloudformation template to launch an Alluxio cluster that uses S3 as the under filesystem (UFS).

## Background

This AWS CloudFormation template launches Alluxio on AWS Infrastructure and creates the following resources:

- EC2 Instances (m5.2xlarge for Alluxio masters, r5d.4xlarge for Alluxio workers)
- Auto Scaling Group for Alluxio workers
- Security Group rules for intra-node communications
- Security Group rules for external access (can be restricted to your IP address)
- Integration with your existing VPC and subnets

This template launches one Alluxio master node, and a number of Alluxio worker nodes as specified. It configures and launches the Alluxio master and worker daemons and optionally sets up passwordless SSH between the master node and the workers.

## Prerequisites

To use this AWS CloudFormation template, you need the following:

- A valid AWS account with the following IAM role policies:
     - AmazonEC2FullAccess
     - AmazonS3FullAccess

     or

     - Enough permissions to launch a CloudFormation stack and access an S3 bucket

     - See: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html

- Enough quota for the number of r5.4xlarge EC2 instances need for your Alluxio worker nodes

- A working AWS CLI environment on your computer
     - See: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html

- A working github CLI environment
     - See: https://github.com/git-guides/install-git

## Usage

### Step 1. Clone this github repo

Clone this repo with the git CLI commands:

     $ git clone https://github.com/gregpalmr/alluxio-aws-cloudformation
     $ cd alluxio-aws-cloudformation

### Step 2. Upload the Alluxio install file to an S3 bucket

Alluxio offers a free Community Edition as well as a trial licensed Enterprise Edition. Download one of them and upload it to an S3 bucket.

Download the Alluxio Enterprise or Community Edition from the Alluxio website:

     https://www.alluxio.io/download/

Use your AWS S3 console or the AWS CLI to create a new private S3 bucket if you don't already have a bucket to use:

     $ aws s3api create-bucket --bucket my-alluxio-bucket \
            --region us-east-1 \
            --acl private

Use your AWS S3 console or the AWS CLI to copy the Alluxio tar file to the bucket. For example:

     $ aws s3 cp alluxio-2.10.0-2.0-bin.tar.gz s3://my-alluxio-bucket/installers/
 
### Step 3. (Optional) Upload your Alluxio Enterprise Edition Licnese Key to an S3 bucket

If you are deploying the Enterprise Edition of Alluxio, you will require a license file, which you can obtain from the Alluxio customer support team. Upload that file to your private S3 bucket.

Use your AWS S3 console or the AWS CLI to copy the Alluxio tar file to your S3 bucket. For example:

     $ aws s3 cp ./alluxio-enterprise-license.json \
                     s3://my-alluxio-bucket/installers/alluxio-enterprise-license.json

### Step 4. Create the SSH key and AWS key-pair

Use an SSH keygen program to create an SSH key.

Windows

     TBD

MacOS and Linux

     $ ssh-keygen -f my-alluxio-sshkey -t rsa -N ''

     $ aws --region us-east-1 ec2 \
           import-key-pair \
           --key-name "my-alluxio-keypair" \
           --public-key-material fileb://my-alluxio-sshkey.pub

### Step 5. Run the AWS create stack command

AWS provides a "create-stack" command to launch a coordinated infrastructure creation process. Use the provided CloudFormation template to launch an Alluxio cluster. This Alluxio CloudFormation template supports multiple cluster sizes including the following:

Alluxio can cache data in memory or on NVMe or SSD storage. To deploy an Alluxio cluster that caches data to a RAM disk that is 2/3 the size of available memory, use the following clusterSize parameters:

- 1-workers-mem-cache  - 3 Alluxio master nodes (m5.2xlarge) and 1 worker nodes (r5.4xlarge)
- 3-workers-mem-cache  - 3 Alluxio master nodes (m5.2xlarge) and 3 worker nodes (r5.4xlarge)
- 5-workers-mem-cache  - 3 Alluxio master nodes (m5.2xlarge) and 5 worker nodes (r5.4xlarge)
- 10-workers-mem-cache - 3 Alluxio master nodes (m5.2xlarge) and 10 worker nodes (r5.4xlarge)
- 25-workers-mem-cache - 3 Alluxio master nodes (m5.2xlarge) and 25 worker nodes (r5.4xlarge)
- 50-workers-mem-cache - 3 Alluxio master nodes (m5.2xlarge) and 50 worker nodes (r5.4xlarge)

To deploy an Alluxio cluster that caches data to two 300 GB NVMe disks, use the following clusterSize parameters:

- 1-workers-nvme-cache  - 3 Alluxio master nodes (m5.2xlarge) and 1 worker nodes (r5d.4xlarge)
- 3-workers-nvme-cache  - 3 Alluxio master nodes (m5.2xlarge) and 3 worker nodes (r5d.4xlarge)
- 5-workers-nvme-cache  - 3 Alluxio master nodes (m5.2xlarge) and 5 worker nodes (r5d.4xlarge)
- 10-workers-nvme-cache - 3 Alluxio master nodes (m5.2xlarge) and 10 worker nodes (r5d.4xlarge)
- 25-workers-nvme-cache - 3 Alluxio master nodes (m5.2xlarge) and 25 worker nodes (r5d.4xlarge)
- 50-workers-nvme-cache - 3 Alluxio master nodes (m5.2xlarge) and 50 worker nodes (r5d.4xlarge)

The CloudFormation template requires some user supplied options, including:

- clusterSize - The size of the Alluxio cluster to launch (see above).

- useVPC - The existing VPC to use. Your AWS administrator can supply this or you can create a VPC yourself using the AWS VPC console or the AWS CLI. It should take the form of: vpc-ad49er61ba

- useSubnet - The existing VPC subnet to use. Your AWS administrator can supply this or you can create a subnet using the AWS VPC console or the AWS CLI. It should take the form of: subnet-0fcea85e31ff88608

- keypairName - The AWS keypair to use when launching the EC2 instances. The keypair will allow you to SSH to your EC2 instances later. Your AWS administrator can supply this or you can create a keypair using the AWS IAM console or the AWS CLI.

- securityGroupInboundSourceCidr - The CIDR for which to restrict inbound access. If you set this option to "0.0.0/0", anyone on the Internet will be able to access your EC2 instances (specfically the SSH port 22 and the Alluxio Web console port 19999). It is recommended that you supply a CIDR that restricts access to your IP address or to your VPN's IP address. You can get your computer's IP address by pointing your Web browser to:

     https://whatismyipaddress.com/

     This web page will provide you with your IPv4 and IPv6 IP addresses. Use the IPv4 address and specify a CIDR like this:

     67.220.95.204/24

- alluxioS3BucketName - The name of the S3 bucket that you created for Alluxio to use as an under filesystem (UFS).

- alluxioDownloadURL - A reference to the S3 bucket location where you uploaded the Alluxio install tar file.

- alluxioLicenseDownloadURL - A reference to the S3 bucket location where you uploaded the Alluxio Enterprise Edition license file

Here is an example of launching the Enterprise Edition of Alluxio using the 3-workers size:

     $ aws cloudformation create-stack --stack-name My-Alluxio-Cluster \
        --disable-rollback \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
        --template-body file://./cloudformation/deploy-alluxio-on-aws.yaml \
        --tags "Key=Business-Unit,Value=Presales" \
               "Key=owner,Value=[CHANGE ME]" \
               "Key=Name,Value=My-Alluxio-Cluster" \
        --parameters ParameterKey=useVPC,ParameterValue=vpc-[CHANGE ME] \
                     ParameterKey=useSubnet,ParameterValue=subnet-[CHANGE ME] \
                     ParameterKey=securityGroupInboundSourceCidr,ParameterValue=0.0.0.0/0 \
                     ParameterKey=keypairName,ParameterValue=my-alluxio-keypair \
                     ParameterKey=clusterSize,ParameterValue=3-workers \
                     ParameterKey=alluxioS3BucketName,ParameterValue=my-alluxio-bucket \
                     ParameterKey=alluxioDownloadURL,ParameterValue=s3://my-alluxio-bucket/installers/alluxio-2.10.0-2.0-bin.tar.gz \
                     ParameterKey=alluxioLicenseDownloadURL,ParameterValue=s3://my-alluxio-bucket/installers/alluxio-enterprise-license.json

Here is an example of launching the Community Edition of Alluxio using the 3-worker size:

     $ aws cloudformation create-stack --stack-name My-Alluxio-Cluster \
        --disable-rollback \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
        --template-body file://./cloudformation/deploy_alluxio_on_aws.yaml \
        --tags "Key=Business-Unit,Value=Presales" \
               "Key=owner,Value=[CHANGE ME]" \
               "Key=Name,Value=My-Alluxio-Cluster" \
        --parameters ParameterKey=useVPC,ParameterValue=vpc-[CHANGE ME] \
                     ParameterKey=useSubnet,ParameterValue=subnet-[CHANGE ME] \
                     ParameterKey=securityGroupInboundSourceCidr,ParameterValue=0.0.0.0/0 \
                     ParameterKey=keypairName,ParameterValue=my-alluxio-keypair \
                     ParameterKey=clusterSize,ParameterValue=3-workers \
                     ParameterKey=alluxioS3BucketName,ParameterValue=my-alluxio-bucket

While the CloudFormation stack is being launched, you can query the status using commands like this:

     $ aws cloudformation describe-stacks --stack-name My-Alluxio-Cluster

     $ aws cloudformation describe-stack-events --stack-name My-Alluxio-Cluster

     $ aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE

If you want to destroy the cloudformation stack, you can use this command:

     $ aws cloudformation delete-stack --stack-name My-Alluxio-Cluster

### Step 5. Access the Alluxio Web console

Once the Alluxio cluster launch is complete, you can access the Alluxio Web console on any of the Alluxio master nodes. To get the IP addresses of the Alluxio master nodes, use the AWS CloudFormation console to view the "Resources" section of the stack, or use the following AWS CLI command:

     $ aws ec2 describe-instances --query 'Reservations[*].Instances[*].PrivateIpAddress'  --filters "Name=tag-key,Values=Name" "Name=tag-value,Values=My-Alluxio-Cluster-Alluxio-Master" --output=text

Point your Web browser to the one of the Alluxio master nodes like this:

     http://[MASTER IP ADDRESS]:19999

![Alluxio Web Console](https://github.com/gregpalmr/alluxio-aws-cloudformation/blob/main/images/alluxio-console-overview.png?raw=true)

Click on the "Workers" tab link and you will see the three Alluxio worker nodes that were launched using the above example:

![Alluxio Web Console](https://github.com/gregpalmr/alluxio-aws-cloudformation/blob/main/images/alluxio-console-workers.png?raw=true)

### Step 6. Run the Alluxio health checks

Alluxio provides a "runTests" command to help you determine if your Alluxio cluster is configured and working correctly. You will have to log into the Alluxio master node and run the command. Use these commands:

First, run the "alluxio fsadmin report" command to see if the Alluxio master nodes and worker nodes are healthy:

     $ ssh -i ~/.ssh/alluxio-keypair ec2-user@<MASTER NODE IP ADDRESS>

     $ sudo su - alluxio

     $ alluxio fsadmin report

You will see a summary output like this:

    Alluxio cluster summary:
        Master Address: 172.31.75.133:19998
        Web Port: 19999
        Rpc Port: 19998
        Started: 08-21-2023 19:05:31:859
        Uptime: 0 day(s), 0 hour(s), 1 minute(s), and 38 second(s)
        Version: enterprise-2.10.0-2.0
        Safe Mode: false
        Zookeeper Enabled: false
        Raft-based Journal: true
        Raft Journal Addresses:
            172.31.68.182:19200
            172.31.68.200:19200
            172.31.75.133:19200
        Master Address                   State    Version
        172.31.75.133:19998              PRIMARY  enterprise-2.10.0-2.0
        172.31.68.200:19998              STANDBY  enterprise-2.10.0-2.0
        172.31.68.182:19998              STANDBY  enterprise-2.10.0-2.0
        Live Workers: 3
        Lost Workers: 0
        Total Capacity: 230.73GB
            Tier: MEM  Size: 230.73GB
        Used Capacity: 0B
            Tier: MEM  Size: 0B
    Free Capacity: 230.73GB

You can also run the "runTests" command to test reading and writing to the under store (S3 bucket in this case):

     $ /opt/alluxio/bin/alluxio runTests

The runTests will output the success or failure of the checks. If you have some failures, you may reference the Alluxio troubleshooting documentation to help resolve the issues.

     See: https://docs.alluxio.io/os/user/stable/en/operation/Troubleshooting.html

You can view the files that were created by the Alluxio runTests command by clicking on the "Browse" tab link in the Alluxio Web console:

![Alluxio Web Console](https://github.com/gregpalmr/alluxio-aws-cloudformation/blob/main/images/alluxio-console-browse-test-files.png?raw=true)

### Summary

This github repo provides a CloudFormation template to quickly launch an Alluxio cluster in an AWS environment. If you have any questions or comments, please direct them to gregpalmr@gmail.com

