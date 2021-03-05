#configuring the provider
provider "aws" {
  region = "us-east-1"
}

#<<MID>>#

#####################################################################################################
# Prerequisites - creating an AWS VPC network with private and public subnets, NAT and IP addresses #
#####################################################################################################

resource "aws_vpc" "organization-vpc" {                       # creating a VPC
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "organization_gw" {           # creating Internet Gateway for external access
  vpc_id = aws_vpc.organization-vpc.id
  tags = {
    Name = "organization gateway"
  }
}

resource "aws_nat_gateway" "nat_gw" {                         # creating NAT for private subnet to access the external resources and S3
  allocation_id = aws_eip.elastic_ip.id
  subnet_id     = aws_subnet.public-subnet.id
  depends_on = [aws_internet_gateway.organization_gw]

  tags = {
    Name = "gw NAT"
  }
}

resource "aws_eip" "elastic_ip" {                                     # associating elastic IP address with NAT
  vpc      = true
  depends_on = [aws_internet_gateway.organization_gw]
}

resource "aws_route_table" "organization-private-route-table" {      # adding the routing table for PRIVATE SUBNET
  vpc_id = aws_vpc.organization-vpc.id

  route {
    cidr_block = "0.0.0.0/0"                            # all traffic goes to NAT
    gateway_id = aws_nat_gateway.nat_gw.id
  }

  tags = {
    Name = "organization private routing table for NAT"
  }
}

resource "aws_route_table" "organization-route-table" {      # adding the routing table FOR PUBLIC SUBNET
  vpc_id = aws_vpc.organization-vpc.id

  route {
    cidr_block = "0.0.0.0/0"                            # all traffic goes to internet gateway
    gateway_id = aws_internet_gateway.organization_gw.id
  }

  tags = {
    Name = "organization public routing table"
  }
}

resource "aws_subnet" "public-subnet" {                             # creating a public subnet
  vpc_id     = aws_vpc.organization-vpc.id
  cidr_block = "10.0.0.0/24"
  availability_zone = "us-east-1a"
  #map_public_ip_on_launch = true

  tags = {
    Name = "organization public subnet"
  }
}

resource "aws_subnet" "private_subnet" {                             # creating a private subnet
  vpc_id     = aws_vpc.organization-vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"


  tags = {
    Name = "organization private subnet"
  }
}

resource "aws_route_table_association" "organization-route" {                        # associating subnet with PUBLIC routing table
  subnet_id      = aws_subnet.public-subnet.id
  route_table_id = aws_route_table.organization-route-table.id
}

resource "aws_route_table_association" "organization-private-route" {               # associating subnet with PRIVATE routing table
  subnet_id = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.organization-private-route-table.id
}

resource "aws_security_group" "allow" {                              # allowing port 80 and 443 to be open for external access to VPC
  name        = "allow_web"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.organization-vpc.id

  ingress {
    description = "https"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]                             # everyone can access port 443
  }

  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]                             # everyone can access port 80
  }

  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]                             # everyone can access port 22
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

resource "aws_network_interface" "private-interface" {              # creating the network interface for private instance,no external IP address
  subnet_id       = aws_subnet.private_subnet.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow.id]
}

resource "aws_network_interface" "public-interface" {              # creating the network interface for public instance, assigning external IP address
  subnet_id       = aws_subnet.public-subnet.id
  private_ips     = ["10.0.0.50"]
  security_groups = [aws_security_group.allow.id]
}

resource "aws_eip" "public" {                                       # creating elastic IP so public instance would be reachable from the outside
  vpc                       = true
  network_interface         = aws_network_interface.public-interface.id
  associate_with_private_ip = "10.0.0.50"
  depends_on = [aws_internet_gateway.organization_gw]
}

output "external_ip_for_public_ec2" {
  value = aws_instance.organization-ec2-public.public_ip
}

#####################################
# 1. Create a non-public S3 bucket. #
#####################################

resource "aws_s3_bucket" "organization-daiptr-bucket" {
  bucket = "organization-daiptr-bucket"
  acl    = "private"
  tags = {
    Name = "organization Bucket"
  }
}

###############################################################################################
# 2. Upload index.html to S3 bucket. (also uploading .pem key file to connect to private ec2) #
###############################################################################################

