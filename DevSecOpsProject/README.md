This project aims to provide a robust framework for deploying and managing cloud infrastructure and DevOps tools on AWS with best practices in security, monitoring, and continuous integration/continuous deployment (CI/CD). By automating the provisioning of infrastructure and resources, we enable faster and more reliable deployments.

The project includes the setup and configuration of key DevOps tools and technologies such as Prometheus, Grafana, Jenkins, Argo CD, SonarQube, Trivy, and Amazon ECR. It also covers the deployment of an Amazon EKS cluster, including node groups, cluster add-ons, and necessary IAM roles, all automated with Terraform and shell scripts. To ensure the security and integrity of our Terraform state, we leverage AWS S3 for storage and DynamoDB for state locking.



Features
Amazon EKS Cluster Deployment: Automate the creation of an EKS cluster along with node groups and essential add-ons.
Infrastructure as Code (IaC): Utilize Terraform to define and deploy AWS resources in a predictable and repeatable manner.
DevOps Tools Configuration: Install and configure Prometheus, Grafana, Jenkins, Argo CD, SonarQube, and Trivy for monitoring, CI/CD, and security scanning.
Amazon ECR: Use Amazon Elastic Container Registry for storing, managing, and deploying Docker container images.
Secure State Management: Store Terraform state files in an encrypted S3 bucket and use DynamoDB for state locking to ensure consistent and secure state management
