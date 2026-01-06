#!/usr/bin/env python3
"""
Message verification script for pg_amqp integration tests.

This script connects to RabbitMQ, sets up test queues, and verifies
that messages published by pg_amqp arrive correctly.

Usage:
    ./verify_messages.py setup          # Create exchange and queue
    ./verify_messages.py verify N       # Verify N messages in queue
    ./verify_messages.py verify-message "expected content"
    ./verify_messages.py count          # Count messages in queue
    ./verify_messages.py cleanup        # Remove test exchange and queue
    ./verify_messages.py purge          # Purge all messages from queue
    ./verify_messages.py check          # Check Management API is accessible
"""

import sys
import os
import json
import urllib.request
import urllib.error
import urllib.parse
import base64
import time

# RabbitMQ connection settings (configurable via environment)
RABBITMQ_HOST = os.environ.get("RABBITMQ_HOST", "localhost")
RABBITMQ_PORT = int(os.environ.get("RABBITMQ_PORT", "15672"))  # Management API port
RABBITMQ_USER = os.environ.get("RABBITMQ_USER", "guest")
RABBITMQ_PASS = os.environ.get("RABBITMQ_PASS", "guest")
RABBITMQ_VHOST = os.environ.get("RABBITMQ_VHOST", "/")

# Test resources
TEST_EXCHANGE = "pg_amqp_verify_exchange"
TEST_QUEUE = "pg_amqp_verify_queue"

# Retry settings
MAX_RETRIES = 30
RETRY_DELAY = 0.2  # 200ms between retries

def api_request(method, path, data=None):
    """Make a request to the RabbitMQ Management API."""
    url = f"http://{RABBITMQ_HOST}:{RABBITMQ_PORT}/api/{path}"
    credentials = base64.b64encode(f"{RABBITMQ_USER}:{RABBITMQ_PASS}".encode()).decode()

    headers = {
        "Authorization": f"Basic {credentials}",
        "Content-Type": "application/json",
    }

    body = json.dumps(data).encode() if data else None
    request = urllib.request.Request(url, data=body, headers=headers, method=method)

    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            if response.status in (201, 204):
                return None
            content = response.read().decode()
            return json.loads(content) if content else None
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise

def setup():
    """Set up test exchange and queue."""
    vhost = urllib.parse.quote(RABBITMQ_VHOST, safe="")

    # Clean up any existing resources
    print("Cleaning up any existing test resources...")
    try:
        api_request("DELETE", f"queues/{vhost}/{TEST_QUEUE}")
    except:
        pass
    try:
        api_request("DELETE", f"exchanges/{vhost}/{TEST_EXCHANGE}")
    except:
        pass

    # Declare fanout exchange
    print(f"Declaring exchange: {TEST_EXCHANGE}")
    api_request("PUT", f"exchanges/{vhost}/{TEST_EXCHANGE}", {
        "type": "fanout",
        "durable": False,
        "auto_delete": False,
    })

    # Declare queue
    print(f"Declaring queue: {TEST_QUEUE}")
    api_request("PUT", f"queues/{vhost}/{TEST_QUEUE}", {
        "durable": False,
        "auto_delete": False,
    })

    # Bind queue to exchange
    print("Binding queue to exchange")
    api_request("POST", f"bindings/{vhost}/e/{TEST_EXCHANGE}/q/{TEST_QUEUE}", {
        "routing_key": "",
    })

    print("Setup complete!")
    return 0

def get_messages(count=100, ack=True):
    """Get messages from the test queue."""
    vhost = urllib.parse.quote(RABBITMQ_VHOST, safe="")
    result = api_request("POST", f"queues/{vhost}/{TEST_QUEUE}/get", {
        "count": count,
        "ackmode": "ack_requeue_false" if ack else "ack_requeue_true",
        "encoding": "auto",
    })
    return result or []

def get_queue_count():
    """Get current message count in queue."""
    vhost = urllib.parse.quote(RABBITMQ_VHOST, safe="")
    queue_info = api_request("GET", f"queues/{vhost}/{TEST_QUEUE}")
    return queue_info.get("messages", 0) if queue_info else -1

def count_messages():
    """Count and print messages in the test queue."""
    count = get_queue_count()
    if count >= 0:
        print(f"Messages in queue: {count}")
        return count
    else:
        print("Queue not found")
        return -1

