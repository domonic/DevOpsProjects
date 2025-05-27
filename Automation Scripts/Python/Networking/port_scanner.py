# Soket Moduel is used to make connections to a host on  a specific port
import socket
# Threading will allow for running multiple scanning functions simultaneously
import threading
# Queue will assist in ensuring that each port is only scanned once
from queue import Queue


def printPortMenu():
    print('Below are the avaialbe Port Mode Selections')
    print('\n-------------------------------------------------------')
    print('\nMode 1: Ports 1 - 1024')
    print('Mode 2: Ports 1 - 49152')
    print('Mode 3: Common Ports 20, 21, 22, 23, 25, 53, 80, 110, 443')
    print('Mode 4: Manual Entry of Ports')

def getPorts(mode):
    if mode == 1:
        for port in range(1, 1024):
            queue.put(port)
    elif mode == 2:
        for port in range(1, 49152):
            queue.put(port)
    elif mode == 3:
        ports = [20, 21, 22, 23, 25, 53, 80, 110, 443]
        for port in ports:
            queue.put(port)
    elif mode == 4:
        ports = input("\nEnter your ports (seperated by a space):")
        ports = ports.split()
        ports = list(map(int, ports))
        for port in ports:
            queue.put(port)

def portScan(port):
    try:
        targetConnection = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        targetConnection.connect((targetIP, port))
        return True
    except:
        return False

def runScanner(threads, portMode):
    getPorts(portMode)
    threadsList = []

    for t in range(threads):
        thread = threading.Thread(target=worker)
        threadsList.append(thread)

    for thread in threadsList:
        thread.start()
    
    for thread in threadsList:
        thread.join()
    
    print('Target Open Ports Are:', portsOpen)

def worker():
    while not queue.empty():
        port = queue.get()
        if portScan(port):
            print(" This Port {} is open!".format(port))
            portsOpen.append(port)
        else:
            print("Sorry Port {} is closed!".format(port))


if __name__ == '__main__':
    queue = Queue()
    portsOpen = []
    running = '1'
    while running == '1':
        try:
            print('\n')
            targetIP = (input("\nPlease enter a IPv4 Address i.e. (192.168.0.0): "))
            portModeMenu = printPortMenu()
            portMode = int(input("\nPlease Select an Avaialbe Port Mode: "))
            numThreads = int(input("Please Enter Number of Threads: "))
            runScanner(numThreads, portMode)
            print('\n-------------------------------------------------------')
            running = (input("\nTo Exit Press Any Key or to Continue Press 1: "))
            
        except Exception as e:
            print(e)
            continue

