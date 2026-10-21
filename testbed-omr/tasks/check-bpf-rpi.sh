echo "== kernel"; uname -a
echo "== scheduler tersedia"; sysctl -n net.mptcp.available_schedulers
echo "== BTF kernel"; ls -l /sys/kernel/btf/vmlinux 2>&1
echo "== bpffs"; mount | grep -i bpf
echo "== bpftool"; which bpftool; bpftool version 2>&1 | head -2
echo "== struct_ops terpasang"; bpftool struct_ops list 2>&1 | head -20
echo "== paket bpf di repo"; apk search bpftool libbpf 2>/dev/null | head
echo "== asal scheduler bpf_* (file .o / script)"
find / -xdev \( -name '*mptcp*.o' -o -name '*sched*.bpf.o' -o -name 'mptcp_bpf*' \) 2>/dev/null | head -20
grep -rls "struct_ops\|bpf_rr\|bpf_burst" /etc /usr/lib /usr/share /lib 2>/dev/null | head -20
echo "== kernel config"
zcat /proc/config.gz 2>/dev/null | grep -E "CONFIG_(DEBUG_INFO_BTF|BPF_JIT|BPF_SYSCALL|MPTCP|BPF_JIT_ALWAYS_ON)=" 
echo "== modul"; lsmod 2>/dev/null | grep -i -E "mptcp|bpf" | head
