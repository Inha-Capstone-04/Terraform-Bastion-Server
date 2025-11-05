# --- 일반 설정 ---
variable "aws_region" {
  description = "배포할 AWS 리전"
  type        = string
  default     = "us-west-2" # 오레곤리전
}

# --- EC2 설정 ---
variable "instance_type" {
  description = "EC2 인스턴스 타입"
  type        = string
  default     = "t3.medium"
}

variable "ec2_key_pair_name" {
  description = "EC2 인스턴스에 연결할 기존 AWS Key Pair 이름"
  type        = string
}

variable "existing_instance_profile_name" {
  description = "EC2에 연결할 기존 IAM Instance Profile의 이름"
  type        = string
}

# --- S3 설정 ---
variable "s3_bucket_name_prefix" {
  description = "S3 버킷 이름 (고유해야 하므로 접두사 사용)"
  type        = string
  default     = "inha-capstone-04-s3-bucket"
}

# --- RDS (Secret) 설정 ---
variable "db_username" {
  description = "RDS PostgreSQL 관리자 유저 이름"
  type        = string
  sensitive   = true # 민감 정보로 표시
}

variable "db_password" {
  description = "RDS PostgreSQL 관리자 비밀번호"
  type        = string
  sensitive   = true # 민감 정보로 표시
}

# --- VPC 설정 ---
variable "target_vpc_id" {
  description = "배포를 진행할 대상 VPC의 ID"
  type        = string
  # default 값을 설정하지 않아, secrets.tfvars에서 필수로 입력해야 함
}

variable "my_bastion_sg_name" {
  type        = string
  description = "IntelliJ 터널링에 사용할 Bastion 서버의 보안 그룹 이름"
  default = "inha-capstone-04-sg-bastion-host"
}