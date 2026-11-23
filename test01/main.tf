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




