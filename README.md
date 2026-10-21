# Sift

A lightweight, portable Linux system information tool written in POSIX-compliant shell (`/bin/sh`).

Sift provides an instantaneous, read-only snapshot of essential system metrics without background services, heavy runtimes, or root privileges. It is designed specifically for Linux systems, focusing on minimalism, readability, and predictable behavior.

## Features

- **Tree-Structured Snapshot:** Gathers essential system details into an elegant, hierarchical tree structure (Host/OS header, followed by kernel, uptime, cpu, load, memory, temperature, and disk).
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
├─ temp    47.5 °C (max: k10temp / Tctl)
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
- `/sys/class/thermal` and `/sys/class/hwmon` (for the highest accepted hardware temperature and its source)

### Temperature Output (v0.2.1)

`temp` shows the highest accepted reading across available sensors, followed by its source; it is not necessarily the CPU temperature or an overall system temperature. Hwmon sources use the device `name` and `temp*_label`, falling back to identifiers such as `hwmon0 / temp1`. Thermal sources use `type` and the zone identifier, such as `x86_pkg_temp / thermal_zone0`. Equal readings keep the first source found, with hwmon checked before thermal zones.

Sift skips hwmon channels with `temp*_fault=1` or `temp*_enable=0`. Missing status attributes are optional; present attributes that cannot be read or contain unexpected values cause that channel to be skipped. Thermal-zone `mode=disabled` is not used to reject readings because it controls kernel thermal management. Temperature alarms do not invalidate a reading.

Input must be a signed or unsigned integer in millidegrees Celsius within the sanity range -273.15 to 300 °C, then is displayed to one decimal place. Zero, negative readings, and readings such as 125 °C are not automatically errors. These checks cannot detect every faulty or miscalibrated sensor. With no accepted readings, Sift displays `N/A`.

Attribute semantics follow the Linux kernel documentation for [hwmon](https://docs.kernel.org/hwmon/sysfs-interface.html) and [thermal zones](https://docs.kernel.org/driver-api/thermal/sysfs-api.html).

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
- **Temperature Sensors:** VM/container readings depend on which host sensors are exposed; no usable sensors means `N/A`. Sift assumes standard millidegree-Celsius readings and does not apply `sensors.conf` calibration or voltage-to-temperature conversion. Known [VT1211 external channels](https://docs.kernel.org/hwmon/vt1211.html#temperature-monitoring), which require board-specific scaling, are skipped; its internal `temp2` remains supported. Other non-standard drivers may need separate conversion support.
- **High-Latency Remote Mounts:** If the root filesystem (`/`) is mounted over a network share (such as NFS or CIFS), execution time may be affected by network latency when querying `df`.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
