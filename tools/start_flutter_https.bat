@echo off
pushd %~dp0
cd ..
flutter run -d web-server --web-hostname=0.0.0.0 --web-port=5000 --web-header="Cross-Origin-Opener-Policy=same-origin-allow-popups" --web-tls-cert-path="localhost+1.pem" --web-tls-cert-key-path="localhost+1-key.pem"
popd