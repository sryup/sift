#!/bin/sh
set -eu
LC_ALL=C
export LC_ALL

project_dir=$(CDPATH='' cd -P "$(dirname "$0")/.." && pwd)
test_dir=$(mktemp -d /tmp/sift-temperature.XXXXXX)
cleanup() {
    # Only remove the absolute, task-specific directory created by mktemp.
    case "$test_dir" in
        /tmp/sift-temperature.??????) rm -rf -- "$test_dir" ;;
    esac
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

# Load the real functions without running the snapshot or adding a public
# environment variable/CLI flag that changes production sensor paths.
awk '
    /^# Parse and validate all CLI arguments$/ { found = 1; exit }
    { print }
    END { if (!found) exit 1 }
' "$project_dir/sift" > "$test_dir/functions.sh"
# shellcheck source=/dev/null
. "$test_dir/functions.sh"

cases=0
passed=0
new_case() {
    cases=$((cases + 1))
    case_dir="$test_dir/case$cases"
    mkdir "$case_dir"
}
attr() {
    mkdir -p "$case_dir/${1%/*}"
    printf '%s\n' "$2" > "$case_dir/$1"
}
expect() {
    actual=$(get_temperature "$case_dir" 2> "$case_dir/stderr") || {
        printf 'FAIL: %s (nonzero exit)\n' "$2" >&2
        exit 1
    }
    if [ "$actual" != "$1" ] || [ -s "$case_dir/stderr" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$2" "$1" "$actual" >&2
        cat "$case_dir/stderr" >&2
        exit 1
    fi
    passed=$((passed + 1))
    printf 'ok %s - %s\n' "$passed" "$2"
}

new_case
expect 'N/A' 'no sensor directories'

new_case
attr hwmon/hwmon0/name coretemp
attr hwmon/hwmon0/temp1_label 'Package id 0'
attr hwmon/hwmon0/temp1_input 62500
attr hwmon/hwmon1/name amdgpu
attr hwmon/hwmon1/temp1_label edge
attr hwmon/hwmon1/temp1_input 70000
attr thermal/thermal_zone0/type x86_pkg_temp
attr thermal/thermal_zone0/temp 65000
expect '70.0 °C (max: amdgpu / edge)' 'highest device wins, not necessarily CPU'

new_case
attr hwmon/hwmon0/name coretemp
attr hwmon/hwmon0/temp1_label 'Package id 0'
attr hwmon/hwmon0/temp1_input 62500
attr hwmon/hwmon0/temp1_fault 0
attr hwmon/hwmon0/temp1_enable 1
attr hwmon/hwmon0/temp2_input 125000
attr hwmon/hwmon0/temp2_fault 1
attr hwmon/hwmon0/temp3_input 140000
attr hwmon/hwmon0/temp3_enable 0
expect '62.5 °C (max: coretemp / Package id 0)' 'skip hottest faulty and disabled channels'

for flag_case in fault:1 enable:0 fault:2 enable:2 fault:broken enable:broken fault: enable:; do
    new_case
    attr hwmon/hwmon0/temp1_input 62500
    attr "hwmon/hwmon0/temp1_${flag_case%%:*}" "${flag_case#*:}"
    expect 'N/A' "reject unusable status $flag_case"
done

new_case
attr hwmon/hwmon0/temp1_input 47500
expect '47.5 °C (max: hwmon0 / temp1)' 'missing metadata uses identifiers'

new_case
attr hwmon/hwmon0/name ''
attr hwmon/hwmon0/temp1_label ''
attr hwmon/hwmon0/temp1_input 47500
expect '47.5 °C (max: hwmon0 / temp1)' 'empty metadata uses identifiers'

new_case
attr thermal/thermal_zone2/type acpitz
attr thermal/thermal_zone2/mode disabled
attr thermal/thermal_zone2/temp 48000
expect '48.0 °C (max: acpitz / thermal_zone2)' 'thermal mode is not a sensor enable flag'

new_case
attr thermal/thermal_zone3/temp 48000
expect '48.0 °C (max: thermal_zone3)' 'missing thermal type uses zone identifier'

new_case
attr hwmon/hwmon0/temp1_input 0
expect '0.0 °C (max: hwmon0 / temp1)' 'zero is a valid reading'

new_case
attr hwmon/hwmon0/temp1_input -12500
attr thermal/thermal_zone0/temp -5500
expect '-5.5 °C (max: thermal_zone0)' 'all-negative inputs still select the maximum'

new_case
attr hwmon/hwmon0/temp1_input 125000
attr hwmon/hwmon0/temp1_crit 100000
attr hwmon/hwmon0/temp1_crit_alarm 1
expect '125.0 °C (max: hwmon0 / temp1)' 'a high reading or alarm is not a sensor fault'

for invalid in '' broken NaN +62500 62.5 --62500 '62500 2' -273151 300001 99999999999999999999999999; do
    new_case
    attr hwmon/hwmon0/temp1_input "$invalid"
    expect 'N/A' "reject invalid/out-of-range input [$invalid]"
done

new_case
attr hwmon/hwmon0/temp1_input "$(printf '62500\tgarbage')"
expect 'N/A' 'a tab in the value cannot become a source delimiter'

new_case
attr hwmon/hwmon0/temp1_input 00062567
expect '62.6 °C (max: hwmon0 / temp1)' 'leading zeros are decimal and output rounds to one place'

new_case
attr hwmon/hwmon0/temp1_input 62500
printf '62500' > "$case_dir/hwmon/hwmon0/temp1_input"
expect '62.5 °C (max: hwmon0 / temp1)' 'final newline is optional'

new_case
attr hwmon/hwmon0/name coretemp
attr hwmon/hwmon0/temp1_label 'Package id 0'
attr hwmon/hwmon0/temp1_input 62500
attr thermal/thermal_zone0/type x86_pkg_temp
attr thermal/thermal_zone0/temp 62500
expect '62.5 °C (max: coretemp / Package id 0)' 'equal values prefer the hwmon source'

new_case
attr hwmon/hwmon0/temp1_input 10000
attr hwmon/hwmon0/temp2_input 9000
expect '10.0 °C (max: hwmon0 / temp1)' 'maximum comparison is numeric, not lexical'

new_case
attr hwmon/hwmon0/name vt1211
attr hwmon/hwmon0/temp1_input 150000
attr hwmon/hwmon0/temp2_input 42000
attr hwmon/hwmon0/temp3_input 220000
expect '42.0 °C (max: vt1211 / temp2)' 'VT1211 external channels require unsupported calibration'

new_case
attr hwmon/hwmon0/name nct6775
attr hwmon/hwmon0/temp1_type 4
attr hwmon/hwmon0/temp1_input 48000
expect '48.0 °C (max: nct6775 / temp1)' 'thermistor type alone does not imply raw voltage'

new_case
attr hwmon/hwmon0/name coretemp
attr hwmon/hwmon0/temp1_label 'Package\n %s'
attr hwmon/hwmon0/temp1_input 62500
expect '62.5 °C (max: coretemp / Package\n %s)' 'metadata is literal text, not an escape or format string'

new_case
attr hwmon/hwmon0/temp1_label "$(printf 'Core\t0\033[31m')"
attr hwmon/hwmon0/temp1_input 62500
expect '62.5 °C (max: hwmon0 / Core?0?[31m)' 'control characters cannot change terminal formatting'

new_case
attr devices/cpu/name coretemp
attr devices/cpu/temp1_input 62500
mkdir "$case_dir/hwmon"
ln -s ../devices/cpu "$case_dir/hwmon/hwmon0"
expect '62.5 °C (max: coretemp / temp1)' 'sysfs class symlinks are followed'

new_case
attr hwmon/hwmon0/temp2_input 40000
ln -s missing "$case_dir/hwmon/hwmon0/temp1_input"
expect '40.0 °C (max: hwmon0 / temp2)' 'missing sensor does not hide remaining readings'

new_case
attr hwmon/hwmon0/temp1_input 62500
ln -s missing "$case_dir/hwmon/hwmon0/temp1_fault"
expect 'N/A' 'present but unreadable status is not treated as an absent flag'

if [ "$(id -u)" -ne 0 ]; then
    new_case
    attr hwmon/hwmon0/temp1_input 90000
    attr hwmon/hwmon0/temp2_input 40000
    chmod 000 "$case_dir/hwmon/hwmon0/temp1_input"
    expect '40.0 °C (max: hwmon0 / temp2)' 'permission-denied input is skipped quietly'

    new_case
    attr hwmon/hwmon0/temp1_input 90000
    attr hwmon/hwmon0/temp1_fault 0
    chmod 000 "$case_dir/hwmon/hwmon0/temp1_fault"
    expect 'N/A' 'permission-denied status makes a channel unusable'
else
    printf '# skipped permission tests: running as root\n'
fi

printf 'Passed %s temperature tests.\n' "$passed"
