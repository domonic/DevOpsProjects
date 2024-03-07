# Zero Downtime Deployment on Kubernetes with ALB Ingress

This GitHub project outlines the methodology and configurations necessary to achieve zero downtime deployments in a Kubernetes environment, specifically when using the AWS ALB Ingress Controller on Amazon EKS. The focus is on preventing the common 502 errors that can occur during the deployment process, ensuring seamless service continuity for end-users.


# Overview

Deployments on Kubernetes can sometimes result in temporary service unavailability, commonly manifested as 502 Bad Gateway errors. These issues arise when the ALB attempts to route traffic to Pods that are terminating, leading to failed requests. This project implements a strategy to eliminate downtime and such errors, ensuring that the ALB only routes traffic to healthy Pods that are ready to handle requests.


# Key Concetps

**Graceful Shutdown**: Ensuring that Pods have enough time to finish processing ongoing requests before they are terminated.

**Pre-Stop Hook**: A Kubernetes feature used to delay the Pod termination process, giving services extra time to handle ongoing requests.

**Deregistration Delay**: A setting on the Target Group associated with the ALB, providing a buffer period before the ALB stops sending requests to the deregistering targets.



# Implementation Steps

1. **Configure Pre-Stop Hook**: Modify the Kubernetes deployment to include a Pre-Stop Hook. This script delays the termination of the Pod, allowing existing connections to be processed. For example, a sleep command can be used to provide a buffer.
    ```yaml
    lifecycle:
      preStop:
        exec:
          command: ["sleep", "30"]

2. **Adjust Readiness Probe**: The Readiness Probe is configured to fail immediately when the Pod is about to terminate. This ensures the Service stops sending new requests to the terminating Pod.
    ```yaml
    readinessProbe:
      exec:
        command: ["cat", "/tmp/healthy"]
      initialDelaySeconds: 5
      periodSeconds: 5
    ```


3. **Configure Deregistration Delay**: Set the deregistration delay for the Target Group in AWS to match the Pre-Stop Hook delay, ensuring the ALB only routes traffic to Pods that are fully ready and operational.
This can be configured through the AWS Management Console or via the AWS CLI.
Ensure the delay is sufficient for your application's needs.
**Test Deployment**: Perform a deployment to test the configuration. You should observe that the ALB does not route new requests to Pods that are terminating, effectively eliminating 502 errors during deployments.



# Implementation with Blue/Green Deployments

**Setup Separate Node Groups**: Create separate node groups in EKS for the blue and green environments. These will serve as distinct target groups under the ALB, allowing for independent scaling and management.
**Configure ALB Ingress to Manage Traffic**: Use annotations in your Kubernetes Ingress resource to manage traffic distribution between the blue and green target groups. Initially, all traffic is routed to the blue group.
    ```yaml
    annotations:
      alb.ingress.kubernetes.io/actions.forward-single-tg: >
        {"Type":"forward","ForwardConfig":{"TargetGroups":[{"ServiceName":"blue-service","ServicePort":"80"}]}}
    ```

**Deploy Green Environment**: Roll out the new version of your application to the green node group. At this stage, no live traffic is directed to the green environment, allowing for thorough testing and validation.
**Switch Traffic**: Once the green deployment is verified to be stable and ready, update the Ingress resource to switch traffic from the blue target group to the green target group. This can be done with no downtime, ensuring a seamless transition for end-users.
    ```yaml
    annotations:
      alb.ingress.kubernetes.io/actions.forward-single-tg: >
        {"Type":"forward","ForwardConfig":{"TargetGroups":[{"ServiceName":"green-service","ServicePort":"80"}]}}
    ```

**Monitor and Finalize**: After the traffic has been successfully rerouted to the green environment, monitor the application for any issues. If everything operates as expected, the blue environment can be decommissioned or kept as a rollback option.



# Benefits

Implementing this strategy ensures that your Kubernetes-hosted applications can be updated or scaled without introducing service interruptions or degrading the user experience. By carefully managing the lifecycle of Pods and their traffic, you achieve zero downtime deployments.




