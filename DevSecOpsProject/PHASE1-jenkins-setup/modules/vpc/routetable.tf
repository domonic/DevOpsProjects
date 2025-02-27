# Using Terraform IaC to create Route Table
resource "aws_route_table" "route" {
    vpc_id = "${aws_vpc.devsecopsvpc.id}"
route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.devsecopsigw.id}"
    }
tags = {
        Name = "Route to internet"
    }
}

# Associating Route Table To VPC Blue Subnet 2a
resource "aws_route_table_association" "k8s-blue-2a" {
    subnet_id = "${aws_subnet.k8s-blue-2a.id}"
    route_table_id = "${aws_route_table.route.id}"
}

# Associating Route Table To VPC Blue Subnet 2b
resource "aws_route_table_association" "k8s-blue-2b" {
    subnet_id = "${aws_subnet.k8s-blue-2b.id}"
    route_table_id = "${aws_route_table.route.id}"
}

# Associating Route Table To VPC Blue Subnet 2c
resource "aws_route_table_association" "k8s-blue-2c" {
    subnet_id = "${aws_subnet.k8s-blue-2c.id}"
    route_table_id = "${aws_route_table.route.id}"
}

# Associating Route Table To VPC Green Subnet 2a
resource "aws_route_table_association" "k8s-green-2a" {
    subnet_id = "${aws_subnet.k8s-green-2a.id}"
    route_table_id = "${aws_route_table.route.id}"
}

# Associating Route Table To VPC Green Subnet 2b
resource "aws_route_table_association" "k8s-green-2b" {
    subnet_id = "${aws_subnet.k8s-green-2b.id}"
    route_table_id = "${aws_route_table.route.id}"
}

# Associating Route Table To VPC Green Subnet 2c
resource "aws_route_table_association" "k8s-green-2c" {
    subnet_id = "${aws_subnet.k8s-green-2c.id}"
    route_table_id = "${aws_route_table.route.id}"
}