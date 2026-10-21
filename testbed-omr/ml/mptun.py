#!/usr/bin/env python3
"""
Bidirectional multipath TCP tunnel for ONE connection, over N sub-streams each
pinned to a SIM. It carries the camera's RTSP-over-TCP connection so the live
video is aggregated across both SIMs (Jetson-controlled split) instead of riding
the single glorytun tunnel -- and the dashboard's per-SIM counters then reflect
it. No ffmpeg / extra deps: the tunnel just relays bytes, it does not parse RTSP.

Topology (SIMs are behind CGNAT, so the RPi always initiates outbound):
  RPi  --role rpi--  opens N sub-streams to the VPS (source-bound per WAN) and,
                     on demand, a socket to the camera; relays camera<->substreams.
  VPS  --role vps--  accepts the N sub-streams and listens locally for MediaMTX;
                     relays MediaMTX<->substreams.

Heavy direction (camera -> VPS, the video) is split across all sub-streams by
weight w and reassembled in order on the VPS. Light direction (MediaMTX -> camera,
RTSP control) rides sub-stream 0. w is read live from --ctl (the Jetson writes it).

Frames per sub-stream:  U = uplink data [b'U'][seq u64][len u32][payload]
                        D = downlink data [b'D'][len u32][payload]   (sub 0 only)
                        C = control  [b'C'][1 byte: 1=START 0=STOP]  (sub 0 only)

Run:
  VPS:  mptun.py --role vps --sub-port 5401 --local-port 5402 --conns 8
  RPi:  mptun.py --role rpi --vps <ip> --sub-port 5401 --n1 4 --n2 4 \
                 --cam 192.168.100.20:554 --ctl /tmp/mptun_w
"""
import argparse, socket, struct, sys, threading, time

U = struct.Struct("!QI")   # uplink seq, len
LD = struct.Struct("!I")   # downlink/len
WAN1_IP, WAN2_IP = "192.168.1.100", "192.168.2.100"
CHUNK = 8192


def recvn(sock, n):
    buf = bytearray()
    while len(buf) < n:
        b = sock.recv(n - len(buf))
        if not b:
            return None
        buf += b
    return bytes(buf)


# ---------------- VPS side ----------------
def run_vps(a):
    srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", a.sub_port)); srv.listen(a.conns + 4)
    lsrv = socket.socket(); lsrv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    lsrv.bind(("127.0.0.1", a.local_port)); lsrv.listen(4)
    sys.stderr.write(f"[vps] sub-port {a.sub_port}, local {a.local_port}\n"); sys.stderr.flush()
    while True:
        # a fresh set of sub-streams per session (RPi reconnects each time)
        subs = []
        for _ in range(a.conns):
            c, _ = srv.accept(); c.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            idx = c.recv(1)[0]; subs.append((idx, c))
        subs.sort(key=lambda t: t[0]); socks = [c for _, c in subs]; sub0 = socks[0]
        sys.stderr.write("[vps] sub-streams up; waiting for MediaMTX\n"); sys.stderr.flush()
        mm, _ = lsrv.accept(); mm.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        sys.stderr.write("[vps] MediaMTX connected\n"); sys.stderr.flush()
        try:
            _session_vps(mm, socks, sub0)
        except Exception:
            pass
        for s in socks:
            try: s.close()
            except Exception: pass
        sys.stderr.write("[vps] session ended\n"); sys.stderr.flush()


def _session_vps(mm, socks, sub0):
    state = {"run": True, "next": 0, "buf": {}}
    lock = threading.Lock()
    mm.settimeout(1.0)
    sub0.sendall(b"C" + bytes([1]))                      # START

    def end():
        state["run"] = False
        try: mm.shutdown(socket.SHUT_RDWR)               # unblock the downlink recv
        except Exception: pass

    def sub_reader(s):                                    # uplink: cam -> MediaMTX
        try:
            while state["run"]:
                tag = recvn(s, 1)
                if not tag:
                    break
                if tag == b"U":
                    h = recvn(s, U.size); seq, ln = U.unpack(h); data = recvn(s, ln)
                    if data is None:
                        break
                    with lock:
                        state["buf"][seq] = data
                        while state["next"] in state["buf"]:
                            mm.sendall(state["buf"].pop(state["next"])); state["next"] += 1
        except Exception:
            pass
        finally:
            end()

    readers = [threading.Thread(target=sub_reader, args=(s,), daemon=True) for s in socks]
    for t in readers:
        t.start()
    try:                                                 # downlink: MediaMTX -> cam (sub0)
        while state["run"]:
            try:
                d = mm.recv(CHUNK)
            except socket.timeout:
                continue
            if not d:
                break
            sub0.sendall(b"D" + LD.pack(len(d)) + d)
    except Exception:
        pass
    finally:
        state["run"] = False
        try: sub0.sendall(b"C" + bytes([0]));
        except Exception: pass
        try: mm.close()
        except Exception: pass


