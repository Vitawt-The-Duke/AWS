#!/bin/bash
#
#******************************************************************************
#    Declaring ENV
#******************************************************************************
#
AWS_REGION="us-east-2"
VPC_NAME="My VPC"
VPC_CIDR="10.0.0.0/16"
SUBNET_PUBLIC_CIDR="10.0.1.0/24"
SUBNET_PUBLIC_AZ="us-east-2a"
SUBNET_PUBLIC_NAME="10.0.1.0 - us-east-2a"
SUBNET_PRIVATE_CIDR="10.0.2.0/24"
SUBNET_PRIVATE_AZ="us-east-2c"
SUBNET_PRIVATE_NAME="10.0.2.0 - us-east-2b"
CHECK_FREQUENCY=5
AWS_ACCESS_KEY_ID="######################"
AWS_SECRET_ACCESS_KEY="################################"
BUCKET_NAME="test-brddhghghghesfhefsfx"
RDS_DB_ID="test-db"
RDS_DB_ID_CLONE="test-db-restore"
RDS_DB_USR="minad"
RDS_DB_PWD="EJHSGvsfhvbs"
IAM_USERNAME="uzer"
IAM_POL_NAME="testcase"
RDS_SNAP_ID="testcasesnap"
COSRFILE="file://cors.json"
POLICYFILE="file://policytestcasepol.json"
ASEC_GROUP="testsecgroup"
#******************************************************************************
#    installing dependcies
#******************************************************************************
sudo su
yum update
yum install -y \
python34 \
python34-setuptools \ 
jq \
wget \ 
git
easy_install-3.4 pip
exit
pip3 install awscli --upgrade --user
#******************************************************************************
#    installing and configuring aws CLI
#******************************************************************************
aws configure \
$AWS_ACCESS_KEY_ID \
$AWS_SECRET_ACCESS_KEY \
us-east-2 \
json
#
#******************************************************************************
#    AWS VPC Creation Shell Script
#https://github.com/kovarus/aws-cli-create-vpcs/blob/master/aws-cli-create-vpc.sh
#******************************************************************************
#==============================================================================
#   AUTHOR:    Joe Arauzo
#==============================================================================
#
# Create VPC
echo "Creating VPC in preferred region..."
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block $VPC_CIDR \
  --query 'Vpc.{VpcId:VpcId}' \
  --output text \
  --region $AWS_REGION)
echo "  VPC ID '$VPC_ID' CREATED in '$AWS_REGION' region."

# Add Name tag to VPC
aws ec2 create-tags \
  --resources $VPC_ID \
  --tags "Key=Name,Value=test" \
  --region $AWS_REGION
echo "  VPC ID '$VPC_ID' NAMED as 'test'."

# Create Public Subnet
echo "Creating Public Subnet..."
SUBNET_PUBLIC_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $SUBNET_PUBLIC_CIDR \
  --availability-zone $SUBNET_PUBLIC_AZ \
  --query 'Subnet.{SubnetId:SubnetId}' \
  --output text \
  --region $AWS_REGION)
echo "  Subnet ID '$SUBNET_PUBLIC_ID' CREATED in '$SUBNET_PUBLIC_AZ'" \
  "Availability Zone."

# Add Name tag to Public Subnet
aws ec2 create-tags \
  --resources $SUBNET_PUBLIC_ID \
  --tags "Key=Name,Value=$SUBNET_PUBLIC_NAME" \
  --region $AWS_REGION
echo "  Subnet ID '$SUBNET_PUBLIC_ID' NAMED as" \
  "'$SUBNET_PUBLIC_NAME'."

# Create Private Subnet
echo "Creating Private Subnet..."
SUBNET_PRIVATE_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $SUBNET_PRIVATE_CIDR \
  --availability-zone $SUBNET_PRIVATE_AZ \
  --query 'Subnet.{SubnetId:SubnetId}' \
  --output text \
  --region $AWS_REGION)
echo "  Subnet ID '$SUBNET_PRIVATE_ID' CREATED in '$SUBNET_PRIVATE_AZ'" \
  "Availability Zone."

# Add Name tag to Private Subnet
aws ec2 create-tags \
  --resources $SUBNET_PRIVATE_ID \
  --tags "Key=Name,Value=$SUBNET_PRIVATE_NAME" \
  --region $AWS_REGION
