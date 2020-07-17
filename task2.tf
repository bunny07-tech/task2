provider "aws" {
  region     = "ap-south-1"
  profile = "vinod"
}

# KEY-PAIR-------------------------------------------------------------------
resource "tls_private_key" "task2key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "tomkey" {
  key_name = "tom-key"
  public_key = tls_private_key.task2key.public_key_openssh
}
#Creating Security Group---------------------------------------------------------
resource "aws_security_group" "SG" {
  name        = "MySecurityGroup"
  description = "Allow HTTP inbound traffic"
  
  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    description = "nfs from VPC"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name = "MySecurityGroup"
  }
}

# Creating Instance
#------------------------------------------------------------------------------------
resource "aws_instance" "myinstance" {
  ami           = "ami-0732b62d310b80e97"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.tomkey.key_name
  security_groups = ["MySecurityGroup"] 


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.task2key.private_key_pem
    host     = aws_instance.myinstance.public_ip
  }


  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }


  tags = {
    Name = "OS_TOM"
  }
}

# Output the public ip
output "outip"{
  value=aws_instance.myinstance.public_ip
}


resource "null_resource" "local1" {
  #Save the Public IP to a local text file

  provisioner "local-exec" {
    command = "echo ${aws_instance.myinstance.public_ip} > publicip.txt"
  }
}


resource "null_resource" "local2" {
  depends_on = [
    null_resource.remote1,aws_cloudfront_distribution.s3_distribution
  ]
  provisioner "local-exec" {
    command = "start chrome ${aws_instance.myinstance.public_ip}"
  }
}

#Output the availability_zone
output "outaz"{
  value=aws_instance.myinstance.subnet_id
}

#Creating EFS File System
resource "aws_efs_file_system" "my_file" {
  tags = {
    Name = "my_file"
  }
}

#Creating Mount targets
resource "aws_efs_mount_target" "mount_tar" {
  file_system_id = aws_efs_file_system.my_file.id
  subnet_id      = aws_instance.myinstance.subnet_id
}

#-----------------------------------------------------------------------------------


resource "null_resource" "remote1" {
  depends_on = [
    aws_efs_mount_target.mount_tar,
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.task2key.private_key_pem
    host     = aws_instance.myinstance.public_ip
  }


  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4 /dev/xvdh",
      "sudo mount /dev/xvdh /var/www/html/",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/bunny07-tech/task2.git /var/www/html/",
    ]
  }
} 

#Create a S3 Bucket
#With Read access for all users
resource "aws_s3_bucket" "buck" {
  bucket = "my-task2-terraform-bucket"
  force_destroy = true


  versioning {
    enabled = true
  }
  grant {
    type        = "Group"
    permissions = ["READ"]
    uri         = "http://acs.amazonaws.com/groups/global/AllUsers"
  }
  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}

#Add one image to the Bucket with public-read ACL
resource "aws_s3_bucket_object" "buck_obj" {
  bucket = "my-task2-terraform-bucket"
  key    = "ab.jpg"
  source = "ab.jpg"
   acl = "public-read"
  depends_on = [
    aws_s3_bucket.buck
  ]
}


locals {
  s3_origin_id = "myS3Origin"
}

#  create Cloudfront Distribution with the previously created S3 as the origin.

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.buck.bucket_regional_domain_name
    origin_id   = local.s3_origin_id
  }

custom_origin_config {
            http_port = 80
            https_port = 80
            origin_protocol_policy = "match-viewer"
            origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"] 

}
    }
       
    enabled = true
     is_ipv6_enabled = true
 
 default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id
    forwarded_values {
      query_string = false
     cookies {
        forward = "none"
      }
    }
 viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
}


  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

forwarded_values {
      query_string = false

  cookies {
        forward = "none"
      }
    }

   restrictions {
    geo_restriction {
      restriction_type = "none"
      
  }

viewer_certificate {
    cloudfront_default_certificate = true
  }
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.task2key.private_key_pem
    host     = aws_instance.myin.public_ip
  }

  // Generate Cloudfront URL for image and append to the HTML Page
  provisioner "remote-exec" {
    inline = [
      "sudo su << EOF",
      "echo \"<img src='http://${self.domain_name}/${aws_s3_bucket_object.buck_obj.key}' height='200px' width='200px'>\" >> /var/www/html/index.php",
      "EOF",
    ]
  }
}
