import ipaddress
from ipaddress import IPv4Network

def ipClass(ipv4Address):
    classA = IPv4Network(("10.0.0.0", "255.0.0.0"))
    classB = IPv4Network(("172.16.0.0", "255.240.0.0")) 
    classC = IPv4Network(("192.168.0.0", "255.255.0.0"))
    
    if ipv4Address in classA:
        print('IP Address Class: A')
    elif ipv4Address in classB:
        print('IP Address Class: B')
    elif ipv4Address in classC:
        print('IP Address Class: C')
    else:
        print('IP Address Class: NA')


def ipType(ipv4Address):
    if IPv4Network(ipv4Address, False).is_private:
         print('IP Address Type: Private')
    else:
        print("IP Address Type: Public")

def numSubnets(ipv4Address):
    subnetBits = 0
    borrowedBits = 0
    
    ipv4AddressOctList = str(IPv4Network(ipv4Address, False).with_prefixlen.split('/')[0])
    finalIPv4AddressOctList = (ipv4AddressOctList.split("."))
    ipv4AddressOctListBinary = [format(int(i), '08b') for i in finalIPv4AddressOctList]
    subnetMask = str((IPv4Network(ipv4Address, False).netmask))
    subnetMaskList = subnetMask.split(".")
    subnetMaskBinary = [format(int(i), '08b') for i in subnetMaskList]  
     
    for octect in range(len(ipv4AddressOctListBinary)):
        if ipv4AddressOctListBinary[octect] == '00000000':
            subnetBits += 8

    for octect in range(len(subnetMaskBinary)):
        for char in subnetMaskBinary[octect]:
            if char == '0':
                borrowedBits += 1

    if pow(2,(subnetBits-borrowedBits)) < 1:
        print(f'Number of subnets available: NA')
    else:    
        print(f'Number of subnets available: {pow(2,(subnetBits-borrowedBits))}')
           

def outputNetworkInfo(ipv4Address):
    print(f'You have entered: {ipv4Address}')
    print(f'Below is the Network Information for {ipv4Address}')
    print('\n-------------------------------------------------------')
    ipClass(ipv4Address)
    ipType(ipv4Address)
    print(f'Network Address: {ipv4Address.network}')
    print(f'CIDR Notation:', IPv4Network(ipv4Address, False).with_prefixlen.split('/')[1])
     
def outputAdditionalNetworkInfo(ipv4Address: IPv4Network):
    print(f'Subnet Mask: {IPv4Network(ipv4Address, False).netmask}')
    numSubnets(ipv4Address)
    if (IPv4Network(ipv4Address, False).num_addresses-2) > 0:
        print(f'Number of usable host addresses per subnet: {(IPv4Network(ipv4Address, False).num_addresses-2)}')
        print(f'First usable IP Address: {(IPv4Network(ipv4Address, False).network_address+1)}')
        print(f'Last usable IP Address: {(IPv4Network(ipv4Address, False).broadcast_address-1)} ')
        print(f'Broadcast address: {(IPv4Network(ipv4Address, False).broadcast_address)}')
    else: 
        print(f'Number of usable host addresses per subnet: 0')
        print(f'First usable IP Address: NA')
        print(f'Last usable IP Address: NA')
        print(f'Broadcast address: {(IPv4Network(ipv4Address, False).broadcast_address)}')


if __name__ == '__main__':
    running = '1'
    while running == '1':
        try:
            print('\n')
            ipv4Address = ipaddress.ip_interface(input("Please enter a IPv4 Address i.e. (192.168.0.0/32): "))
            networkInfo = outputNetworkInfo(ipv4Address)
            additionalNetworkInfo = outputAdditionalNetworkInfo(IPv4Network(ipv4Address, False))
            print('\n-------------------------------------------------------')
            running = (input("\nTo Exit Press Any Key or to Continue Press 1: "))
            
        except Exception as e:
            print(e)
            continue
            
            

