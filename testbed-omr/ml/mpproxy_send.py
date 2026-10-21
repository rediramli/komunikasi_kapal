#!/usr/bin/env python3
"""
Stage 3 sender (runs on the RPi). Carries ONE logical stream over N sub-streams,
each pinned to a SIM by source-binding to that WAN's IP (OMR routes it out that
SIM, bypassing glorytun). A scheduler assigns every chunk (monotonic seq) to a
path; the receiver reassembles in order. This is the real multipath video proxy.

Each connection has its own writer thread pulling from a bounded queue, so a slow
SIM backs up only its own queue -- the fast SIM keeps flowing (and, with
work-stealing, picks up the slack).

Schedulers:
  weighted : send a fraction w of chunks to Simba (path 1), the rest to Singtel.
             w is the control knob the ML policy sets. (w=1 => fast SIM only.)
  rr       : round-robin across all connections, path-agnostic (naive).

Usage (run on the RPi):
  mpproxy_send.py --host <vps> --port 5301 --n1 4 --n2 4 --w 0.5 \
                  --dur 6 --bitrate 0        # 0 = greedy (max in-order goodput)
"""
import argparse, queue, socket, struct, sys, threading, time

HDR = struct.Struct("!QI")
WAN1_IP = "192.168.1.100"    # Simba  (wan1, ~12 ms)
WAN2_IP = "192.168.2.100"    # Singtel (wan2, ~90 ms)
CHUNK = 1200                 # payload bytes per chunk (~1 MTU)


def connect(host, port, src_ip, path_id):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((src_ip, 0))                      # <-- pins this sub-stream to that SIM
    s.connect((host, port))
    s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    s.sendall(bytes([path_id]))
    return s


def writer(sock, q, stop):
    try:
        while True:
            item = q.get()
            if item is None:
                break
            seq, data = item
            sock.sendall(HDR.pack(seq, len(data)) + data)
    except Exception:
        stop.set()
    finally:
        try: sock.shutdown(socket.SHUT_WR)
        except Exception: pass
        try: sock.close()
        except Exception: pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", required=True)
    ap.add_argument("--port", type=int, default=5301)
    ap.add_argument("--n1", type=int, default=4)      # Simba sub-streams
    ap.add_argument("--n2", type=int, default=4)      # Singtel sub-streams
    ap.add_argument("--w", type=float, default=0.5)   # fraction of chunks to Simba
    ap.add_argument("--sched", choices=["weighted", "rr"], default="weighted")
    ap.add_argument("--dur", type=float, default=6.0)
    ap.add_argument("--bitrate", type=float, default=0.0, help="Mbps; 0 = greedy")
    ap.add_argument("--qdepth", type=int, default=64)
    ap.add_argument("--strict", action="store_true",
                    help="no work-stealing: honour the split w exactly (shows its true cost)")
    a = ap.parse_args()

    socks1 = [connect(a.host, a.port, WAN1_IP, 1) for _ in range(a.n1)]
    socks2 = [connect(a.host, a.port, WAN2_IP, 2) for _ in range(a.n2)]
    all_socks = socks1 + socks2
    queues = [queue.Queue(maxsize=a.qdepth) for _ in all_socks]
    q1 = [queues[i] for i in range(len(socks1))]
    q2 = [queues[len(socks1) + i] for i in range(len(socks2))]
    stop = threading.Event()
    writers = [threading.Thread(target=writer, args=(s, queues[i], stop), daemon=True)
               for i, s in enumerate(all_socks)]
    for w in writers:
        w.start()

    payload = b"\x00" * CHUNK
    seq = 0
    acc = 0.0                       # weighted-split accumulator
    rr_i = 0
    t0 = time.monotonic()
    interval = (CHUNK * 8 / (a.bitrate * 1e6)) if a.bitrate > 0 else 0.0
    next_send = t0

    def put(qlist, idx_holder):
        # round-robin within a path, work-steal to the other path if full
        for _ in range(len(qlist)):
            q = qlist[idx_holder[0] % len(qlist)]
            idx_holder[0] += 1
            try:
                q.put_nowait((seq, payload)); return True
            except queue.Full:
                continue
        return False

    i1, i2 = [0], [0]
    while time.monotonic() - t0 < a.dur and not stop.is_set():
        if a.sched == "rr":
            q = queues[rr_i % len(queues)]; rr_i += 1
            try: q.put((seq, payload), timeout=0.5)
            except queue.Full: pass
        else:
            acc += a.w
            to1 = acc >= 1.0
            if to1:
                acc -= 1.0
                ok = put(q1, i1) or (not a.strict and q2 and put(q2, i2))
            else:
                ok = (q2 and put(q2, i2)) or (not a.strict and put(q1, i1))
            if not ok:
                time.sleep(0.001)
                continue
        seq += 1
        if interval:
            next_send += interval
            d = next_send - time.monotonic()
            if d > 0:
                time.sleep(d)

    for q in queues:
        q.put(None)
    for w in writers:
        w.join(timeout=2)
    sys.stderr.write(f"sent {seq} chunks ({seq*CHUNK*8/1e6:.1f} Mbit offered)\n")


if __name__ == "__main__":
    main()
