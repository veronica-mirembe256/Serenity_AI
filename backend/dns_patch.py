"""
dns_patch.py — Force Python to resolve DNS via Google (8.8.8.8).

On some Windows machines, Python's socket.getaddrinfo fails with
[Errno 11001] even when the browser works fine. This happens because
Windows DNS resolution for Python processes can be broken by:
  - VPNs that only route browser traffic
  - Corporate firewalls with process-level filtering
  - Misconfigured network adapters after moving files
  - IPv6 fallback issues in the Python socket layer

This patch uses dnspython to resolve hostnames directly via 8.8.8.8,
then monkey-patches socket.getaddrinfo so every library (httpx, supabase,
requests) automatically benefits without any code changes.
"""

import socket
import dns.resolver

# Build a resolver that goes straight to Google DNS
_resolver = dns.resolver.Resolver(configure=False)
_resolver.nameservers = ["8.8.8.8", "8.8.4.4"]
_resolver.timeout = 5
_resolver.lifetime = 5

_original_getaddrinfo = socket.getaddrinfo


def _patched_getaddrinfo(host, port, family=0, type=0, proto=0, flags=0):
    """
    Try to resolve host via dnspython first.
    Falls back to the original resolver if dnspython fails
    (e.g. for localhost, 127.0.0.1, IPv6 addresses).
    """
    # Do not patch numeric IPs or localhost
    try:
        socket.inet_aton(host)          # already an IPv4 address
        return _original_getaddrinfo(host, port, family, type, proto, flags)
    except (socket.error, TypeError):
        pass

    if host in ("localhost", "127.0.0.1", "::1"):
        return _original_getaddrinfo(host, port, family, type, proto, flags)

    try:
        answers = _resolver.resolve(host, "A")
        ip = str(answers[0])
        return _original_getaddrinfo(ip, port, family, type, proto, flags)
    except Exception:
        # Fall back to the original resolver
        return _original_getaddrinfo(host, port, family, type, proto, flags)


def apply():
    """Call this once at startup to activate the DNS patch."""
    socket.getaddrinfo = _patched_getaddrinfo