echo "  Subnet ID '$SUBNET_PRIVATE_ID' NAMED as '$SUBNET_PRIVATE_NAME'."

# Create Internet gateway
echo "Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
  --query 'InternetGateway.{InternetGatewayId:InternetGatewayId}' \
  --output text \
  --region $AWS_REGION)
echo "  Internet Gateway ID '$IGW_ID' CREATED."

# Attach Internet gateway to your VPC
aws ec2 attach-internet-gateway \
  --vpc-id $VPC_ID \
  --internet-gateway-id $IGW_ID \
  --region $AWS_REGION
echo "  Internet Gateway ID '$IGW_ID' ATTACHED to VPC ID '$VPC_ID'."

# Create Route Table
echo "Creating Route Table..."
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --query 'RouteTable.{RouteTableId:RouteTableId}' \
  --output text \
  --region $AWS_REGION)
echo "  Route Table ID '$ROUTE_TABLE_ID' CREATED."

# Create route to Internet Gateway
RESULT=$(aws ec2 create-route \
  --route-table-id $ROUTE_TABLE_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID \
  --region $AWS_REGION)
echo "  Route to '0.0.0.0/0' via Internet Gateway ID ${RED}'$IGW_ID' ADDED to" \
  "Route Table ID '$ROUTE_TABLE_ID'."

# Associate Public Subnet with Route Table
RESULT=$(aws ec2 associate-route-table  \
  --subnet-id $SUBNET_PUBLIC_ID \
  --route-table-id $ROUTE_TABLE_ID \
  --region $AWS_REGION)
echo "  Public Subnet ID '$SUBNET_PUBLIC_ID' ASSOCIATED with Route Table ID" \
  "'$ROUTE_TABLE_ID'."

# Enable Auto-assign Public IP on Public Subnet
aws ec2 modify-subnet-attribute \
  --subnet-id $SUBNET_PUBLIC_ID \
  --map-public-ip-on-launch \
  --region $AWS_REGION
echo "  'Auto-assign Public IP' ENABLED on Public Subnet ID" \
  "'$SUBNET_PUBLIC_ID'."

# Allocate Elastic IP Address for NAT Gateway
echo "Creating NAT Gateway..."
EIP_ALLOC_ID=$(aws ec2 allocate-address \
  --domain vpc \
  --query '{AllocationId:AllocationId}' \
  --output text \
  --region $AWS_REGION)
echo "  Elastic IP address ID '$EIP_ALLOC_ID' ALLOCATED."

# Create NAT Gateway
NAT_GW_ID=$(aws ec2 create-nat-gateway \
  --subnet-id $SUBNET_PUBLIC_ID \
  --allocation-id $EIP_ALLOC_ID \
  --query 'NatGateway.{NatGatewayId:NatGatewayId}' \
  --output text \
  --region $AWS_REGION)
FORMATTED_MSG="Creating NAT Gateway ID '$NAT_GW_ID' and waiting for it to "
FORMATTED_MSG+="become available.\n    Please BE PATIENT as this can take some "
FORMATTED_MSG+="time to complete.\n    ......\n"
printf "  $FORMATTED_MSG"
FORMATTED_MSG="STATUS: %s  -  %02dh:%02dm:%02ds elapsed while waiting for NAT "
FORMATTED_MSG+="Gateway to become available..."
SECONDS=0
LAST_CHECK=0
STATE='PENDING'
until [[ $STATE == 'AVAILABLE' ]]; do
  INTERVAL=$SECONDS-$LAST_CHECK
  if [[ $INTERVAL -ge $CHECK_FREQUENCY ]]; then
    STATE=$(aws ec2 describe-nat-gateways \
      --nat-gateway-ids $NAT_GW_ID \
      --query 'NatGateways[*].{State:State}' \
      --output text \
      --region $AWS_REGION)
    STATE=$(echo $STATE | tr '[:lower:]' '[:upper:]')
    LAST_CHECK=$SECONDS
  fi
  SECS=$SECONDS
  STATUS_MSG=$(printf "$FORMATTED_MSG" \
    $STATE $(($SECS/3600)) $(($SECS%3600/60)) $(($SECS%60)))
  printf "    $STATUS_MSG\033[0K\r"
  sleep 1
