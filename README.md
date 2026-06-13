# Terraform-Bastion-Server

> INHA Univ. 캡스톤 디자인 - Ember Sentinel 프로젝트의 AWS 인프라 IaC(Infrastructure as Code) 레포지토리입니다.

Bastion 서버에서 Terraform을 실행하여 EC2, RDS, S3, ECR 등 AWS 리소스를 코드로 관리합니다. IAM Instance Profile을 통해 자격증명 없이 Bastion EC2의 Role 권한을 자동으로 상속받아 실행합니다.

## 배포 리소스 구성

### EC2 인스턴스

| 인스턴스         | 타입      | 용도                                       |
| ---------------- | --------- | ------------------------------------------ |
| `api-server-dev` | t3.medium | Spring Boot API 서버 + Redis               |
| `livekit-server` | m5.xlarge | LiveKit SFU 스트리밍 서버 + Egress + Redis |

- **API 서버**: Docker 기동 시 Redis 7.0 컨테이너를 함께 실행합니다.
- **LiveKit 서버**: Docker Compose로 LiveKit Server, Egress, Redis 3개 컨테이너를 `network_mode: host`로 실행합니다. Egress는 화재 감지 시 영상을 S3로 자동 녹화합니다.

### LiveKit 포트 구성

| 포트          | 프로토콜 | 용도                    |
| ------------- | -------- | ----------------------- |
| 7880          | TCP      | LiveKit API & WebSocket |
| 7881          | TCP      | WebRTC TCP Fallback     |
| 50000 - 60000 | UDP      | WebRTC 미디어 전송      |

### RDS

- **엔진**: PostgreSQL 15.12
- **인스턴스**: db.t4g.micro (스토리지 20GB)
- **데이터베이스명**: `ember_sentinel`

### S3

- 버킷명은 `inha-capstone-04-s3-bucket-{random_hex}` 형태로 생성됩니다.
- 퍼블릭 접근 완전 차단 (Public Access Block 적용)
- Egress 컨테이너가 IAM Role 권한으로 녹화 영상을 업로드합니다.

### ECR

| 리포지토리                        | 용도                     |
| --------------------------------- | ------------------------ |
| `inha-capstone-04/api-server`     | API 서버 도커 이미지     |
| `inha-capstone-04/livekit-server` | LiveKit 서버 도커 이미지 |

## 기술 스택

- **IaC**: Terraform
- **Provider**: AWS (`~> 5.0`), Random (`~> 3.5`), HTTP (`~> 3.4`)
- **리전**: `us-west-2` (오레곤)
- **OS**: Amazon Linux 2023 (SSM Parameter Store에서 최신 AMI 자동 조회)

## 디렉토리 구조

```
Terraform-Bastion-Server/
├── main.tf               # 모든 AWS 리소스 정의 (S3, SG, EC2, RDS, ECR)
├── variables.tf          # 입력 변수 정의
├── outputs.tf            # 출력값 정의
├── provider.tf           # Terraform 프로바이더 설정
└── templates/
    ├── api_server_userdata.sh      # API 서버 EC2 초기화 스크립트 (Docker, Redis)
    ├── livekit_userdata.sh         # LiveKit 서버 EC2 초기화 스크립트
    ├── livekit.yaml.tftpl          # LiveKit 서버 설정 템플릿
    ├── egress.yaml.tftpl           # LiveKit Egress 설정 템플릿
    └── docker-compose.livekit.yml  # LiveKit 서버 Docker Compose 구성
```

## 사용 방법

### 사전 요건

- Bastion EC2에서 실행할 것 (IAM Role 자동 상속)
- Terraform 설치 필요

### 필수 입력 변수

| 변수명                           | 설명                                          | Sensitive |
| -------------------------------- | --------------------------------------------- | --------- |
| `target_vpc_id`                  | 리소스를 배포할 VPC ID                        |           |
| `ec2_key_pair_name`              | EC2 접속용 Key Pair 이름                      |           |
| `existing_instance_profile_name` | EC2에 연결할 IAM Instance Profile 이름        |           |
| `my_bastion_ip`                  | Terraform을 실행하는 Bastion 서버의 Public IP |           |
| `dev_ec2_cidr_blocks`            | EC2 SSH 인바운드 허용 CIDR                    |           |
| `db_username`                    | RDS PostgreSQL 관리자 유저명                  | ✓         |
| `db_password`                    | RDS PostgreSQL 관리자 비밀번호                | ✓         |
| `livekit_api_key`                | LiveKit Server API Key                        | ✓         |
| `livekit_api_secret`             | LiveKit Server API Secret                     | ✓         |

### 실행

```bash
terraform init
terraform plan
terraform apply
```

### 출력값

| 출력                       | 설명                            |
| -------------------------- | ------------------------------- |
| `api_server_dev_public_ip` | API 서버 Public IP              |
| `livekit_server_public_ip` | LiveKit 서버 Public IP          |
| `rds_endpoint`             | RDS 연결 엔드포인트             |
| `rds_port`                 | RDS 포트                        |
| `s3_bucket_name`           | 생성된 S3 버킷명                |
| `api_server_ecr_url`       | API 서버 ECR 리포지토리 URL     |
| `livekit_server_ecr_url`   | LiveKit 서버 ECR 리포지토리 URL |
