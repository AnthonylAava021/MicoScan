import requests
import json

API_KEY = ""

modelos = [
    "gemini-1.5-flash",
    "gemini-1.5-flash-latest",
    "gemini-1.0-pro",
    "gemini-1.0-pro-latest",
    "gemini-2.0-flash",
]

prompt = "Hola, responde con 'OK' si me puedes leer."

for modelo in modelos:
    print(f"\nProbando modelo: {modelo}")
    print(f"URL: https://generativelanguage.googleapis.com/v1beta/models/{modelo}:generateContent")
    
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{modelo}:generateContent?key={API_KEY}"
    
    payload = {
        "contents": [
            {
                "parts": [
                    {"text": prompt}
                ]
            }
        ]
    }
    
    try:
        response = requests.post(
            url,
            headers={"Content-Type": "application/json"},
            json=payload,
            timeout=10
        )
        
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print("✅ ÉXITO!")
            print(f"Respuesta: {data.get('candidates', [{}])[0].get('content', {}).get('parts', [{}])[0].get('text', 'N/A')}")
            break
        else:
            print(f"❌ Error: {response.text[:200]}")
    except Exception as e:
        print(f"❌ Excepción: {e}")
