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

variable "my_bastion_ip" {
  type        = string
  description = "Terraform을 실행하는 Bastion 서버의 Public IP (예: '1.2.3.4')"
  
  # (선택 사항) IP 형식이 맞는지 간단한 검증 추가
  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.my_bastion_ip))
    error_message = "유효한 IPv4 주소 형식을 입력해야 합니다."
  }
}

# --- [추가] Bastion 서버의 보안 그룹 조회 ---
data "aws_security_group" "bastion_sg" {
  filter {
    name   = "group-name"
    values = [var.my_bastion_sg_name]
  }
  
  vpc_id = data.aws_vpc.target.id
}

# --- [추가됨] EC2 부팅 시 실행할 스크립트 정의 (DRY 원칙) ---
locals {
  docker_install_script = <<-EOF
    #!/bin/bash
    # Amazon Linux 2023 (AL2023) 기준
    
    # 1. 패키지 업데이트
    dnf update -y
    
    # 2. Docker 설치
    dnf install docker -y
    
    # 3. Docker 서비스 시작 및 부팅 시 활성화
    systemctl start docker
    systemctl enable docker
    
    # 4. ec2-user가 sudo 없이 docker 명령을 실행할 수 있도록 그룹에 추가
    # (이 작업은 CI/CD 및 SSH 접속 시 매우 중요합니다)
    usermod -aG docker ec2-user
    
    # 참고: 'usermod' 변경 사항은 새 로그인 세션부터 적용됩니다.
  EOF
}

# --- 1. S3 버킷 생성 ---

# S3 버킷 이름이 고유해야 하므로 랜덤 문자열 추가
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

