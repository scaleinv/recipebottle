import socket
import time
import struct
import select
import requests
import os
import json
import time
import subprocess

def python_ping(host, count=4, timeout=2):
    try:
        ip = socket.gethostbyname(host)
    except socket.gaierror:
        return f"Could not resolve hostname: {host}"

    icmp = socket.getprotobyname("icmp")
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_RAW, icmp)
    except PermissionError:
        return "Raw socket creation requires root privileges"

    results = []
    for _ in range(count):
        try:
            sock.sendto(b"", (ip, 0))
            start_time = time.time()
            ready = select.select([sock], [], [], timeout)
            if ready[0]:
                end_time = time.time()
                rtt = (end_time - start_time) * 1000
                results.append(f"Reply from {ip}: time={rtt:.2f}ms")
            else:
                results.append(f"Request timed out")
        except Exception as e:
            results.append(f"Error: {str(e)}")

    sock.close()
    return "\n".join(results)

def check_dns_resolution(hostname="api.anthropic.com"):
    try:
        ip_address = socket.gethostbyname(hostname)
        return f"DNS resolution successful. {hostname} resolves to {ip_address}"
    except socket.gaierror:
        return f"DNS resolution failed for {hostname}"

def check_http_connection(url="https://api.anthropic.com"):
    try:
        response = requests.get(url, timeout=5)
        return f"HTTP connection successful. Status code: {response.status_code}"
    except requests.RequestException as e:
        return f"HTTP connection failed: {str(e)}"

def get_network_info():
       try:
           result = subprocess.run(['ip', '-j', 'addr'], capture_output=True, text=True)
           ip_info = json.loads(result.stdout)
           
           info = "Network interface information:\n"
           for interface in ip_info:
               info += f"Interface: {interface['ifname']}\n"
               info += f"  MAC Address: {interface.get('address', 'Not available')}\n"
               for addr_info in interface.get('addr_info', []):
                   if addr_info['family'] == 'inet':
                       info += f"  IP Address: {addr_info['local']}\n"
           return info
       except Exception as e:
           return f"Failed to retrieve network interface information: {str(e)}"

def check_environment_variables():
    relevant_vars = ['ANTHROPIC_API_KEY', 'HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY']
    env_info = "Environment variables:\n"
    for var in relevant_vars:
        value = os.environ.get(var, 'Not set')
        if var == 'ANTHROPIC_API_KEY' and value != 'Not set':
            value = value[:5] + '...' + value[-5:]  # Mask the API key
        env_info += f"{var}: {value}\n"
    return env_info

def test_api_performance(num_requests=10):
    api_key = os.environ.get('ANTHROPIC_API_KEY')
    headers = {
        "x-api-key": api_key,
        "content-type": "application/json",
        "anthropic-version": "2023-06-01"
    }
    data = {
        "model": "claude-3-5-sonnet-20240620",
        "max_tokens": 1024,
        "messages": [{"role": "user", "content": "Hello, Claude"}]
    }
    
    total_time = 0
    for i in range(num_requests):
        start_time = time.time()
        response = requests.post("https://api.anthropic.com/v1/messages", headers=headers, json=data)
        end_time = time.time()
        total_time += (end_time - start_time)
        print(f"Request {i + 1}: {response.status_code}, Time: {end_time - start_time:.2f}s")
    
    print(f"\nAverage response time: {total_time / num_requests:.2f}s")

def run_diagnostics():
    print("Running network diagnostics...\n")
    print(check_dns_resolution())
    print("\nPython Ping:")
    print(python_ping("api.anthropic.com"))
    print(check_http_connection())
    print(get_network_info())
    print(check_environment_variables())
    print("\nTesting API performance:")
    test_api_performance()

