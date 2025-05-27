import socket
import time

def measure_tcp_latency(host, port=80, attempts=4, timeout=2):
    latencies = []
    print(f"\nTesting {host}:{port}")
    
    for i in range(attempts):
        try:
            start = time.time()
            with socket.create_connection((host, port), timeout=timeout):
                latency_ms = (time.time() - start) * 1000
                latencies.append(latency_ms)
                print(f"  Attempt {i+1}: {latency_ms:.2f} ms")
        except socket.error as e:
            print(f"  Attempt {i+1}: Failed ({e})")

    if latencies:
        avg = sum(latencies) / len(latencies)
        print(f"  ✅ Avg: {avg:.2f} ms | Min: {min(latencies):.2f} ms | Max: {max(latencies):.2f} ms")
    else:
        print("  ❌ All attempts failed.")

def multiple_hosts(hosts, port=80, attempts=4):
    for host in hosts:
        measure_tcp_latency(host, port, attempts)

if __name__ == '__main__':
    hosts = [
        'google.com',
        'cloudflare.com',
        'amazon.com',
        'openai.com'
    ]
    multiple_hosts(hosts, port=80, attempts=5)
