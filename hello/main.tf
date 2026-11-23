# hello/main.tf

# .tf 파일은 hcl 형식의 문서이다.   json, xml, yml, hcl 



provider "aws" {
  region = "ap-northeast-2"
}

# vpc 정의하기
resource "aws_vpc" "test_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "terraform_test_vpc"
  }
}

# 인터넷 게이트 웨이
# resource "만들자원" "이 자원을 가리킬 식별값(tf 파일 다른곳에서 참조하는 용도로 사용)"
resource "aws_internet_gateway" "igw" {
  # 어떤 vpc 에 붙여야하지?  선택에 대한 문제가 발생한다 
  vpc_id = aws_vpc.test_vpc.id
  tags = {
    Name = "test_vpc_igw" # tags 에 들어가는 이름은 마음대로 지을수 있다. aws console 에 로그인하면 보인다.
  }
}
