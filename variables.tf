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

variable "my_bastion_ip" {
  type        = string
  description = "Terraform을 실행하는 Bastion 서버의 Public IP (예: '1.2.3.4')"
  
  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.my_bastion_ip))
    error_message = "유효한 IPv4 주소 형식을 입력해야 합니다."
  }
}

variable "dev_ec2_cidr_blocks" {
  type        = string
  description = "EC2 3대의 ssh 접근용 인바운드 IP 또는 CIDR (예: '0.0.0.0/0')"

  validation {
    condition     = can(cidrhost(var.dev_ec2_cidr_blocks, 0))
    error_message = "유효한 IPv4 CIDR 형식(예: 1.2.3.4/32 또는 0.0.0.0/0)이어야 합니다."
  }
}

variable "my_bastion_sg_name" {
  type        = string
  description = "Bastion 서버의 보안 그룹 이름 (데이터 소스 조회용)"
  default     = "inha-capstone-04-sg-bastion-host"
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
  sensitive   = true
}

variable "db_password" {
  description = "RDS PostgreSQL 관리자 비밀번호"
  type        = string
  sensitive   = true
}

variable "allowed_rds_cidr_blocks" {
  type        = list(string)
  description = "RDS에 접속을 허용할 CIDR 블록 리스트"
  default     = ["0.0.0.0/0"]
}

# --- VPC 설정 ---
variable "target_vpc_id" {
  description = "배포를 진행할 대상 VPC의 ID"
  type        = string
}