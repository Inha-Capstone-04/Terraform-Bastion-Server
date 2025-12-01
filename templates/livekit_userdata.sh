#!/bin/bash

# 1. 기본 패키지 업데이트 및 Docker 설치
dnf update -y
dnf install docker -y
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# Docker Compose 설치
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# 2. 작업 디렉토리 생성
mkdir -p /home/ec2-user/livekit
cd /home/ec2-user/livekit

# Docker 컨테이너 내부의 non-root 유저(egress)가 쓸 수 있도록 777 권한 부여
mkdir -p /home/ec2-user/livekit/recordings
chmod -R 777 /home/ec2-user/livekit/recordings

# 3. 설정 파일 생성 (Terraform에서 주입된 내용)
cat <<EOF > livekit.yaml
${livekit_config}
EOF

# Egress 설정 파일 생성
cat <<EOF > egress.yaml
${egress_config}
EOF
chmod 644 egress.yaml livekit.yaml

cat <<EOF > docker-compose.yaml
${docker_compose_config}
EOF

# 4. 소유권 변경
chown -R ec2-user:ec2-user /home/ec2-user/livekit

# 5. 실행
/usr/local/bin/docker-compose up -d