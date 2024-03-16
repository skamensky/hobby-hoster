
locals {
  regions = jsondecode(file("${path.module}/config.json"))["regions"]
}


resource "aws_instance" "ec2_instance" {
  count         = length(local.regions)
  ami           = local.regions[count.index]["ami"]
  availability_zone = local.regions[count.index]["availability_zone"]
  instance_type = var.instance_type
  subnet_id     = aws_subnet.main[count.index].id
  vpc_security_group_ids = [aws_security_group.allow_web[count.index].id, aws_security_group.allow_ssh[count.index].id]

  key_name = var.ssh_pub_key_path
  provisioner "file" {
    source      = "${var.project_root}/hobby-hoster/bootstrap/"
    destination = "/mnt/data/bootstrap"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /mnt/data/bootstrap/init.sh",
      "/mnt/data/bootstrap/init.sh",
    ]
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.ssh_private_key_path)
    host        = self.public_ip
  }

  tags = {
    Name = "${vars.base_tag}-instance-${local.regions[count.index]["region"]}"
  }
}

resource "aws_vpc" "main" {
  count      = length(local.regions)
  cidr_block = "10.0.0.0/16"
  
  tags = {
    Name = "${vars.base_tag}-main-vpc-${local.regions[count.index]["region"]}"
  }
}

resource "aws_subnet" "main" {
  count                   = length(local.regions)
  vpc_id                  = aws_vpc.main[count.index].id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = local.regions[count.index]["availability_zone"]
  map_public_ip_on_launch = true
  
  tags = {
    Name = "${vars.base_tag}-main-subnet-${local.regions[count.index]["region"]}"
  }
}


resource "aws_security_group" "allow_web" {
  count       = length(local.regions)
  name        = "allow_web_traffic-${local.regions[count.index]["region"]}"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.main[count.index].id
  

  tags = {
    Name = "${vars.base_tag}-allow-web-${local.regions[count.index]["region"]}"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "allow_ssh" {
  count                    = length(var.allowed_ssh_sources) * length(local.regions)
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  cidr_blocks              = [var.allowed_ssh_sources[count.index % length(var.allowed_ssh_sources)]]
  security_group_id        = aws_security_group.allow_web[count.index % length(local.regions)].id
  description              = "Allow SSH inbound traffic"
}


output "instance_public_ips" {
  value = {
    for i in range(length(aws_instance.ec2_instance)) : local.regions[i]["region"] => aws_instance.ec2_instance[i].public_ip
  }
  description = "Mapping of regions to instance public IPs"
}