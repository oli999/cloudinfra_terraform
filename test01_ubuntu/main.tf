# test01/main.tf

# vpc, 인터넷게이트웨이 , 서브넷, 라우팅 테이블 , 라우팅 테이블 연결, pem 파일 생성 및 다운로드
# 보안그룹, ec2 인스턴스 생성 등의 작업을 할 예정...

# 협업시 버전 차이로 인한 오류를 방지하기 위해서 버전을 고정하는 역활
terraform {
  required_version = "~>1.17.0" # 1.17.x 버전대만 허용, 1.18.0 이상은 차단 
  required_providers {
    # 사용할 외부 플러그인(provider) 목록과 버전 정의
    aws = {
        source = "hashicorp/aws"
        version = "~> 6.0"
    }
  }
}

# provider 설정
# 실제 인프라를 생성할 클라우드 플렛폼과 대상 리전을 지정
provider "aws"{
    region = "ap-northeast-2" # 아시아 태평양(서울) 리전 
}

# VPC 생성
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16" # 사설 ip 대역
  enable_dns_hostnames = true # public dnx 도메인 이름 자동부여 설정
  tags = {
    Name = "lecture-vpc" # 이름 부여 
  }
}

# 인터넷 게이트 웨이 생성
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id # 위에서 생성한 VPC의 ID를 동적으로 참조 (의존성 자동 설정)
  tags   = { Name = "lecture-igw" }
}

# 가용영역(AZ) 조회 
data "aws_availability_zones" "available"{
  state = "available" # 현재 리전에서 사용가능한 AZ 목록만 필터링
}

# public subnet 생성
resource "aws_subnet" "public_subnet" {
  vpc_id = aws_vpc.main.id
  # subnet 의 ip 대역 지정 
  cidr_block = "10.0.1.0/24"
  # 조회된 AZ 목록 배열(예: ["ap-northeast-2a", "ap-northeast-2b", ...]) 중 첫 번째(0번) 선택
  availability_zone = data.aws_availability_zones.available.names[0]
  # 이 서브넷에 생성되는 EC2 인스턴스에 공인(Public) IP를 자동으로 할당
  map_public_ip_on_launch = true
  tags = {
    Name = "lecture-subnet"
  }
}

# 라우팅 테이블 : 네트워크 트레픽의 경로를 결정하는 이정표
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id # 이 라우팅 테이블이 속할 vpc 지정
  # 라우팅 규칙: 내부 대역 외 모든 외부 목적지(0.0.0.0/0) 으로 가는 트래픽은 인터냇 게이트 웨이로 가도록 한다
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# 라우팅 테이블 연결 (public subnet 을 위에서 만든 라우팅 테이블로 연결해서 인터넷이 되도록 한다 )
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_subnet.id # 연결할 서브넷 ID
  route_table_id = aws_route_table.public_rt.id # 적용할 라우팅 테이블 ID
}

# pem 파일 관련 작업
# 알고리즘 결정
resource "tls_private_key" "pk" {
    algorithm = "RSA"
    rsa_bits  = 4096
}
# aws 에 공개키 등록
resource "aws_key_pair" "kp" {
    key_name   = "lecture-key" # AWS 콘솔에 표시될 키 페어 이름
    public_key = tls_private_key.pk.public_key_openssh # OpenSSH 형식의 공개키를 AWS에 업로드
}

# 개인키를 가져오기
# "local_file" resource 를 이용하면 파일을 생성할수 있다.
resource "local_file" "ssh_key" {
    # ${path.module} 은 현재 실행경로를 의미한다. 
    filename        = "${path.module}/lecture-key.pem" # 현재 main.tf가 있는 폴더에 저장
    content         = tls_private_key.pk.private_key_pem
    file_permission = "0600" # 파일의 권한 설정 
}

# 보안그룹 만들기
resource "aws_security_group" "ssh_sg" {
    # 보안 그룹의 이름은 이름이 겹치지 않게 유일하게 식별되는 이름은 짓는다
    name = "allow-ssh"
    # 어떤 vpc 소속인지 (보안그룹은 vpc 에 종속된다)
    vpc_id = aws_vpc.main.id # 위에서 미리 정의한 vpc

    # 밖에서 안으로 들어오는 규칙 (ingress rule)
    ingress {
      from_port = 22
      to_port = 22
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"] # 외부에서 들어오는 모든 traffic (실무에서는 나의 ip 만)
    }
    # postgres 를 위한 port 열어두기 
    ingress {
      from_port = 5432
      to_port = 5432
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"] # 외부에서 들어오는 모든 traffic (실무에서는 나의 ip 만)
    }

    # 안에서 밖으로 나가는 규칙 (egress rule)
    egress {
      # 0번~0번 까지 열어두면 모든 port 를 의미한다 
      from_port = 0
      to_port = 0
      protocol = "-1"  # 모든 프로토콜 
      cidr_blocks = ["0.0.0.0/0"] # 출발지에 상관없이 
    }
}

# ec2 에 설치할 amazon linux 최신 이미지 검색
data "aws_ami" "latest_ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical(Ubuntu 공식 배포사) AWS 계정 ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"] # Ubuntu 24.04 LTS 최신 이미지 검색
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ec2 만들기
resource "aws_instance" "my_ec2" {
    ami = data.aws_ami.latest_ubuntu.id # 검색된 최신 이미지의 id
    instance_type = "t3.micro" # 서버 사양
    subnet_id = aws_subnet.public_subnet.id # 어떤 subnet 에 위치 시킬 것인지
    vpc_security_group_ids = [aws_security_group.ssh_sg.id] # 적용시킬 보안그룹의 아이디를 배열에 넣어준다.
    key_name = aws_key_pair.kp.key_name # 위에서 미리 분비한 key 를 참조해서 이름을 넣어준다.
    # 테그 부여 (웹브라우저로 접속했을때 실제 만들어진 ec2 의 이름이 된다)
    tags = {
      Name = "my-ubuntu-ec2"
    }
}

# 만들어진 ec2 의 public ipv4 주소 출력하기
output "ec2_public_ip" {
  description = "생성된 EC2 인스턴스의 ip"
  value = aws_instance.my_ec2.public_ip
}

output "ssh_command" {
  description = "local 에 생성된 pem 파일을 이용해서 ssh 접속 명령어"
  # ubuntu linux 는 접속하는 user 의 계정명이 ubuntu 가 된다.
  value = "ssh ubuntu@${aws_instance.my_ec2.public_ip}  -i ${local_file.ssh_key.filename}"
}