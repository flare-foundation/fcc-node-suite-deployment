from flask import Flask
from threading import Thread

# Internal server (port 6661)
internal_app = Flask("internal")

@internal_app.route("/")
def internal():
    return "Internal"

def run_internal():
    internal_app.run(host="0.0.0.0", port=6661)

# External server (port 6662)
external_app = Flask("external")

@external_app.route("/")
def external():
    return "External"

def run_external():
    external_app.run(host="0.0.0.0", port=6662)

# Run both servers in separate threads
Thread(target=run_internal).start()
Thread(target=run_external).start()

# Keep main thread alive
import time
while True:
    time.sleep(60)
