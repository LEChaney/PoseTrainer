import http.server
import ssl
import os
from pathlib import Path

# Get the directory where this script is located
SCRIPT_DIR = Path(__file__).parent.resolve()

# Certificate files in the same directory as this script
CERT_FILE = SCRIPT_DIR / "localhost+1.pem"
KEY_FILE = SCRIPT_DIR / "localhost+1-key.pem"

# Server configuration
HOST = "0.0.0.0"  # Listen on all interfaces
PORT = 5000

def main():
    # Verify certificate files exist
    if not CERT_FILE.exists():
        print(f"❌ Certificate not found: {CERT_FILE}")
        return
    if not KEY_FILE.exists():
        print(f"❌ Key file not found: {KEY_FILE}")
        return
    
    # Change to the script directory to serve files from there
    os.chdir(SCRIPT_DIR)
    
    # Create HTTPS server
    server_address = (HOST, PORT)
    httpd = http.server.HTTPServer(server_address, http.server.SimpleHTTPRequestHandler)
    
    # Wrap socket with SSL
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=str(CERT_FILE), keyfile=str(KEY_FILE))
    httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
    
    print(f"🔒 HTTPS Server running at https://localhost:{PORT}/")
    print(f"📁 Serving files from: {SCRIPT_DIR}")
    print(f"🔑 Using certs:")
    print(f"   - {CERT_FILE.name}")
    print(f"   - {KEY_FILE.name}")
    print("\nPress Ctrl+C to stop the server")
    
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n\n👋 Server stopped")

if __name__ == "__main__":
    main()
