resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = file(local.ssh_pub_key_path)
}

resource "aws_instance" "ec2_instance" {
  ami                    = local.region.ami
  availability_zone      = local.region.availability_zone
  instance_type          = local.region.instance_type
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.allow_web.id, aws_security_group.allow_ssh.id]

  key_name = aws_key_pair.deployer.key_name

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(local.ssh_private_key_path)
    host        = self.public_ip
  }

  tags = {
    Name = "${local.base_tag}-instance-${var.region_name}"
  }
}

resource "null_resource" "init_script_exec" {
  # Ensures this resource is recreated if the instance, init script, or volume attachment changes
  triggers = {
    instance_id          = aws_instance.ec2_instance.id
    volume_attachment_id = aws_volume_attachment.ebs_attach.id
    init_script_hash     = filesha256("${local.project_root}/hobby-hoster/bootstrap/init.sh")
  }

  # Define connection details
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(local.ssh_private_key_path)
    host        = aws_instance.ec2_instance.public_ip
  }

  // this is here because provisioner "file" doesn't reupload if it detects the target file is already there (even if the file content is changed).
  // this forces the file to be reuploaded
  provisioner "remote-exec" {
    inline = [
      "sudo rm -rf /tmp/bootstrap/",
    ]
  }

  provisioner "file" {
    source      = "${local.project_root}/hobby-hoster/bootstrap"
    destination = "/tmp/bootstrap/"
  }

  # Execute the script after the EBS volume is attached since it depends on it, passing the attached volume size as the first argument
  provisioner "remote-exec" {
    inline = [
      "sudo bash /tmp/bootstrap/init.sh ${local.attached_volume_size}",
    ]
  }
  # Explicitly depend on the EC2 instance and EBS volume attachment
  depends_on = [
    aws_instance.ec2_instance,
    aws_volume_attachment.ebs_attach,
  ]

}


resource "null_resource" "env_file_update" {
  # This resource triggers when there's a change in the .env file
  triggers = {
    env_file_hash = filesha256("${local.project_root}/.env")
  }

  # Define connection details
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(local.ssh_private_key_path)
    host        = aws_instance.ec2_instance.public_ip
  }

  # Copy the .env file to the specified location on the EC2 instance
  provisioner "file" {
    source      = "${local.project_root}/.env"
    destination = "/mnt/data/.env"
  }

  # Explicitly depend on the EC2 instance being up
  depends_on = [
    aws_instance.ec2_instance,
  ]
}





resource "null_resource" "build_agent" {
  # This section is responsible for setting up the build agent on the EC2 instance.
  # It triggers the build agent setup when there are changes detected in the bootstrap or the agent folder's content.
  triggers = {
    bootstrap_triggers = null_resource.init_script_exec.id
    agent_folder_hash    = join("", [for f in fileset("${local.project_root}/hobby-hoster/agent", "**/*") : filesha256("${local.project_root}/hobby-hoster/agent/${f}")])
  }

  # Define connection details
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(local.ssh_private_key_path)
    host        = aws_instance.ec2_instance.public_ip
  }

  // this is here because provisioner "file" doesn't reupload if it detects the target file is already there (even if the file content is changed).
  // this forces the file to be reuploaded
  provisioner "remote-exec" {
    inline = [
      "sudo rm -rf /tmp/agent/",
      "sudo rm -rf /tmp/bootstrap/",
    ]
  }


  provisioner "file" {
    source      = "${local.project_root}/hobby-hoster/bootstrap"
    destination = "/tmp/bootstrap/"
  }

  provisioner "file" {
    source      = "${local.project_root}/hobby-hoster/agent"
    destination = "/tmp/agent/"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo bash /tmp/bootstrap/build_agent.sh",
    ]
  }
  depends_on = [
    null_resource.init_script_exec
  ]
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "${local.base_tag}-main-vpc-${var.region_name}"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.base_tag}-igw-${var.region_name}"
  }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.base_tag}-rt-${var.region_name}"
  }
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = local.region.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.base_tag}-main-subnet-${var.region_name}"
  }
}


resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic-${var.region_name}"
  description = "Allow web inbound traffic"
  vpc_id      = aws_vpc.main.id


  tags = {
    Name = "${local.base_tag}-allow-web-${var.region_name}"
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
resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh_traffic-${var.region_name}"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.base_tag}-allow-ssh-${var.region_name}"
  }

  dynamic "ingress" {
    for_each = local.allowed_ssh_sources
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["${ingress.value}/32"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "public_ip" {
  value = aws_instance.ec2_instance.public_ip
}
