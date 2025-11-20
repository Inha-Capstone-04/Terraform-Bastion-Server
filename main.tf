# --- 데이터 소스 ---

# 기본 VPC 및 서브넷 정보 가져오기
data "aws_vpc" "target" {
  id = var.target_vpc_id
}

data "aws_subnets" "target" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.target.id]
  }
}

# 오레곤 리전(us-west-2)의 최신 Amazon Linux 2023 (x86_64) AMI ID를 동적으로 가져옵니다.
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Bastion 서버의 보안 그룹 조회
data "aws_security_group" "bastion_sg" {
  filter {
    name   = "group-name"
    values = [var.my_bastion_sg_name]
  }
  
  vpc_id = data.aws_vpc.target.id
}

# 기존 IAM 인스턴스 프로파일 조회 (SSM 권한 포함 필수)
data "aws_iam_instance_profile" "existing_profile" {
  name = var.existing_instance_profile_name
}

# --- [수정됨] EC2 부팅 시 실행할 스크립트 (Docker + SSM Agent) ---
locals {
  # Amazon Linux 2023 기준
  setup_script = <<-EOF
    #!/bin/bash
    
    # 1. 시스템 패키지 업데이트
    dnf update -y
    
    # 2. Docker 설치 및 설정
    dnf install docker -y
    systemctl start docker
    systemctl enable docker
    # ec2-user를 docker 그룹에 추가 (sudo 없이 사용)
    usermod -aG docker ec2-user
    
    # 3. SSM Agent 설치 및 확인 (AL2023은 기본 설치되어 있으나 확실하게 수행)
    dnf install -y amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent

    # 3. Docker 사용자 정의 네트워크 생성
    # 이미 존재하면 에러가 날 수 있으므로 || true로 무시하거나 검사
    docker network create ember-network || true
    
    # 4. Redis Volume 생성
    docker volume create embersentinel_redis_data
    
    # 5. Redis 컨테이너 실행
    docker run -d \
      --name embersentinel-redis \
      --network ember-network \
      -p 6379:6379 \
      -v embersentinel_redis_data:/data \
      --restart always \
      redis:7.0-alpine \
      redis-server --appendonly yes
    
    # 참고: 'usermod' 변경 사항은 새 로그인 세션부터 적용됩니다.
  EOF
}

# --- 1. S3 버킷 생성 ---

resource "random_id" "bucket_suffix" {
  byte_length = 6
}

resource "aws_s3_bucket" "my_bucket" {
  bucket = "${var.s3_bucket_name_prefix}-${random_id.bucket_suffix.hex}"

  tags = {
    Name = "inha-capstone-04-s3-bucket"
    Env  = "shared"
  }
}

resource "aws_s3_bucket_public_access_block" "my_bucket_pab" {
  bucket                  = aws_s3_bucket.my_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- 2. EC2 인스턴스 보안 그룹 ---

resource "aws_security_group" "ec2_sg" {
  name        = "inha-capstone-04-ec2-server-ssh-from-bastion-sg"
  description = "Allow SSH inbound traffic from Bastion"
  vpc_id      = data.aws_vpc.target.id

  ingress {
    description = "SSH from Bastion"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_bastion_ip}/32"]
  }

  ingress {
    description = "SSH from Dev"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.dev_ec2_cidr_blocks}"]
  }

  ingress {
    description = "Springboot Access from Dev"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["${var.dev_ec2_cidr_blocks}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "inha-capstone-04-ec2-server-ssh-sg"
  }
}

# --- 3. EC2 인스턴스 (3대) ---
# 모든 인스턴스에 local.setup_script (Docker + SSM) 적용

# 3.1. EC2 API 서버 (Prod)
resource "aws_instance" "api_server" {
  ami           = data.aws_ssm_parameter.al2023_ami.value
  instance_type = var.instance_type
  
  subnet_id = data.aws_subnets.target.ids[0]
  
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name               = var.ec2_key_pair_name
  iam_instance_profile   = data.aws_iam_instance_profile.existing_profile.name

  user_data = local.setup_script

  tags = {
    Name = "inha-capstone-04-api-server"
    Env  = "prod"
    username = "inha-capstone-04"
  }
}

# 3.2. EC2 LiveKit 서버
resource "aws_instance" "livekit_server" {
  ami           = data.aws_ssm_parameter.al2023_ami.value
  instance_type = var.instance_type

  subnet_id = data.aws_subnets.target.ids[1]

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name               = var.ec2_key_pair_name
  iam_instance_profile   = data.aws_iam_instance_profile.existing_profile.name

  user_data = local.setup_script

  tags = {
    Name = "inha-capstone-04-livekit-server"
    username = "inha-capstone-04"
  }
}

# 3.3. EC2 API 서버 (Dev)
resource "aws_instance" "api_server_dev" {
  ami           = data.aws_ssm_parameter.al2023_ami.value
  instance_type = var.instance_type
  
  subnet_id = data.aws_subnets.target.ids[0]
  
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name               = var.ec2_key_pair_name
  iam_instance_profile   = data.aws_iam_instance_profile.existing_profile.name

  user_data = local.setup_script

  tags = {
    Name = "inha-capstone-04-api-server-dev"
    Env  = "dev"
    username = "inha-capstone-04"
  }
}

# --- 4. RDS (PostgreSQL) ---

resource "aws_security_group" "rds_sg" {
  name        = "inha-capstone-04-rds-postgres-allow-sg"
  description = "Allow PostgreSQL from EC2 SG and Bastion SG"
  vpc_id      = data.aws_vpc.target.id

  ingress {
    description     = "PostgreSQL from allowed CIDR blocks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    cidr_blocks     = var.allowed_rds_cidr_blocks
  }

  ingress {
    description     = "PostgreSQL from Develop EC2s"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id] 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "inha-capstone-04-rds-postgres-sg"
  }
}

data "aws_db_subnet_group" "existing" {
  name = "default-subnet-group"
}

resource "aws_db_instance" "my_postgres_db" {
  identifier             = "inha-capstone-04-db-instance"
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version         = "15.12"
  instance_class         = "db.t4g.micro"
  db_name                = "ember_sentinel"
  username               = var.db_username
  password               = var.db_password
  
  db_subnet_group_name   = data.aws_db_subnet_group.existing.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  
  publicly_accessible    = true
  skip_final_snapshot    = true

  tags = {
    Owner   = "inha-capstone-04"
    Project = "capstone"
    Env     = "shared"
  }
}

# --- 5. ECR (컨테이너 이미지 저장소) ---

# 5.1. API 서버용 ECR
resource "aws_ecr_repository" "api_server_ecr" {
  name = "inha-capstone-04/api-server"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = {
    Name    = "inha-capstone-04-api-server-ecr"
    Project = "capstone"
    Env     = "shared"
  }
}

# 5.2. LiveKit 서버용 ECR
resource "aws_ecr_repository" "livekit_server_ecr" {
  name = "inha-capstone-04/livekit-server"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = {
    Name    = "inha-capstone-04-livekit-server-ecr"
    Project = "capstone"
    Env     = "shared"
  }
}