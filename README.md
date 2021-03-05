# terraform-aws
Short Terraform code to deploy instances and services to AWS

Create a non-public S3 bucket.
Upload ​ index.html​ to S3 bucket.
Create a private EC2 instance.
Create a custom policy for the EC2 instance to access only the created S3 bucket.
Install Docker into EC2 instance.
Run NGINX Docker container.
Create a python/shell script to copy the uploaded file from the S3 bucket to NGINX
webroot.
Push NGINX logs to CloudWatch.
Create a CloudWatch dashboard to monitor EC2 instance and NGINX.
Create public EC2 instance to proxy HTTP and ssh traffic to the private EC2 instance.