# S3 퍼블릭 액세스 차단 (보안 권장)
resource "aws_s3_bucket_public_access_block" "my_bucket_pab" {
  bucket                  = aws_s3_bucket.my_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- 2. EC2 인스턴스 (2대) ---

# EC2에 적용할 보안 그룹 (Bastion IP에서만 SSH 22번 포트 허용)
resource "aws_security_group" "ec2_sg" {
  name        = "inha-capstone-04-ec2-server-ssh-from-bastion-sg"
  description = "Allow SSH inbound traffic from Bastion"
  vpc_id      = data.aws_vpc.target.id

  ingress {
    description = "SSH from Bastion"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    # 신뢰할 수 없는 http data source 대신, 안전한 변수(variable)를 사용합니다.
    cidr_blocks = ["${var.my_bastion_ip}/32"]
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

# 1. EC2 API 서버 (Prod)
resource "aws_instance" "api_server" {
  ami           = data.aws_ssm_parameter.al2023_ami.value
  instance_type = var.instance_type
  
  # 첫 번째 가용 영역의 서브넷에 배포
  # data.aws_subnets.default.ids 리스트의 첫 번째 항목 사용
  subnet_id = data.aws_subnets.target.ids[0]
  
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name               = var.ec2_key_pair_name
  iam_instance_profile   = data.aws_iam_instance_profile.existing_profile.name

  user_data = local.docker_install_script

  tags = {
    Name = "inha-capstone-04-api-server"
    Env  = "prod"
  }
}

# 2. EC2 LiveKit 서버
resource "aws_instance" "livekit_server" {
  ami           = data.aws_ssm_parameter.al2023_ami.value
  instance_type = var.instance_type

  # 두 번째 가용 영역의 서브넷에 배포 (가용성 향상)
  # data.aws_subnets.default.ids 리스트의 두 번째 항목 사용
  subnet_id = data.aws_subnets.target.ids[1]

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name               = var.ec2_key_pair_name
  iam_instance_profile   = data.aws_iam_instance_profile.existing_profile.name

  user_data = local.docker_install_script

  tags = {
    Name = "inha-capstone-04-livekit-server"
  }
}

# 3. EC2 API 서버 (Dev)
resource "aws_instance" "api_server_dev" {
  ami           = data.aws_ssm_parameter.al2023_ami.value
  instance_type = var.instance_type # dev용으로 더 낮은 사양을 원하면 변수화 필요
  
  # main과 동일하게 첫 번째 서브넷에 배포
  subnet_id = data.aws_subnets.target.ids[0]
  
  vpc_security_group_ids = [aws_security_group.ec2_sg.id] # 동일한 SG 사용
  key_name               = var.ec2_key_pair_name
  iam_instance_profile   = data.aws_iam_instance_profile.existing_profile.name

  user_data = local.docker_install_script

  tags = {
    Name = "inha-capstone-04-api-server-dev"
    Env  = "dev"
  }
}

# --- 3. RDS (PostgreSQL) ---

# RDS에 적용할 보안 그룹 (EC2 보안 그룹에서만 5432 포트 허용)
resource "aws_security_group" "rds_sg" {
  name        = "inha-capstone-04-rds-postgres-allow-sg"
  description = "Allow PostgreSQL from EC2 SG and Bastion SG"
  vpc_id      = data.aws_vpc.target.id

  ingress {
    description     = "PostgreSQL from EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    # 위에서 생성한 EC2 인스턴스(의 보안 그룹)에서만 접속 허용
    security_groups = [aws_security_group.ec2_sg.id] 
  }

  ingress {
    description = "PostgreSQL from Bastion (for IntelliJ Tunnel)"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [data.aws_security_group.bastion_sg.id]
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

# 기존 RDS 서브넷 그룹 조회
data "aws_db_subnet_group" "existing" {
  name = "default-subnet-group"
}

# PostgreSQL DB 인스턴스 생성
resource "aws_db_instance" "my_postgres_db" {
  identifier             = "inha-capstone-04-db-instance"
  allocated_storage      = 20             # 20GB 스토리지
  engine                 = "postgres"
  engine_version         = "15.12"         # PostgreSQL 15.12 버전
  instance_class         = "db.t4g.micro"  # 개발/테스트용
  db_name                = "ember_sentinel"
  username               = var.db_username # secrets.tfvars에서 가져옴
  password               = var.db_password # secrets.tfvars에서 가져옴
  
  db_subnet_group_name   = data.aws_db_subnet_group.existing.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  
  publicly_accessible    = false          # 외부 접근 차단 (보안 권장)
  skip_final_snapshot    = true           # 삭제 시 최종 스냅샷 생략 (프로덕션에서는 false 권장)

  tags = {
    Owner   = "inha-capstone-04"
    Project = "capstone"
    Env  = "shared"
  }
}

# --- 4. IAM (EC2 -> S3 접근 권한) ---

# [수정됨] resource 대신 data를 사용하여 기존 인스턴스 프로파일을 이름으로 조회
data "aws_iam_instance_profile" "existing_profile" {
  name = var.existing_instance_profile_name
}

# --- 5. ECR (컨테이너 이미지 저장소) ---

# 1. API 서버용 ECR 리포지토리
resource "aws_ecr_repository" "api_server_ecr" {
  name = "inha-capstone-04/api-server" # 리포지토리 이름 (구분자 '/' 사용 권장)

  image_tag_mutability = "IMMUTABLE" # 태그 덮어쓰기 방지 (보안/운영 모범 사례)

  image_scanning_configuration {
    scan_on_push = true # 푸시할 때마다 이미지 취약점 스캔 (보안 모범 사례)
  }

  tags = {
    Name    = "inha-capstone-04-api-server-ecr"
    Project = "capstone"
    Env     = "shared"
  }
}

# 2. LiveKit 서버용 ECR 리포지토리
resource "aws_ecr_repository" "livekit_server_ecr" {
  name = "inha-capstone-04/livekit-server" # 리포지토리 이름

  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name    = "inha-capstone-04-livekit-server-ecr"
    Project = "capstone"
    Env     = "shared"
  }
}