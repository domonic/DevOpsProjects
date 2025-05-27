import subprocess
import re

def run_tcpdump(interface='en0', duration=10, filter_expr='tcp'):
    print(f"Running tcpdump on {interface} for {duration} seconds...")

    try:
        # Run tcpdump for a fixed duration
        proc = subprocess.Popen(
            ['tcpdump', '-i', interface, '-nn', '-tt', filter_expr],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )

        try:
            # Wait for the duration then terminate
            proc.wait(timeout=duration)
        except subprocess.TimeoutExpired:
            proc.terminate()

        output, _ = proc.communicate()

        lines = output.decode().splitlines()
        print(f"\nCaptured {len(lines)} packets. First 5 shown:\n")
        for line in lines[:5]:
            print("  ", line)

        # Optional: Parse and analyze packets
        parse_tcpdump_output(lines)

    except FileNotFoundError:
        print("❌ Error: tcpdump not found. Make sure it's installed.")
    except Exception as e:
        print(f"❌ Error running tcpdump: {e}")

def parse_tcpdump_output(lines):
    tcp_pattern = re.compile(r'IP (\S+) > (\S+): Flags \[(.*?)\], seq (\d+), ack (\d+), .*length (\d+)')
    print("\nParsed TCP packets:")
    print(f"{'Source':<20} {'→':<2} {'Destination':<18} | {'Flags':<7} | {'Seq':<12} | {'Ack':<12} | {'Len':<7}")
    print("-" * 105)

    for line in lines:
        match = tcp_pattern.search(line)
        if match:
            src, dst, flags, seq, ack, length = match.groups()
            print(f"  {src} → {dst} | Flags: {flags} | Seq: {seq} | Ack: {ack} | Len: {length}")

if __name__ == '__main__':
    run_tcpdump(interface='en0', duration=30, filter_expr='tcp')
