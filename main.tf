# --- 데이터 소스 ---

# 기본 VPC 및 서브넷 정보
data "aws_vpc" "target" {
  id = var.target_vpc_id
}

data "aws_subnets" "target" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.target.id]
  }
}

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_security_group" "bastion_sg" {
  filter {
    name   = "group-name"
    values = [var.my_bastion_sg_name]
  }
  vpc_id = data.aws_vpc.target.id
}

data "aws_iam_instance_profile" "existing_profile" {
  name = var.existing_instance_profile_name
}

data "aws_caller_identity" "current" {}

# --- User Data 및 Config 렌더링 ---

locals {
  # 1. 사용자 이름 추출 (태그용)
  extracted_arn_parts = split("/", data.aws_caller_identity.current.arn)
  extracted_username = local.extracted_arn_parts[length(local.extracted_arn_parts) - 1]

  # 2. LiveKit 설정 값
  livekit_api_key    = var.livekit_api_key
  livekit_api_secret = var.livekit_api_secret
  
  # Webhook URL: Dev API 서버 IP for Test
  webhook_target_ip = aws_instance.api_server_dev.public_ip 

  # 3. 템플릿 렌더링
  
  # API 서버용 스크립트
  api_server_userdata = file("${path.module}/templates/api_server_userdata.sh")

  # LiveKit 설정 파일 내용 생성
  livekit_yaml_content = templatefile("${path.module}/templates/livekit.yaml.tftpl", {
    api_key     = local.livekit_api_key
    api_secret  = local.livekit_api_secret
    webhook_url = "http://${local.webhook_target_ip}:8080/livekit/webhook"
  })

  # Egress 설정 파일 내용 생성
  egress_yaml_content = templatefile("${path.module}/templates/egress.yaml.tftpl", {
    api_key        = local.livekit_api_key
    api_secret     = local.livekit_api_secret
    aws_region     = "us-west-2" # 사용하는 리전
    s3_bucket_name = aws_s3_bucket.my_bucket.bucket
  })

  # LiveKit 서버용 스크립트 (Egress Config 추가 전달)
  livekit_server_userdata = templatefile("${path.module}/templates/livekit_userdata.sh", {
    livekit_config        = local.livekit_yaml_content
    egress_config         = local.egress_yaml_content
    docker_compose_config = file("${path.module}/templates/docker-compose.livekit.yml")
  })
}

# --- 1. S3 버킷 ---

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

# --- 2. 보안 그룹 ---

# 2.1 API 서버용 보안 그룹
resource "aws_security_group" "ec2_sg" {
  name        = "inha-capstone-04-ec2-api-sg"
  description = "Allow SSH and HTTP 8080"
  vpc_id      = data.aws_vpc.target.id

  ingress {
    description = "SSH from Dev/Bastion"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_bastion_ip}/32", "${var.dev_ec2_cidr_blocks}"]
  }

  ingress {
    description = "Springboot HTTP"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 필요 시 제한
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "inha-capstone-04-ec2-api-sg" }

}

# 2.2 LiveKit 서버용 보안 그룹 (WebRTC 필수 포트 개방)
resource "aws_security_group" "livekit_sg" {
  name        = "inha-capstone-04-ec2-livekit-sg"
  description = "Allow LiveKit Traffic (TCP/UDP)"
  vpc_id      = data.aws_vpc.target.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_bastion_ip}/32", "${var.dev_ec2_cidr_blocks}"]
  }

  # LiveKit API & WebSocket
  ingress {
    from_port   = 7880
    to_port     = 7880
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # WebRTC TCP (Fallback)
  ingress {
    from_port   = 7881
    to_port     = 7881
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # WebRTC UDP (Media) - 핵심
  ingress {
    from_port   = 50000
    to_port     = 60000
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "inha-capstone-04-ec2-livekit-sg" }

}

# --- 3. EC2 인스턴스 ---

# 3.2 LiveKit 서버 - LiveKit 실행 스크립트 적용
resource "aws_instance" "livekit_server" {
  ami           = data.aws_ssm_parameter.al2023_ami.value
  instance_type = var.instance_type_m5_xlarge
  subnet_id     = data.aws_subnets.target.ids[1]

  # [LiveKit 전용 보안 그룹]
  vpc_security_group_ids = [aws_security_group.livekit_sg.id]
  
  key_name               = var.ec2_key_pair_name
  iam_instance_profile   = data.aws_iam_instance_profile.existing_profile.name

  # [LiveKit용 스크립트]
  user_data = local.livekit_server_userdata

  tags = {
    Name     = "inha-capstone-04-livekit-server"
    username = "inha-capstone-04"
  }
}

# 3.3 API 서버 (Dev) - Redis 실행 스크립트 적용
resource "aws_instance" "api_server_dev" {
  ami           = data.aws_ssm_parameter.al2023_ami.value
  instance_type = var.instance_type_t3_medium
  subnet_id     = data.aws_subnets.target.ids[0]
  
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  key_name               = var.ec2_key_pair_name
  iam_instance_profile   = data.aws_iam_instance_profile.existing_profile.name

  # [API 서버용 스크립트]
  user_data = local.api_server_userdata

  tags = {
    Name     = "inha-capstone-04-api-server-dev"
    Env      = "dev"
    username = "inha-capstone-04"
  }
}

# --- 4. RDS (PostgreSQL) ---

resource "aws_security_group" "rds_sg" {
  name        = "inha-capstone-04-rds-postgres-allow-sg"
  description = "Allow PostgreSQL from EC2 SGs"
  vpc_id      = data.aws_vpc.target.id

  ingress {
    description     = "PostgreSQL from allowed CIDR blocks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    cidr_blocks     = var.allowed_rds_cidr_blocks
  }

  ingress {
    description     = "PostgreSQL from API Servers"
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

  tags = { Name = "inha-capstone-04-rds-postgres-sg" }
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

# --- 5. ECR ---

resource "aws_ecr_repository" "api_server_ecr" {
  name = "inha-capstone-04/api-server"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  tags = { Name = "inha-capstone-04-api-server-ecr" }
}

resource "aws_ecr_repository" "livekit_server_ecr" {
  name = "inha-capstone-04/livekit-server"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  tags = { Name = "inha-capstone-04-livekit-server-ecr" }
}