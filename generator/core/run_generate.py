import threading
import subprocess
import signal
import sys

modules = [
    "runners.run_hpc",
    "runners.run_monitoring",
    "runners.run_syslog"
]

processes = []
stop_event = threading.Event()


def run_module(module_name):
    """Run a module as a subprocess and keep reference"""
    if stop_event.is_set():
        return

    p = subprocess.Popen([sys.executable, "-m", module_name])
    processes.append(p)
    p.wait()


def stop_all(signum=None, frame=None):
    """Stop all running processes"""
    print("\nStopping all services...")
    stop_event.set()

    for p in processes:
        if p.poll() is None:  # still running
            p.terminate()

    for p in processes:
        try:
            p.wait(timeout=5)
        except subprocess.TimeoutExpired:
            p.kill()

    print("All services stopped.")
    sys.exit(0)


# Handle Ctrl+C and kill signals
signal.signal(signal.SIGINT, stop_all)
signal.signal(signal.SIGTERM, stop_all)


threads = []

for module in modules:
    t = threading.Thread(target=run_module, args=(module,), daemon=True)
    t.start()
    threads.append(t)

# Keep main thread alive
try:
    for t in threads:
        t.join()
except KeyboardInterrupt:
    stop_all()