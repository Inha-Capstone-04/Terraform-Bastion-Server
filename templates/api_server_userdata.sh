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