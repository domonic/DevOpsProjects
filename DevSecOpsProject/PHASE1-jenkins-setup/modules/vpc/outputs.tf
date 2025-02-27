output "k8s-blue-2a"{
    value = aws_subnet.k8s-blue-2a.id
}


output "k8s-blue-2b"{
    value = aws_subnet.k8s-blue-2b.id
}

output "k8s-blue-2c"{
    value = aws_subnet.k8s-blue-2c.id
}

output "k8s-green-2a"{
    value = aws_subnet.k8s-green-2a.id
}

output "k8s-green-2b"{
    value = aws_subnet.k8s-green-2b.id
}

output "k8s-green-2c"{
    value = aws_subnet.k8s-green-2c.id
}

output "devsecopsvpc"{
    value = aws_vpc.devsecopsvpc.id
}

output "subnet_ids"{
    value = [aws_subnet.k8s-blue-2a.id, aws_subnet.k8s-blue-2b.id, aws_subnet.k8s-blue-2c.id, 
             aws_subnet.k8s-green-2a.id, aws_subnet.k8s-green-2b.id, aws_subnet.k8s-green-2c.id]
}

output "subnet_alb_ids"{
     value = [aws_subnet.k8s-blue-2a.id, aws_subnet.k8s-blue-2b.id, aws_subnet.k8s-blue-2c.id]
}


output "subnet_blue_ids"{
     value = [aws_subnet.k8s-blue-2a.id, aws_subnet.k8s-blue-2b.id, aws_subnet.k8s-blue-2c.id]
}


output "subnet_green_ids"{
     value = [aws_subnet.k8s-green-2a.id, aws_subnet.k8s-green-2b.id, aws_subnet.k8s-green-2c.id]
}