done
printf "\n    ......\n  NAT Gateway ID '$NAT_GW_ID' is now AVAILABLE.\n"

# Create route to NAT Gateway
MAIN_ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
  --filters Name=vpc-id,Values=$VPC_ID Name=association.main,Values=true \
  --query 'RouteTables[*].{RouteTableId:RouteTableId}' \
  --output text \
  --region $AWS_REGION)
echo "  Main Route Table ID is '$MAIN_ROUTE_TABLE_ID'."
RESULT=$(aws ec2 create-route \
  --route-table-id $MAIN_ROUTE_TABLE_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $NAT_GW_ID \
  --region $AWS_REGION)
echo "  Route to '0.0.0.0/0' via NAT Gateway with ID '$NAT_GW_ID' ADDED to" \
  "Route Table ID '$MAIN_ROUTE_TABLE_ID'."
echo "COMPLETED"
#******************************************************************************
#    END AWS VPC Creation Shell Script
#******************************************************************************

#******************************************************************************
#    Create s3 bucket
#Naming: https://docs.aws.amazon.com/AmazonS3/latest/dev/BucketRestrictions.html
#******************************************************************************
aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --region us-east-1
echo "s3 bucket $BUCKET_NAME created"
#
#******************************************************************************
#    CORS apply
#******************************************************************************
#
aws s3api put-bucket-cors \
  --bucket $BUCKET_NAME \
  --cors-configuration $CORSFILE
echo "CORS for s3 bucket $BUCKET_NAME applyed"
#
#******************************************************************************
#    IAM user creation and PO
#******************************************************************************
#
aws iam create-user --user-name $IAM_USERNAME
echo "IAM user $IAM_USERNAME created"
aws iam put-user-policy --user-name $IAM_USERNAME --policy-name $IAM_POL_NAME --policy-document $POLICYFILE
echo "IAM policy $IAM_POL_NAME created from $POLICYFILE and applyed to $IAM_USERNAME"
# 
#******************************************************************************
#    Create RDS database instance
# db.t2.micro allow to use 750hrs of instance in free tire
#******************************************************************************
aws rds create-db-instance \
  --db-instance-class db.t2.micro \
  --engine postgres \
  --db-name testdb \
  --db-instance-identifier $RDS_DB_ID \
  --master-username $RDS_DB_USR \
  --master-user-password $RDS_DB_PWD \
  --allocated-storage 10 \
echo "RDS database with $RDS_DB_ID created"
#
#******************************************************************************
#    Snapshoting-cloning-restoring created RDS database instance
#******************************************************************************
aws rds create-db-snapshot \
  --db-instance-identifier $RDS_DB_ID \
  --db-snapshot-identifier $RDS_SNAP_ID
echo "RDS database snapshot  with ID $RDS_SNAP_ID from DB_ID $RDS_DB_ID created"
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier $RDS_DB_ID_CLONE \
  --db-snapshot-identifier $RDS_SNAP_ID
echo "RDS database $RDS_DB_ID_CLONE restored from snapshot $RDS_SNAP_ID"
#                                                       #
#                                                       #
#                 DELETING RDS STUFF                    #
#                                                       #
#                                                       #
read -n 1 -r -s -p $'"Press any key to continiune. It will remove all previously created RDS stuff"\n'
aws rds stop-db-instance \
  --db-instance-identifier $RDS_DB_ID \
  --db-instance-identifier $RDS_DB_ID_CLONE \ 
aws rds delete-db-snapshot \
  --db-snapshot-identifier $RDS_SNAP_ID
aws rds delete-db-instance \
  --skip-final-snapshot \
  --delete-automated-backups \
  --db-instance-identifier $RDS_DB_ID \
  --db-instance-identifier $RDS_DB_ID_CLONE
echo "seems all have been marked 4 deletion. please run 'aws rds describe-db-instances' in 10 mins 2 ensure"
#
#******************************************************************************
#    Amazon security group
#******************************************************************************
aws ec2 create-security-group \
--description testsecgroup \
--group-name $ASEC_GROUP \
--vpc-id $VPC_ID
