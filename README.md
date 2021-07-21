# alluxio-aws-cloudformation

An AWS Cloudformation template to launch an Alluxio cluster that uses S3 as the under filesystem (UFS).

## Background

This AWS Cloudformation template launches Alluxio on AWS Infrastructure and creates the following resources:

- EC2 Instances (m5.2xlarge for Alluxio masters, r5d.4xlarge for Alluxio workers)
- Auto Scaling Group for Alluxio workers
- Security Group rules for intra-node communications
- Security Group rules for external access (can be restricted to your IP address)
- Integration with your existing VPC and subnets

This template launches one Alluxio master node, and a number of Alluxio worker nodes as specified. It configures and launches the Alluxio master and worker daemons and optionally sets up passwordless SSH between the master node and the workers.

## Prerequisites

To use this AWS Cloudformation template, you need the following:

- A valid AWS account with the following IAM role policies:
     - AmazonEC2FullAccess
     - AmazonS3FullAccess

     or

     - Enough permissions to launch a cloudformation stack and access an S3 bucket

     - See: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html

- Enough quota for the number of r5d.4xlarge EC2 instances need for your Alluxio worker nodes

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

Use your AWS S3 console or the AWS CLI to copy the Alluxio tar file to the bucket. For example:

     $ aws s3 cp alluxio-2.6.0-bin.tar.gz s3://alluxio-bucket/installers/
 
### Step 3. Optionally upload SSH keys to the S3 bucket

You can optionally create and upload SSH keys to be used for passwordless SSH access from the Alluxio master node to the worker nodes. Use these commands:

     $ ssh-keygen -f alluxio-keypair -t rsa -N ''

     $ aws s3 cp alluxio-keypair s3://alluxio-bucket/cloudformation/alluxio-keypair

     $ aws s3 cp alluxio-keypair.pub s3://alluxio-bucket/cloudformation/alluxio-keypair.pub

### Step 4. Run the AWS create stack command

AWS provides a "create-stack" command to launch a coordinated infrastructure creation process. Use the provided Cloudformation template to launch an Alluxio cluster. The template supports mulitiple cluster sizes including:
- 1-worker - One Alluxio master node (m5.2xlarge) and one worker node (r5d.4xlarge)
- 3-small-workers - One Alluxio master node (t2.medium) and three worker nodes (t2.medium)
- 3-workers - One Alluxio master node (m5.2xlarge) and three worker nodes (r5d.4xlarge)
- 5-workers - One Alluxio master node (m5.2xlarge) and five worker nodes (r5d.4xlarge)
- 10-workers - One Alluxio master node (m5.2xlarge) and ten worker nodes (r5d.4xlarge)
- 25-workers - One Alluxio master node (m5.2xlarge) and twenty-five worker nodes (r5d.4xlarge)
- 50-workers - One Alluxio master node (m5.2xlarge) and one fifty worker nodes (r5d.4xlarge)

The cloudformation template requires some user supplied options, including:

- useVPC - The existing VPC to use. Your AWS administrator can supply this or you can create a VPC yourself using the AWS VPC console or the AWS CLI. It should take the form of: vpc-ad49er61ba

- useSubnet - The existing VPC subnet to use. Your AWS administrator can supply this or you can create a subnet using the AWS VPC console or the AWS CLI. It should take the form of: subnet-0fcea85e31ff88608

- keypairName - The AWS keypair to use when launching the EC2 instances. The keypair will allow you to SSH to your EC2 instances later. Your AWS administrator can supply this or you can create a keypair using the AWS IAM console or the AWS CLI.

- clusterSize - The size of the Alluxio cluster to launch (see above).

- alluxioS3BucketName - The name of the S3 bucket that you created for Alluxio to use as an under filesystem (UFS).

- alluxioS3BucketAccessKeyId - The aws_access_key_id to allow Alluxio to access the S3 bucket.

- alluxioS3BucketSecretAccessKey - The aws_secret_access_key to allow Alluxio to access the S3 bucket.

- alluxioDownloadURL - A reference to the S3 bucket location where you uploaded the Alluxio install tar file.

Here is an example of launching using the 3-small-workers option:

     $ aws cloudformation create-stack --stack-name My-Alluxio-Cluster \
        --disable-rollback \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
        --template-body cloudformation/deploy_alluxio_on_aws.yaml \
        --tags "Key=Business-Unit,Value=Presales" \
               "Key=owner,Value=[CHANGE ME]" \
               "Key=Name,Value=My-Alluxio-Cluster" \
        --parameters ParameterKey=useVPC,ParameterValue=vpc-[CHANGE ME] \
                     ParameterKey=useSubnet,ParameterValue=subnet-[CHANGE ME] \
                     ParameterKey=securityGroupInboundSourceCidr,ParameterValue=0.0.0.0/0 \
                     ParameterKey=keypairName,ParameterValue=My-Alluxio-Keypair \
                     ParameterKey=clusterSize,ParameterValue=3-small-workers \
                     ParameterKey=alluxioS3BucketName,ParameterValue=alluxio-bucket \
                     ParameterKey=alluxioS3BucketAccessKeyId,ParameterValue=[CHANGE ME] \
                     ParameterKey=alluxioS3BucketSecretAccessKey,ParameterValue=[CHANGE ME] \
                     ParameterKey=alluxioDownloadURL,ParameterValue=s3://alluxio-bucket/installers/alluxio-2.6.0-bin.tar.gz

While the cloudformation stack is being launched, you can query the status using commands like this:

     $ aws cloudformation describe-stacks --stack-name My-Alluxio-Cluster

     $ aws cloudformation describe-stack-events --stack-name My-Alluxio-Cluster

     $ aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE

If you want to destroy the cloudformation stack, you can use this command:

     $ aws cloudformation delete-stack --stack-name My-Alluxio-Cluster

### Step 5. Access the Alluxio Web console

Once the Alluxio cluster launch is complete, you can access the Alluxio Web console on the Alluxio master node. To get the IP address of the Alluxio master node, use the AWS Cloudformation console to view the "Outputs" section of the stack, or use the following AWS CLI command:

     $ aws cloudformation describe-stacks --stack-name My-Alluxio-Cluster --query "Stacks[0].Outputs[?OutputKey=='AlluxiUIo'].OutputValue" --output text

Use the HTTP URL displayed in the "output" and copy/paste it to your Web browser.

### Step 6. Run the Alluxio health checks

Alluxio provides a "runTests" command to help you determine if your Alluxio cluster is configured and working correctly. You will have to log into the Alluxio master node and run the command. Use these commands:

     $ ssh -i ~/.ssh/alluxio-keypair centos@<MASTER NODE IP_ADDRESS>

     $ /opt/alluxio/bin/alluxio runTests

The runTests will output the success or failure of the checks. If you have some failures, you may reference the Alluxio troubleshooting documentation to help resolve the issues.

     See: https://docs.alluxio.io/os/user/stable/en/operation/Troubleshooting.html

### Summary

This github repo provides a cloudformation template to quickly launch an Alluxio cluster in an AWS environment. If you have any questions or comments, please direct them to gregpalmr@gmail.com

