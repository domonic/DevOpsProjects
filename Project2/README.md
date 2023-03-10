Jenkins is a popular open-source automation tool that is used for continuous integration and continuous delivery (CI/CD) of software applications. Terraform is a tool that allows you to automate the deployment of infrastructure resources. In this article, we will discuss how to deploy Jenkins via Terraform onto AWS EC2.

Prerequisites:

AWS Account
AWS CLI installed on your local machine
Terraform installed on your local machine
Basic knowledge of Terraform and AWS EC2


Step 1: Create an EC2 Key Pair
To connect to the EC2 instance, we need to create an EC2 key pair. If you have already created one, you can skip this step.

Go to the EC2 console in your AWS account.
Click on "Key Pairs" in the left-hand navigation menu.
Click on "Create Key Pair".
Give your key pair a name and select "PEM" as the file format.
Click on "Create Key Pair" and save the downloaded file in a secure location on your local machine.

Step 2: Create the Terraform configuration files to create your infrastructure:

Create a new directory for your Terraform files.
Create the tf files in your directory.
Add the corresponding code to your tf files

Make sure to replace key-name with the name of your key pair that you created in Step 1.

Step 3: Initialize Terraform

Open your terminal and navigate to your Terraform directory.
Run the command terraform init to initialize Terraform and download the AWS provider plugin.
Step 4: Create an Execution Plan

Run the command terraform plan to create an execution plan.
Review the plan to ensure that it is deploying the resources that you expect.
Step 5: Deploy Jenkins

Run the command terraform apply to deploy Jenkins onto AWS EC2.
Terraform will prompt you to confirm the deployment. Type "yes" and hit enter to confirm.
Wait for Terraform to finish deploying the resources.
Step 6: Access Jenkins

Once the deployment is complete, navigate to the EC2 console in your AWS account.
Find the public IP address of the instance that was just created.
Open your web browser and navigate to http://<public-ip-address>:8080 to access Jenkins.
Congratulations! You have successfully deployed Jenkins onto AWS EC2 via Terraform. You can now use Jenkins to automate.