def verify_count(expected):
    """Verify the message count matches expected (with retries)."""
    actual = 0
    last_count = -1
    stable_count = 0

    for _ in range(MAX_RETRIES):
        actual = get_queue_count()
        if actual < 0:
            print("ERROR: Queue not found")
            return 1
        if actual >= expected:
            print(f"OK: Found {actual} messages (expected at least {expected})")
            return 0

        # Track if count is stable (not still receiving messages)
        if actual == last_count:
            stable_count += 1
            # If count has been stable for 5 attempts and we have some messages, fail early
            if stable_count >= 5 and actual > 0:
                break
        else:
            stable_count = 0
            last_count = actual

        time.sleep(RETRY_DELAY)

    print(f"FAIL: Found {actual} messages (expected at least {expected})")
    return 1

def verify_message(expected_content):
    """Verify a specific message exists and consume it."""
    messages = []
    for _ in range(MAX_RETRIES):
        # Peek at messages without consuming
        messages = get_messages(count=100, ack=False)
        for msg in messages:
            if msg.get("payload", "") == expected_content:
                # Found it - now consume all messages to clean up
                get_messages(count=100, ack=True)
                print(f"OK: Found message: {expected_content}")
                return 0
        time.sleep(RETRY_DELAY)

    print(f"FAIL: Message not found: {expected_content}")
    print(f"Messages in queue ({len(messages)}):")
    for msg in messages:
        print(f"  - {msg.get('payload', '')}")
    return 1

def verify_empty():
    """Verify queue is empty (with retries for async operations)."""
    count = 0
    for _ in range(MAX_RETRIES):
        count = get_queue_count()
        if count == 0:
            print("OK: Queue is empty")
            return 0
        if count < 0:
            print("ERROR: Queue not found")
            return 1
        time.sleep(RETRY_DELAY)

    print(f"FAIL: Expected 0 messages, found {count}")
    return 1

def purge():
    """Purge all messages from the test queue."""
    vhost = urllib.parse.quote(RABBITMQ_VHOST, safe="")
    print(f"Purging queue: {TEST_QUEUE}")
    api_request("DELETE", f"queues/{vhost}/{TEST_QUEUE}/contents")
    print("Queue purged!")
    return 0

def cleanup():
    """Remove test exchange and queue."""
    vhost = urllib.parse.quote(RABBITMQ_VHOST, safe="")

    print(f"Deleting queue: {TEST_QUEUE}")
    try:
        api_request("DELETE", f"queues/{vhost}/{TEST_QUEUE}")
    except:
        pass

    print(f"Deleting exchange: {TEST_EXCHANGE}")
    try:
        api_request("DELETE", f"exchanges/{vhost}/{TEST_EXCHANGE}")
    except:
        pass

    print("Cleanup complete!")
    return 0

def check_api():
    """Check if RabbitMQ Management API is accessible."""
    result = api_request("GET", "overview")
    if result:
        print("RabbitMQ Management API is accessible")
        print(f"RabbitMQ version: {result.get('rabbitmq_version', 'unknown')}")
        return 0
    else:
        print("ERROR: Cannot connect to RabbitMQ Management API")
        return 1

def list_messages():
    """List all messages in the queue (without consuming)."""
    messages = get_messages(count=100, ack=False)
    print(f"Messages in queue ({len(messages)}):")
    for i, msg in enumerate(messages):
        print(f"  [{i+1}] routing_key={msg.get('routing_key', '')}")
        print(f"       payload={msg.get('payload', '')}")
        props = msg.get("properties", {})
        if props.get("content_type"):
            print(f"       content_type={props.get('content_type')}")
        if props.get("delivery_mode"):
            print(f"       delivery_mode={props.get('delivery_mode')}")
    return 0

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    command = sys.argv[1]

    try:
        if command == "setup":
            return setup()
        elif command == "verify":
            if len(sys.argv) < 3:
                print("Usage: verify_messages.py verify N")
                return 1
            return verify_count(int(sys.argv[2]))
        elif command == "verify-message":
            if len(sys.argv) < 3:
                print("Usage: verify_messages.py verify-message 'content'")
                return 1
            return verify_message(sys.argv[2])
        elif command == "verify-empty":
            return verify_empty()
        elif command == "count":
            return 0 if count_messages() >= 0 else 1
        elif command == "list":
            return list_messages()
        elif command == "purge":
            return purge()
        elif command == "cleanup":
            return cleanup()
        elif command == "check":
            return check_api()
        else:
            print(f"Unknown command: {command}")
            print(__doc__)
            return 1
    except urllib.error.URLError as e:
        print(f"ERROR: Cannot connect to RabbitMQ Management API: {e}")
        print("Make sure RabbitMQ is running with the management plugin enabled.")
        return 1
    except Exception as e:
        print(f"ERROR: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())
