#!/usr/bin/env python3
"""
Simple HTTP log receiver for PoseTrainer debug logs.
Run this on your Windows PC to receive logs from the app over network.

Usage:
    python log_receiver.py [--port 8080] [--host 0.0.0.0]

The app should be configured to send logs to:
    http://YOUR_PC_IP:8080/logs
"""

import json
import logging
import argparse
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse
import socket

class LogReceiver(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/logs':
            try:
                content_length = int(self.headers['Content-Length'])
                post_data = self.rfile.read(content_length)
                log_entry = json.loads(post_data.decode('utf-8'))
                
                # Format and print the log
                timestamp = log_entry.get('timestamp', datetime.now().isoformat())
                level = log_entry.get('level', 'INFO').upper()
                message = log_entry.get('message', '')
                tag = log_entry.get('tag', '')
                error = log_entry.get('error', '')
                
                # Color coding for different log levels
                colors = {
                    'DEBUG': '\033[37m',    # White
                    'INFO': '\033[36m',     # Cyan
                    'WARNING': '\033[33m',  # Yellow
                    'ERROR': '\033[31m',    # Red
                }
                reset_color = '\033[0m'
                color = colors.get(level, '')
                
                # Format the output
                time_str = timestamp[11:19]  # HH:MM:SS
                tag_str = f'[{tag}] ' if tag else ''
                log_line = f"{time_str} {color}{level:7}{reset_color} {tag_str}{message}"
                
                print(log_line)
                
                if error:
                    print(f"         {color}ERROR:{reset_color} {error}")
                
                self.send_response(200)
                self.send_header('Content-type', 'text/plain')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                self.wfile.write(b'OK')
                
            except Exception as e:
                print(f"Error processing log: {e}")
                self.send_response(400)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()
    
    def do_OPTIONS(self):
        # Handle CORS preflight requests
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
    
    def do_GET(self):
        if self.path == '/':
            # Simple status page
            response = """
            <html>
            <head><title>PoseTrainer Log Receiver</title></head>
            <body>
                <h1>PoseTrainer Log Receiver</h1>
                <p>Status: Running</p>
                <p>Listening for logs at: <code>POST /logs</code></p>
                <p>Configure your app to send logs to:</p>
                <pre>http://{host}:{port}/logs</pre>
            </body>
            </html>
            """.format(host=get_local_ip(), port=self.server.server_port)
            
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(response.encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        # Suppress default HTTP server logs
        pass

def get_local_ip():
    """Get the local IP address"""
    try:
        # Connect to a remote address to determine local IP
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(('8.8.8.8', 80))
            return s.getsockname()[0]
    except:
        return '127.0.0.1'

def main():
    parser = argparse.ArgumentParser(description='PoseTrainer Log Receiver')
    parser.add_argument('--port', type=int, default=8080, help='Port to listen on')
    parser.add_argument('--host', default='0.0.0.0', help='Host to bind to')
    
    args = parser.parse_args()
    
    # Setup the server
    server = HTTPServer((args.host, args.port), LogReceiver)
    local_ip = get_local_ip()
    
    print("=" * 60)
    print("PoseTrainer Log Receiver")
    print("=" * 60)
    print(f"🚀 Server running at http://{local_ip}:{args.port}/")
    print(f"📱 Configure your app to send logs to:")
    print(f"   http://{local_ip}:{args.port}/logs")
    print()
    print("📋 Waiting for logs... (Press Ctrl+C to stop)")
    print("-" * 60)
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n\n🛑 Server stopped")
        server.server_close()

if __name__ == '__main__':
    main()