resource "aws_s3_bucket_object" "index" {
  bucket = aws_s3_bucket.organization-daiptr-bucket.id
  key    = "index.html"
  source = "index.html"
  etag = filemd5("index.html")
}

#####################################
# 3. Create a private EC2 instance. #
#####################################
# 5. Install Docker into EC2 instance.
# 6. Run NGINX Docker container.
# 7. Create a python/shell script to copy the uploaded file from the S3 bucket to NGINX webroot.

resource "aws_instance" "organization-ec2-private" {
  ami = "ami-0be2609ba883822ec"
  instance_type = "t2.micro"
  availability_zone = "us-east-1a"
  key_name = "organization-key"
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.id
  user_data = file("install_docker.sh")                             # running bash script which implements steps 5, 6, 7

  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.private-interface.id
  }

  tags = {
    Name = "organization-ec2-private"
  }
}

locals {                                                #getting ec2 private instance id for cloudwatch dashboard
  ec2_id = aws_instance.organization-ec2-private.id
}

###################################################################################################################################
# 4. Create a custom policy for the EC2 instance to access only the created S3 bucket. Adding a policy to push logs to cloudwatch #
###################################################################################################################################

resource "aws_iam_role" "ec2-role" {
name = "ec2-role"

assume_role_policy = <<EOF
{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Action": "sts:AssumeRole",
          "Principal": {
            "Service": "ec2.amazonaws.com"
          },
          "Effect": "Allow",
          "Sid": ""
        }
      ]
    }
EOF
}

resource "aws_iam_policy" "ec2-policy" {
name        = "ec2-policy"
description = "ec2 policy to access s3 bucket only"

policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:*",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ec2-role-attach" {
role       = aws_iam_role.ec2-role.name
policy_arn = aws_iam_policy.ec2-policy.arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
name = "ec2_profile"
role = aws_iam_role.ec2-role.name
}

#####################################
# 8. Push NGINX logs to CloudWatch. #
#####################################

resource "aws_cloudwatch_log_group" "docker_inginx" {  # creating a log group for cloudwatch. Log push activated in install_docker.sh file when running the container
  name = "docker_inginx"

  tags = {
    Environment = "organization"
    Application = "docker_inginx"
  }
}

#######################################################################
# 9. Create a CloudWatch dashboard to monitor EC2 instance and NGINX. #
#######################################################################

resource "aws_cloudwatch_dashboard" "organization_dashboard" {
  dashboard_name = "organization-dashboard"

  dashboard_body = <<EOF
{
  "widgets": [
    {
      "type": "metric",
      "x": 0,
      "y": 0,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [
            "AWS/EC2",
            "CPUUtilization",
            "InstanceId",
            "${local.ec2_id}"
          ]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-east-1",
        "title": "EC2 Instance ${local.ec2_id} CPU"
      }
    },
    {
      "type": "log",
      "x": 0,
      "y": 7,
      "width": 24,
      "height": 6,
      "properties": {
        "query": "SOURCE 'docker_inginx' | FIELDS @timestamp, @message\n| sort @timestamp desc | limit 25",
        "region": "us-east-1",
        "view": "table",
        "title": "Nginx logs"
      }
    }
  ]
}
EOF
}

#############################################################################################
# 10. Create public EC2 instance to proxy HTTP and ssh traffic to the private EC2 instance. #
#############################################################################################

resource "aws_instance" "organization-ec2-public" {
  ami = "ami-0be2609ba883822ec"
  instance_type = "t2.micro"
  availability_zone = "us-east-1a"
  key_name = "organization-key"
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.id
  depends_on = [aws_instance.organization-ec2-private]

  user_data = file("make_tunnel.sh")                                       # running bash script which edits iptables for port forwarding to private ec2 instance

  network_interface {
    device_index = 0
    network_interface_id = aws_network_interface.public-interface.id
  }

  tags = {
    Name = "organization-ec2-public"
  }
}

# 11. Create pipelines for deployment into both EC2 instances.

#<<SENIOR>>

# 12. Create three users credential secrets in Amazon Secrets Manager.
# 13. Create a python/shell script to create three UNIX users (in public EC2 instance) based on credentials in Amazon Secrets Manager.
# 14. Set up Grafana and configure it to get metrics from CloudWatch about EC2 instances.
# 15. Set up Docker with Ansible.

