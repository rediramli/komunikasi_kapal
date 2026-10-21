#!/usr/bin/env python3
"""
Stage 3 receiver (runs on the VPS). Accepts N pinned sub-stream connections that
together carry ONE logical stream, and reassembles it IN ORDER. This is where the
RTT-asymmetry penalty shows up: a chunk routed over the 90 ms SIM can hold up the
head of the stream even while 12 ms-SIM chunks pile up in the reorder buffer.

Per connection: 1 handshake byte (path id), then frames [seq:uint64][len:uint32][payload].

Reports (JSON): in-order goodput, stall fraction (time the head was blocked while
later data waited), reorder-buffer depth, bytes received vs delivered-in-order.
No clock sync needed -- all metrics are receiver-local wall clock.

Usage: mpproxy_recv.py --port 5301 --conns 8 [--idle 3]
"""
import argparse, json, socket, struct, sys, threading, time

HDR = struct.Struct("!QI")   # seq, length


class Reassembler:
    def __init__(self):
        self.lock = threading.Lock()
        self.buf = {}                 # seq -> payload
        self.next = 0
        self.delivered = 0            # in-order bytes delivered
        self.received = 0             # total bytes received (any order)
        self.stall_ns = 0
        self.block_since = None
        self.max_depth = 0
        self.first_t = None
        self.last_t = None

    def add(self, seq, data):
        now = time.monotonic_ns()
        with self.lock:
            if self.first_t is None:
                self.first_t = now
            self.last_t = now
            self.received += len(data)
            self.buf[seq] = data
            self.max_depth = max(self.max_depth, len(self.buf))
            # was the head blocked (next missing while we held later chunks)?
            if self.block_since is None and self.next not in self.buf and self.buf:
                self.block_since = now
            # deliver contiguous run
            while self.next in self.buf:
                self.delivered += len(self.buf.pop(self.next))
                self.next += 1
                if self.block_since is not None and self.next not in self.buf:
                    self.stall_ns += now - self.block_since
                    self.block_since = None

    def report(self):
        with self.lock:
            dur = (self.last_t - self.first_t) / 1e9 if self.first_t and self.last_t else 0
            gp = (self.delivered * 8 / 1e6 / dur) if dur > 0 else 0
            stall = self.stall_ns / 1e9
            stall_frac = stall / dur if dur > 0 else 0
            return {"dur_s": round(dur, 2),
                    "inorder_goodput_mbps": round(gp, 2),
                    "stall_s": round(stall, 2),
                    "stall_frac": round(stall_frac, 3),
                    "reorder_depth_max": self.max_depth,
                    "delivered_mb": round(self.delivered / 1e6, 2),
                    "received_mb": round(self.received / 1e6, 2)}


def reader(conn, re):
    try:
        f = conn.makefile("rb")
        f.read(1)                     # path id (label only)
        while True:
            h = f.read(HDR.size)
            if len(h) < HDR.size:
                break
            seq, ln = HDR.unpack(h)
            data = f.read(ln)
            if len(data) < ln:
                break
            re.add(seq, data)
    except Exception:
        pass
    finally:
        try: conn.close()
        except Exception: pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=5301)
    ap.add_argument("--conns", type=int, default=8)
    ap.add_argument("--idle", type=float, default=3.0, help="stop after this idle gap once started")
    a = ap.parse_args()

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", a.port))
    srv.listen(a.conns + 2)
    srv.settimeout(1.0)
    re = Reassembler()
    threads = []
    deadline = time.monotonic() + 20          # wait up to 20 s for the sender
    while len(threads) < a.conns and time.monotonic() < deadline:
        try:
            c, _ = srv.accept()
            c.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            t = threading.Thread(target=reader, args=(c, re), daemon=True)
            t.start(); threads.append(t)
        except socket.timeout:
            continue
    for t in threads:
        t.join()
    print(json.dumps(re.report()))


if __name__ == "__main__":
    main()
