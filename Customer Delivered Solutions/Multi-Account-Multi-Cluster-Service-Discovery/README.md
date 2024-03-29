# Multi-Account Multi-Cluster Service Discovery with AWS Cloud Map and Kubernetes

This README outlines the steps and configurations necessary to set up a multi-account, multi-cluster service discovery mechanism using AWS Cloud Map and the open-source AWS Cloud Map MCS Controller. This setup enables services in different Amazon EKS clusters, across different AWS accounts, to discover and communicate with each other.
## Overview
The AWS Cloud Map MCS Controller for Kubernetes allows Kubernetes services to be discovered across cluster boundaries. This guide extends the concept to a multi-account EKS environment, facilitating service discovery and communication across clusters located in separate AWS accounts.
## Prerequisites

Two AWS Accounts (referred to as Account One and Account Two)
Amazon EKS clusters set up in both accounts (Cluster One in Account One, Cluster Two in Account Two)
AWS CLI configured for both accounts
Kubernetes `kubectl` command-line tool configured for both clusters
AWS IAM permissions to create roles, policies, and edit VPC route tables and security groups

## Configuration Steps

### Step 1: Setup IAM Roles for Cross-Account Access

#### Account Two (Service Consumer Account)

In Account Two, create an IAM role (`MCSControllerSARole`) that the Cloud Map MCS Controller in Account One will assume. This role must include `AWSCloudMapFullAccess` permission and a trust relationship that allows the service account in Account One to assume this role.
   
Trust relationship policy for `MCSControllerSARole`:
    ```json
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": "sts:AssumeRoleWithWebIdentity",
                "Principal": {
                    "Federated": "arn:aws:iam::<ACCOUNT_ONE_ACCOUNTID>:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/<CLUSTER_ONE_OIDC_ID>"
                },
                "Condition": {
                    "StringEquals": {
                        "oidc.eks.us-east-1.amazonaws.com/id/<CLUSTER_ONE_OIDC_ID>:aud": [
                            "sts.amazonaws.com"
                       ]
                    }
                }
            }
        ]
    }
    ```

Create the IAM OIDC provider in Account One, pointing to the OIDC provider URL of Cluster Two, with `sts.amazonaws.com` as the audience.

### Step 2: Networking Configuration
In both Account One and Account Two, edit the VPC route tables to allow traffic between the VPCs. Update security groups to permit inbound traffic from the opposing account's EKS clusters.

### Step 3: Deploy the AWS Cloud Map MCS Controller
Deploy the AWS Cloud Map MCS Controller in both clusters, ensuring that the controller in Account Two is configured to assume the IAM role created in Account One.

### Step 4: Service Export and Import

**In Account One (Service Provider Account):** Deploy your Kubernetes services along with a `ServiceExport` object to indicate that the service should be made discoverable across clusters.

**In Account Two (Service Consumer Account):** Once the `ServiceExport` is applied in Account One, the Cloud Map MCS Controller in Account Two will automatically import the service, making it discoverable within Account Two.

### Step 5: Test Service Discovery
From a pod in Account One, verify that the service from Account Two is discoverable and accessible:
```bash
# nslookup <service-name>.demo.svc.clusterset.local
# curl -ivk <service-name>.demo.svc.clusterset.local
```



## Example
```bash
# nslookup nginx-hello.demo.svc.clusterset.local
Server:		172.20.0.10
Address:	172.20.0.10:53


Name:	nginx-hello.demo.svc.clusterset.local
Address: 172.20.40.24

 # curl -ivk nginx-hello.demo.svc.clusterset.local
* processing: nginx-hello.demo.svc.clusterset.local
*   Trying 172.20.40.24:80...
* Connected to nginx-hello.demo.svc.clusterset.local (172.20.40.24) port 80
> GET / HTTP/1.1
> Host: nginx-hello.demo.svc.clusterset.local
> User-Agent: curl/8.2.1
> Accept: */*
>
< HTTP/1.1 200 OK
HTTP/1.1 200 OK
< Server: nginx/1.25.2
Server: nginx/1.25.2
< Date: Fri, 15 Sep 2023 05:12:38 GMT
Date: Fri, 15 Sep 2023 05:12:38 GMT
< Content-Type: text/plain
Content-Type: text/plain
< Content-Length: 158
Content-Length: 158
< Connection: keep-alive
Connection: keep-alive
< Expires: Fri, 15 Sep 2023 05:12:37 GMT
Expires: Fri, 15 Sep 2023 05:12:37 GMT
< Cache-Control: no-cache
Cache-Control: no-cache

<
Server address: 172.31.16.41:80
Server name: nginx-demo-5694f64f59-phgc6
Date: 15/Sep/2023:05:12:38 +0000
URI: /

* Connection #0 to host nginx-hello.demo.svc.clusterset.local left intact
```

## Additional Configuration

Ensure the AWS Cloud Map namespace used for service discovery is created and accessible from both accounts.
Monitor the Cloud Map MCS Controller logs for any errors or warnings that might indicate issues with the setup.


## Reference

https://aws.amazon.com/blogs/opensource/kubernetes-multi-cluster-service-discovery-using-open-source-aws-cloud-map-mcs-controller/
