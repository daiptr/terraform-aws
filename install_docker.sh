#!/bin/bash
exec &> /tmp/install_docker.txt
sudo yum update -y
sleep 20s

#installing cloudwatch agent
sudo yum install -y awslogs
sleep 10s

# installing docker instance and running nginx server and push nginx logs to cloudwatch group d"ocker_inginx"
sudo yum install docker -y
sleep 20s
sudo dockerd &> /dev/null &
sleep 10s
#sudo docker run --name organizationInginxServer -p 80:80 -d nginx
sudo docker run --log-driver="awslogs" --log-opt awslogs-region="us-east-1" --log-opt awslogs-group="docker_inginx" --log-opt awslogs-stream="docker-inginx-logs" --name organizationInginxServer -p 80:80 -d nginx
sleep 20s

# copying index.html from S3 to private ec2
aws s3 cp s3://organization-daiptr-bucket/index.html /tmp
sleep 5s

# copying index.html to docker container
variable_name=$(sudo docker inspect -f '{{.Id}}' organizationInginxServer)
sleep 5s
sudo docker cp /tmp/index.html $variable_name:/usr/share/nginx/html

