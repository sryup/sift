# Sift

A lightweight, portable Linux system information tool written in POSIX-compliant shell (`/bin/sh`).

Sift provides an instantaneous, read-only snapshot of essential system metrics without background services, heavy runtimes, or root privileges. It is designed specifically for Linux systems, focusing on minimalism, readability, and predictable behavior.

## Features

- **Tree-Structured Snapshot:** Gathers essential system details into an elegant, hierarchical tree structure (Host/OS header, followed by kernel, uptime, cpu, load, memory, and disk).
- **Minimal Dependencies:** Implemented as a single-file POSIX shell script relying only on standard utilities.
- **Smart Terminal Colors:** Automatically detects interactive terminal capabilities with bold green accents and dim tree branches, while safely disabling colors for non-TTY pipelines, `--no-color`, `NO_COLOR`, and `TERM=dumb`.
- **Compact Smart Uptime:** Formats system uptime cleanly (`Xd Xh Xm`, `Xh Xm`, `Xm`, or `0m`).
- **Graceful Degradation:** Falls back to secondary sources or `N/A` when supported system data is unavailable or fails to parse properly.
- **Unprivileged Execution:** Requires no root or `sudo` privileges to inspect system metrics.

## Sample Output

> [!NOTE]
> The following output is a generic example. Actual values will reflect your target system.

```text
server (Debian GNU/Linux 13 (trixie) x86_64)
├─ kernel  6.8.0-generic
├─ uptime  14d 6h 23m
├─ cpu     AMD Ryzen 7 7800X3D (16)
├─ load    0.15, 0.08, 0.02
├─ memory  4.2 GiB / 31.2 GiB (13%)
└─ disk    45.8 GiB / 468.2 GiB (10%)
```

## Requirements & Data Sources

Sift is intended solely for Linux operating systems. It does not require external package managers, libraries, or programming runtimes.

### Required Commands
- A POSIX-compliant shell (`/bin/sh` such as Dash, Bash, BusyBox ash, or Ksh)
- Standard POSIX utilities: `awk`, `df`, `uname`

### Linux Data Sources
- `/etc/os-release` (for distribution identity)
- `/proc/uptime` (for system uptime)
- `/proc/cpuinfo` (for CPU model name and logical processor count)
- `/proc/loadavg` (for 1, 5, and 15-minute load averages)
- `/proc/meminfo` (for `MemTotal` and `MemAvailable`)
- `/proc/sys/kernel/hostname` (for system hostname)

## Installation & Usage

### Running Directly (Recommended)

You can clone or download the repository and run Sift directly without installation:

```sh
git clone https://github.com/sryup/sift.git
cd sift
chmod +x sift
./sift
```

### System-Wide Installation

To make Sift accessible globally from any directory, install it into `/usr/local/bin`:

```sh
sudo install -m 755 sift /usr/local/bin/sift
```

> [!NOTE]
> Elevated privileges (`sudo`) are only required to copy the script into system binary paths during installation. Sift itself never requires `sudo` or root privileges to run.

To uninstall:
```sh
sudo rm /usr/local/bin/sift
```

## Command-Line Options

| Option | Description |
|---|---|
| `-h, --help` | Display help message and exit |
| `-v, --version` | Display version information and exit |
| `--no-color` | Disable ANSI color formatting |

## Exit Codes

| Exit Code | Meaning | Description |
|:---:|---|---|
| `0` | Success | Normal operation or partial data failure with safe `N/A` fallback |
| `1` | Fatal Runtime Error | Unsupported non-Linux operating system or unexpected runtime failure |
| `2` | Invalid Arguments | Unrecognized option or invalid command-line syntax |

## Known Limitations

- **Container CPU Metrics:** CPU core count is derived from `/proc/cpuinfo`. In container environments without virtualization layers (such as `lxcfs`), this count may reflect the host system's logical processors rather than container-specific cgroup CPU quotas or limits.
- **Non-Standard Architectures:** Linux distributions on certain architectures (e.g., IBM s390x) format `/proc/cpuinfo` with different field keys. On such systems, Sift displays `(N/A)` for processor count rather than failing. Sift has not been validated on every niche Linux distribution or hardware architecture.
- **High-Latency Remote Mounts:** If the root filesystem (`/`) is mounted over a network share (such as NFS or CIFS), execution time may be affected by network latency when querying `df`.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
