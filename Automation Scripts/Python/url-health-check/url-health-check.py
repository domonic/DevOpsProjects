import requests


def url_list():
    urls_list = []

    with open("urls.txt", "r") as file:
        for url in file:
            urls_list.append(url.strip())  
    
    return urls_list

def health_check_url(url):
    try:
        response = requests.get(url, timeout=5, allow_redirects=False)
        print("\n=============================================")
        print("\nREQUEST DETAILS:")
        print("\n=============================================")
        print()
        print("Request URL:", response.request.url)
        print("Request Method:", response.request.method)
        print("Request Headers:", response.request.headers)
        
        print("\n=============================================")
        print("\nResponse Details:")
        print("\n=============================================")
        print()
        print("Response Headers:\n", response.headers)
        return response.status_code
    
    except requests.RequestException as e:
        return str(e)
    
    


def main(urls):
    for url in urls:
        health_check = health_check_url(url)
        print("\n=============================================")
        print("\nURL - Status Code")
        print("\n=============================================")
        if isinstance(health_check, int):
            if 200 <= health_check <= 299:
                print(f"URL: {url} Status Code: {health_check}")
                print("✅ Success")
            elif 301 <= health_check <= 399:
                print(f"URL: {url} Status Code: {health_check}")
                print("🔄 Redirection")
            
            elif 400 <= health_check <= 499:
                print(f"URL: {url} Status Code: {health_check}")
                print("⚠️ Client Error")
            
            elif 500 <= health_check <= 599:
                print(f"URL: {url} Status Code: {health_check}")
                print("❌ Server Error")

        else:
            print("\n=============================================")
            print("\nURL - Status Code")
            print("\n=============================================")
            print(f"URL: {url} Status Code: {health_check}")
            print("❓ Unknown Error Occurred - Please see Status Code Details Above!")







urls_list = url_list()
main(urls_list)



