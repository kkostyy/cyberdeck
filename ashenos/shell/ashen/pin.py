#!/usr/bin/env python3
"""Lock-screen PIN: salted SHA-256 in ~/.config/ashen/pin (mode 600).

  pin.py set      PIN on stdin (4–8 digits)      pin.py check   PIN on stdin → exit 0 if it matches
  pin.py clear                                    pin.py status  → "set" | "unset"
"""
import hashlib
import hmac
import os
import sys

PATH = os.path.expanduser("~/.config/ashen/pin")


def digest(salt, pin):
    return hashlib.pbkdf2_hmac("sha256", pin.encode(), salt, 200_000).hex()


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "status":
        print("set" if os.path.isfile(PATH) else "unset")
    elif cmd == "clear":
        if os.path.isfile(PATH):
            os.remove(PATH)
    elif cmd == "set":
        pin = sys.stdin.readline().strip()
        if not (pin.isdigit() and 4 <= len(pin) <= 8):
            sys.exit("PIN: 4–8 цифр")
        salt = os.urandom(16)
        os.makedirs(os.path.dirname(PATH), exist_ok=True)
        fd = os.open(PATH, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(salt.hex() + ":" + digest(salt, pin) + "\n")
    elif cmd == "check":
        pin = sys.stdin.readline().strip()
        try:
            salt_hex, want = open(PATH).read().strip().split(":")
        except (OSError, ValueError):
            sys.exit(2)
        sys.exit(0 if hmac.compare_digest(digest(bytes.fromhex(salt_hex), pin), want) else 1)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
