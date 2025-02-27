output "jenkins-efs-sg"{
    value = aws_security_group.jenkins-efs-sg.id
}

output "jenkins-instance-sg" {
    value = aws_security_group.jenkins-instance-sg.id
}