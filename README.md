# Terraform-Bastion-Server
AWS Bastion Server 내에서 Terraform을 활용한 IaC용 Repository입니다.

## 현재 계획중인 AWS 서비스는 다음과 같습니다.
- AWS EC2
    - API Server : 사용자 정보 및 카메라에 대해 관리 정보를 RDS, S3를 활용하여 관리하여 사용자에게 제공합니다.
    - Streaming Server(LiveKit) : 엣지 디바이스에서 실시간 영상 송출용 서버입니다. SFU 방식을 사용하여 부하를 줄입니다.
- AWS RDS : PostgreSQL 15.5 version을 사용합니다.
- AWS S3 : 녹화된 스트리밍 영상을 객체로서 저장합니다.
- AWS IoTCore : 엣지 디바이스에서 push 알림을 전송하기 위한 중간 매개체입니다.

## 현재 배포된 AWS 서비스는 다음과 같습니다.
- AWS EC2
    - API Server
    - Streaming Server
- AWS RDS
- AWS S3