# ---------------- RPi side ----------------
def run_rpi(a):
    cam_host, cam_port = a.cam.split(":"); cam_port = int(cam_port)

    def read_w():
        try:
            return min(1.0, max(0.0, float(open(a.ctl).read().strip())))
        except Exception:
            return a.w

    while True:                                          # fresh sub-streams per session
        binds = [WAN1_IP] * a.n1 + [WAN2_IP] * a.n2
        socks = []
        try:
            for i, src in enumerate(binds):
                s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                s.bind((src, 0)); s.connect((a.vps, a.sub_port))
                s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1); s.sendall(bytes([i]))
                socks.append(s)
        except Exception:
            for s in socks:
                try: s.close()
                except Exception: pass
            time.sleep(2); continue
        sub0 = socks[0]
        sys.stderr.write(f"[rpi] {len(socks)} sub-streams up to {a.vps}:{a.sub_port}; waiting START\n"); sys.stderr.flush()
        tag = recvn(sub0, 1)
        if tag == b"C" and recvn(sub0, 1)[0] == 1:
            cam = socket.socket(); cam.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            try:
                cam.connect((cam_host, cam_port))
                sys.stderr.write("[rpi] camera connected; relaying\n"); sys.stderr.flush()
                _session_rpi(cam, socks, sub0, a.n1, read_w)
            except Exception:
                sys.stderr.write("[rpi] camera connect/relay failed\n"); sys.stderr.flush()
            try: cam.close()
            except Exception: pass
        for s in socks:
            try: s.close()
            except Exception: pass


def _session_rpi(cam, socks, sub0, n1, read_w):
    state = {"run": True}
    cam.settimeout(1.0)

    def end():
        state["run"] = False
        try: cam.shutdown(socket.SHUT_RDWR)              # unblock the uplink recv
        except Exception: pass

    def downlink_reader():                               # sub0: control + MediaMTX->cam
        try:
            while state["run"]:
                tag = recvn(sub0, 1)
                if not tag:
                    break
                if tag == b"D":
                    ln = LD.unpack(recvn(sub0, LD.size))[0]; data = recvn(sub0, ln)
                    if data is None:
                        break
                    cam.sendall(data)
                elif tag == b"C":
                    if recvn(sub0, 1)[0] == 0:
                        break                            # STOP
        except Exception:
            pass
        finally:
            end()

    threading.Thread(target=downlink_reader, daemon=True).start()
    seq = 0; acc = 0.0; i1 = 0; i2 = 0
    try:                                                 # uplink: cam -> subs (split by w)
        while state["run"]:
            try:
                d = cam.recv(CHUNK)
            except socket.timeout:
                continue
            if not d:
                break
            w = read_w(); acc += w
            if acc >= 1.0 and n1 > 0:
                acc -= 1.0; s = socks[i1 % n1]; i1 += 1
            elif len(socks) > n1:
                s = socks[n1 + (i2 % (len(socks) - n1))]; i2 += 1
            else:
                s = socks[i1 % n1]; i1 += 1
            s.sendall(b"U" + U.pack(seq, len(d)) + d); seq += 1
    except Exception:
        pass
    finally:
        end()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--role", choices=["rpi", "vps"], required=True)
    ap.add_argument("--vps", default="168.144.105.155")
    ap.add_argument("--sub-port", type=int, default=5401)
    ap.add_argument("--local-port", type=int, default=5402)
    ap.add_argument("--conns", type=int, default=8)
    ap.add_argument("--n1", type=int, default=4)
    ap.add_argument("--n2", type=int, default=4)
    ap.add_argument("--cam", default="192.168.100.20:554")
    ap.add_argument("--w", type=float, default=0.5)
    ap.add_argument("--ctl", default="/tmp/mptun_w")
    a = ap.parse_args()
    (run_vps if a.role == "vps" else run_rpi)(a)


if __name__ == "__main__":
    main()
