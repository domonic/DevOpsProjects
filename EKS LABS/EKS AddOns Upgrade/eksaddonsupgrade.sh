#! /bin/bash

# Get the current context for the current cluster
echo "=========================================="
echo "=           EKS CLUSTER NAME             ="
echo "=========================================="

cluster_name=$(kubectl config current-context | cut -d "/" -f 2)
echo "            ${cluster_name}               "

echo "                                          "
echo "                                          "

# Get the cluster version: 
echo "=========================================="
echo "=           EKS CLUSTER VERSION          ="
echo "=========================================="

cluster_version=$(aws eks describe-cluster --name k8s-basic-cluster --query "cluster.version" --output text)
echo "                 ${cluster_version}       "

echo "                                          "
echo "                                          "

echo "=========================================="
echo "=  CURRENT ADD-ONS INSTALLED & VERSIONS  ="
echo "=========================================="

# Check if Add on is installed: 
addons_list=$(aws eks list-addons --cluster-name $cluster_name  --query 'addons[]'  --output text)

echo "Now Performing backup of installed addons..."
echo "                                          "
# Take backup of Add ons:
kubectl get deploy coredns -n kube-system -o yaml > coredns-old.yaml
echo "Backing up coredns config..."
sleep 3
echo "COREDNS SUCCESSFULLY BACKED UP"
echo "                                          "

kubectl get daemonset kube-proxy -n kube-system  -o yaml > kube-proxy-old.yaml
echo "Backing up kube-proxy config..."
sleep 3
echo "KUBE-PROXY SUCCESSFULLY BACKED UP"
echo "                                          "

kubectl get daemonset aws-node -n kube-system  -o yaml > vpc-cni-old.yaml
echo "Backing up vpc-cni config..."
sleep 3
echo "VPC-CNI SUCCESSFULLY BACKED UP"

echo "                                          "
echo "                                          "

echo "=========================================="
echo "=      EKS ADD-ON UPGRADE PERFORMED      ="
echo "=========================================="

# View Add on current version & store available add on versions to add on text file: 
for addon in ${addons_list}; do

    # Grab the current running of the EKS Add On
    current_addonversion=$(aws eks describe-addon --cluster-name $cluster_name --addon-name ${addon} --query "addon.addonVersion" --output text)
    echo "Currently the EKS Add-On ${addon}  is running on version  -  ${current_addonversion}"

    # Store all of the available versions for the EKS Add-On into text file
    aws eks describe-addon-versions --kubernetes-version ${cluster_version} --addon-name ${addon} \
        --query 'addons[].addonVersions[].{Version: addonVersion}' --output text > ${addon}-availableversions.txt
    
    # Iterate through the available versions text file until the current version is located and only keep the versions beyond the current version and add them to the upgrade list text file 
    awk -v target="$current_addonversion" '{if ($0 ~ target) found=1} {if (!found) print}' "${addon}-availableversions.txt" > "${addon}-upgradelist.txt" 

    # Delete the available versions text file as it is no longer needed    
    rm ${addon}-availableversions.txt     
    echo "Starting Upgrade for EKS Add-On - ${addon}..."
    echo "                                          "
    # Read the upgrade list text file in reverse line by line to perform the upgrade from oldest remaining available version to the latest version
    while read -r line; do 
        aws eks update-addon --cluster-name ${cluster_name} --addon-name ${addon} --addon-version ${line} \
            --configuration-values '{}' --resolve-conflicts OVERWRITE
        echo "                                          "
        echo "Upgrade of EKS Add-On ${addon} to version:  ${line} started successfully"
        sleep 10
        echo "Upgrade of EKS Add-On ${addon} is still in progress..."
        echo "                                          "
        sleep 50
        echo "Upgrade of EKS Add-On ${addon} to version:  ${line} has successfully completed!"
        echo "                                          "
        sleep 5
    done < <(tac "${addon}-upgradelist.txt")
done
echo "                                          "
echo "                                          "

echo "=========================================="
echo "=      EKS ADD-ON UPGRADE COMPLETED      ="
echo "=========================================="
for addon in ${addons_list}; do
    latest_addonversion=$(aws eks describe-addon --cluster-name $cluster_name --addon-name ${addon} --query "addon.addonVersion" --output text)
    echo "EKS Add-On ${addon}  is now running latest version  -  ${latest_addonversion}"
done

echo "                                          "
echo "                                          "


