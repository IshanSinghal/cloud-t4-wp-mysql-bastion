provider "aws" {
	region = "ap-south-1"
	profile = "ishan_tf"
}

resource "aws_vpc" "myvpc" {
  cidr_block       = "192.168.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = "true"
  tags = {
    Name = "myvpct3"
  }
}


resource "aws_subnet" "subnet1-public" {
  depends_on = [ aws_vpc.myvpc ]
  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "192.168.1.0/24"
  availability_zone = "ap-south-1a"

  tags = {
    Name = "public_subnet"
  }
}

resource "aws_subnet" "subnet2-private" {
  depends_on = [ aws_vpc.myvpc ]
  vpc_id     = aws_vpc.myvpc.id
  cidr_block = "192.168.2.0/24"
  availability_zone = "ap-south-1b"
  tags = {
    Name = "private_subnet"
  }
}


resource "aws_security_group" "sg1" {
  depends_on = [ aws_vpc.myvpc ]
  name        = "sg1-public-wordpress"
  description = "Allow inbound traffic ssh and http"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description = "allow ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "allow http"
    from_port   = 80
    to_port     = 80
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
    Name = "sg1-public-wordpress"
  }
}

resource "aws_security_group" "sg2" {
  depends_on = [ aws_vpc.myvpc ]
  name        = "sg2-private-mysql"
  description = "Allow inbound traffic mysql from public subnet security group"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description = "allow ssh"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = ["${aws_security_group.sg1.id}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg2-private-mysql"
  }
}

resource "aws_security_group" "sg3" {
  depends_on = [ aws_vpc.myvpc ]
  name        = "sg1-public-bastion"
  description = "Allow inbound ssh traffic bastion host"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description = "allow ssh"
    from_port   = 22
    to_port     = 22
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
    Name = "sg1-public-bastion"
  }
}

resource "aws_security_group" "sg4" {
  depends_on = [ aws_vpc.myvpc ]
  name        = "sg2-private-bastion"
  description = "Allow inbound ssh to mysql from bastion host sg"
  vpc_id      = aws_vpc.myvpc.id

  ingress {
    description = "allow ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = ["${aws_security_group.sg3.id}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg2-private-bastion"
  }
}



resource "aws_internet_gateway" "mygw" {
  depends_on = [ aws_vpc.myvpc ]
  vpc_id = aws_vpc.myvpc.id

  tags = {
    Name = "mygw"
  }
}

resource "aws_route_table" "route-table" {
  depends_on = [ aws_internet_gateway.mygw ]
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mygw.id
  }

  tags = {
    Name = "route-table"
  }
}

resource "aws_route_table_association" "route-table-association" {
  depends_on = [ aws_route_table.route-table ]
  subnet_id      = aws_subnet.subnet1-public.id
  route_table_id = aws_route_table.route-table.id
}



resource "aws_instance" "mysql" {
  depends_on = [ aws_security_group.sg2,aws_subnet.subnet2-private ]
  
  ami = "ami-07a7d806001316d24"
  instance_type = "t2.micro"
  
  vpc_security_group_ids = [ aws_security_group.sg2.id, aws_security_group.sg4.id ]
  subnet_id = aws_subnet.subnet2-private.id
  
  tags = {
    Name = "mysql"
  }
}

resource "aws_instance" "wp" {
  depends_on = [ aws_security_group.sg1,aws_subnet.subnet1-public,aws_instance.mysql ]
  
  ami = "ami-02d5fa0170619d4ad"
  instance_type = "t2.micro"
  
  vpc_security_group_ids = [ aws_security_group.sg1.id ]
  subnet_id = aws_subnet.subnet1-public.id
  associate_public_ip_address = "true"
  
  key_name = "keyt"
    
  tags = {
    Name = "wordpress"
  }
}


resource "aws_instance" "bastion" {
  depends_on = [ aws_security_group.sg3,aws_subnet.subnet1-public ]
  
  ami = "ami-08706cb5f68222d09"
  instance_type = "t2.micro"
  
  vpc_security_group_ids = [ aws_security_group.sg3.id ]
  subnet_id = aws_subnet.subnet1-public.id
  associate_public_ip_address = "true"
  
  key_name = "keyt"
    
  tags = {
    Name = "bastion host"
  }
}

resource "aws_eip" "bar" {
  vpc = true
  depends_on = [ aws_internet_gateway.mygw ]
}

resource "aws_nat_gateway" "natgw" {
  allocation_id = aws_eip.bar.id
  subnet_id = aws_subnet.subnet1-public.id

  tags = {
    Name = "NAT GW"
  }
}

resource "aws_route_table" "private-route-table" {
  depends_on = [ aws_internet_gateway.mygw, aws_nat_gateway.natgw ]
  vpc_id = aws_vpc.myvpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.natgw.id
  }

  tags = {
    Name = "private-route-table"
  }
}
resource "aws_route_table_association" "private-route-table-association" {
  depends_on = [ aws_route_table.private-route-table ]
  subnet_id      = aws_subnet.subnet2-private.id
  route_table_id = aws_route_table.private-route-table.id
}