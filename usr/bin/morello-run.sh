#!/bin/bash

# Copyright (c) 2020-2022 Arm Limited. All rights reserved.
#
# SPDX-License-Identifier: BSD-3-Clause

FS_OPTIONS=(
    "android-nano"
    "android-swr"
    "busybox"
    "debian"
    "distro"
)
ETHERNET_OPTIONS=(
    "smc91x"
    "virtio_net"
)
MAX_TIMEOUT=7200

set -u

# default values for optional argument
FILESYSTEM=""
TOP_DIR=$PWD
OUTPUT_DIR=${OUTPUT_DIR:-$TOP_DIR/run-scripts}
ENABLE_TRACING=0
NUM_CLUSTERS=2
NUM_CORES=2
MODEL=${MODEL:-$TOP_DIR/model/FVP_Morello/models/Linux64_GCC-6.4/FVP_Morello}
PLUGINS_DIR=${PLUGINS_DIR:-$TOP_DIR/model/FVP_Morello/plugins/Linux64_GCC-6.4}
AP_ROMFW=${AP_ROMFW:-$TOP_DIR/bsp/rom-binaries/bl1.bin}
FIP_BIN=${FIP_BIN:-$TOP_DIR/output/fvp/firmware/fip.bin}
SCP_ROMFW=${SCP_ROMFW:-$TOP_DIR/bsp/rom-binaries/scp_romfw.bin}
MCP_ROMFW=${MCP_ROMFW:-$TOP_DIR/bsp/rom-binaries/mcp_romfw.bin}
SCP_RAMFW=${SCP_RAMFW:-$TOP_DIR/output/fvp/firmware/scp_fw.bin}
MCP_RAMFW=${MCP_RAMFW:-$TOP_DIR/output/fvp/firmware/mcp_fw.bin}
INSTALLER_IMG=""
DISK_IMG=""
ETHERNET=""
SHARE_DIR=""
VIRTIO_FILE=""
readonly FS_OPTIONS_STR="$(IFS=/ ; echo "${FS_OPTIONS[*]}")"

function usage
{
        cat <<EOF
usage: $0 -f $FS_OPTIONS_STR [-t <network tap interface>] [-m <model bin path>]
       [-C <nb clusters>] [-c <cpus per cluster>] [-l] [-i <distribution installer path>]
       [-d <sata disk image path>] [-e <smc91x/virtio_net>] [-v <directory to be shared with FVP>]
       -- <fast model arguments>
optional arguments:
  -h, --help                    show this help message and exit
  -f, --fs-options              file system to start, one of $FS_OPTIONS_STR
  -j, --automate                [OPTIONAL] If in automation, no terminal/GUI are
                                visible to the user. It just does a boot test.
                                It auto verifies the console log,
                                stops the model and reports the results.
                                (default: False)
  -t, --tap-interface           [OPTIONAL] network tap interface name
  -c, --core                    [OPTIONAL] cpus per cluster
  -C, --cluster                 [OPTIONAL] number of clusters
  -m, --model                   FVP installed path
  -l, --trace-enable            [OPTIONAL] Enable tracing on demand by loading and configuring the
                                TarmacTrace and ToggleMTI plugins. Tracing is disabled at startup;
                                executing the instruction \`hlt 0x1\` (on any CPU) toggles tracing on/off.
                                The trace is written to the file <output dir>/trace.log.
  -i, --installer-image         [OPTIONAL] valid only for distribution installation.
  -d, --sata-disk               [OPTIONAL] valid only if sata disk is present.
  -e, --ethernet                [OPTIONAL] Selects the ethernet driver to use.(default: virtio_net)
  -v, --virtiop9-enable         [OPTIONAL] Enable directory sharing between host OS and FVP. This
                                flag takes the path to the host directory to be shared. The
                                directory to be shared must already be present in host OS.
EOF
        exit
}

DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

pushd $DIR/.. >/dev/null
TOP_DIR="$PWD"
popd >/dev/null

# kill the model's children, then kill the model
kill_model () {
        if test "${MODEL_PID:-}" = "" ; then
                return 0
        fi

        for SIG in INT TERM KILL ; do
                echo -e "\n[INFO] Killing SIG$SIG all children of PID: $MODEL_PID"
                MODEL_CHILDREN=$(pgrep -P $MODEL_PID || true)
                for CHILD in $MODEL_CHILDREN
                do
                        echo -e "\n[INFO] Killing $CHILD $(ps -e | grep $CHILD)"
                        kill -$SIG $CHILD > /dev/null 2>&1
                done

                kill -$SIG $MODEL_PID &> /dev/null
                for i in {10..1} ; do
                        echo "Waiting for model termination by SIG$SIG $i ..."
                        sleep 1
                        kill -0 $MODEL_PID 2>/dev/null || break 2
                done
        done
        wait $MODEL_PID || true
        echo -e "\n[INFO] All model processes killed successfully."
        unset MODEL_PID
}

# parse_log_file: waits until the search string is found in the log file
#                                 or timeout occurs
# Arguments: 1. log file name
#            2. search string
#            3. timeout
# Return Value: 0 -> Success
#              -1 -> Failure
parse_log_file ()
{
        local cnt=0
        local logfile=$1
        local search_str=$2
        local timeout=$3

        if [ "$timeout" -le 0 ] || [ "$timeout" -gt $MAX_TIMEOUT ]; then
                echo -e "\n[WARN] timeout value $timeout is invalid. Setting" \
                        "timeout to $MAX_TIMEOUT seconds."
                timeout=$MAX_TIMEOUT;
        fi

        while : ; do
                sleep 1
                if ls $logfile 1> /dev/null 2>&1; then
                        if tail $logfile | grep -e "$search_str" > /dev/null 2>&1 ; then
                                                        break
                                                fi
                fi
                if [ "$cnt" -ge "$timeout" ]; then
                        echo -e "\n[ERROR]: ${FUNCNAME[0]}: Timedout or $logfile may not found!\n"
                        return -1
                fi
                cnt=$((cnt+1))
        done
        return 0
}

while [[ $# -gt 0 ]]
do
        key="$1"
        case $key in
                -h|--help)
                        usage
                        ;;
                -f|--fs-options)
                        if [[ ! " ${FS_OPTIONS[@]} " =~ " $2 " ]]; then
                                echo "Unsupported filesystem $2"
                                echo "Use -f $FS_OPTIONS_STR"
                                exit -1
                        else
                                export FILESYSTEM="$2"
                                shift
                                shift
                        fi
                        ;;
                -m|--model)
                        MODEL="$2"
                        PLUGINS_DIR=$(dirname $MODEL)/../../plugins/Linux64_GCC-6.4
                        shift
                        shift
                        ;;
                -j|--automate)
                        AUTOMATE="true"
                        shift
                        ;;
                -t|--tap-interface)
                        NETWORK="true"
                        TAP_IFACE=$2
                        shift
                        shift
                        ;;
                -c|--core)
                        if ! [[ "$2" =~ [1-2] ]]; then
                               echo "Invalid number of cores per cluster, must be 1 or 2"
                               exit 1
                        fi
                        NUM_CORES="$2"
                        shift
                        shift
                        ;;
                -C|--cluster)
                        if ! [[ "$2" =~ [1-2] ]]; then
                               echo "Invalid number of cluster, must be 1 or 2"
                               exit 1
                        fi
                        NUM_CLUSTERS="$2"
                        shift
                        shift
                        ;;
                -l|--trace-enable)
                        ENABLE_TRACING=1
                        shift
                        ;;
                -i|--installer-image)
                        INSTALLER_IMG="$2"
                        shift
                        shift
                        ;;
                -d|--sata-disk)
                        DISK_IMG="$2"
                        shift
                        shift
                        ;;
                -e|--ethernet)
                        if [[ ! " ${ETHERNET_OPTIONS[@]} " =~ " $2 " ]]; then
                                echo "Unsupported ethernet $2"
                                echo "Use -e <smc91x/virtio_net>"
                                exit -1
                        else
                                export ETHERNET="$2"
                                shift
                                shift
                        fi
                        ;;
                -v|--virtiop9-enable)
                        SHARE_DIR="$2"
                        shift
                        shift
                        ;;
                --)
                        shift
                        fm_args=("${@:OPTIND}")
                        shift
                        shift
                        ;;
                *)
                        usage
                        ;;
        esac
done

if [ ! -f "$MODEL" ]; then
        echo "$MODEL was not found and the location of the model should be specified using -m"
        usage
fi

# absolutize the path
cd "$OUTPUT_DIR"
readonly OUTPUT_DIR="$PWD"
cd -

if [[ "$FILESYSTEM" == "" ]]; then
        echo "Filesystem parameter required!"
        usage
fi

if [[ "${NETWORK:-}" == "" ]]; then
        echo "No network option provided. Booting without network support!"
        NETWORK="false"
fi

if [[ "${AUTOMATE:-}" == "" ]]; then
        echo "No automate option provided. Keep the model executing!"
        AUTOMATE="false"
fi

case "$FILESYSTEM" in
("android-"*|"busybox"|"debian") VIRTIO_FILE="$TOP_DIR/output/fvp/$FILESYSTEM.img" ;;
esac

if [ ! -z "$INSTALLER_IMG" ]; then
       if [ "$FILESYSTEM" == "distro" ]; then
                VIRTIO_FILE=$INSTALLER_IMG
       else
                echo "ERROR: installer-image option is supported only for distro filesystem"
                exit
       fi
fi

# File checking...
if [ ! -f "$MODEL" ]; then
        echo "ERROR: Cannot find model binary in path <model bin path>"
        exit
fi

if [ ! -f "$AP_ROMFW" ]; then
        echo "ERROR: Cannot find tf-bl1.bin: $AP_ROMFW"
        exit
fi

if [ ! -f "$SCP_ROMFW" ]; then
        echo "ERROR: Cannot find scp_romfw.bin: $SCP_ROMFW"
        exit
fi

if [ ! -f "$MCP_ROMFW" ]; then
        echo "ERROR: Cannot find mcp_romfw.bin: $MCP_ROMFW"
        exit
fi

if [ ! -f "$SCP_RAMFW" ]; then
        echo "ERROR: Cannot find scp_fw.bin: $SCP_RAMFW"
        exit
fi

if [ ! -f "$MCP_RAMFW" ]; then
        echo "ERROR: Cannot find mcp_fw.bin: $MCP_RAMFW"
        exit
fi

if [ ! -f "$FIP_BIN" ]; then
        echo "ERROR: Cannot find fip.bin: $FIP_BIN"
        exit
fi

if [[ ! -z "$VIRTIO_FILE" && ! -f "$VIRTIO_FILE" ]]; then
        echo "ERROR: Cannot find virtio file"
        exit
fi

if [[ ! -z "$DISK_IMG" && ! -f "$DISK_IMG" ]]; then
        echo "ERROR: Cannot find sata disk image"
        exit
fi

if [[ -z "$DISK_IMG" && -z "$VIRTIO_FILE" ]]; then
        echo "ERROR: No virtio file or sata disk image specified"
        exit
fi

echo "Running FVP Base Model with these parameters:"
echo "MODEL=$MODEL"


if [[ "$NETWORK" == "true" ]]; then
        # if the user didn't supply a MAC address, generate one
        MACADDR=`echo -n 00:02:F7; dd bs=1 count=3 if=/dev/random 2>/dev/null |hexdump -v -e '/1 ":%02X"'`
        echo MACADDR=$MACADDR

        if [[ "$ETHERNET" == "smc91x" ]]; then
                net=(
                         -C "board.hostbridge.interfaceName=$TAP_IFACE"
                         -C "board.smsc_91c111.enabled=1"
                         -C "board.smsc_91c111.mac_address=${MACADDR}"
                )
         else
                net=(
                         -C "board.virtio_net.hostbridge.interfaceName=$TAP_IFACE"
                         -C "board.virtio_net.enabled=1"
                         -C "board.virtio_net.transport=legacy"
                         -C "board.virtio_net.mac_address=${MACADDR}"
                )
        fi

elif [[ "$NETWORK" == "false" ]]; then
        if [[ "$ETHERNET" == "smc91x" ]]; then
                net=(
                         -C "board.hostbridge.userNetworking=1"
                         -C "board.smsc_91c111.enabled=1"
                         -C "board.hostbridge.userNetPorts=5555=5555"
                 )
         else
                 net=(
                         -C "board.virtio_net.hostbridge.userNetworking=1"
                         -C "board.virtio_net.enabled=1"
                         -C "board.virtio_net.transport=legacy"
                         -C "board.virtio_net.hostbridge.userNetPorts=5555=5555"
                 )
         fi
fi

if [[ "$ENABLE_TRACING" -eq 1 ]]; then
        trace=(
                --plugin "$PLUGINS_DIR/TarmacTrace.so"
                -C "TRACE.TarmacTrace.trace_events=1"
                -C "TRACE.TarmacTrace.trace_instructions=1"
                -C "TRACE.TarmacTrace.trace_core_registers=1"
                -C "TRACE.TarmacTrace.trace_vfp=1"
                -C "TRACE.TarmacTrace.trace_mmu=0"
                -C "TRACE.TarmacTrace.trace_loads_stores=1"
                -C "TRACE.TarmacTrace.trace_cache=0"
                -C "TRACE.TarmacTrace.updated-registers=1"
                -C "TRACE.TarmacTrace.trace_capability_write_decode=1"
                -C "TRACE.TarmacTrace.trace-file=$OUTPUT_DIR/trace.log"

                # ToggleMTI must be loaded after TarmacTrace for
                # disable_mti_from_start=1 to be effective
                --plugin "$PLUGINS_DIR/ToggleMTIPlugin.so"
                -C "TRACE.ToggleMTIPlugin.hlt_imm16=0x1"
                -C "TRACE.ToggleMTIPlugin.disable_mti_from_start=1"
        )

        # Per-CPU ToggleMTI parameters
        for ((cluster=0; cluster < NUM_CLUSTERS; ++cluster)); do
                for ((cpu=0; cpu < NUM_CORES; ++cpu)); do
                        trace+=(
                                -C "css.cluster$cluster.cpu$cpu.enable_trace_special_hlt_imm16=1"
                                -C "css.cluster$cluster.cpu$cpu.trace_special_hlt_imm16=0x1"
                        )
                done
        done
fi

if [[ "$SHARE_DIR" != "" ]] ; then

        if [[ ! -d "$SHARE_DIR" ]]; then
                echo "[ERROR]: Directory path passed with -v/--virtiop9-enable flag invalid" \
                     "or does not exist."
                usage
                exit 1
        fi

        virtio_p9=(-C "board.virtio_p9.root_path=$SHARE_DIR")
fi

# Create log files with date stamps in the filename
# also create a softlink to these files with a static filename, eg, uart0.log
datestamp=`date +%s%N`
for i in {0..1} ; do
        log_basename="uart$i-$datestamp.log"
        log="$OUTPUT_DIR/$log_basename"
        touch "$log"
        log_link="$OUTPUT_DIR/uart$i.log"
        rm -f "$log_link"
        ln -s "$log_basename" "$log_link"
        readonly "UART${i}_LOG"="$log"
        echo "UART${i}_LOG=$log"
done

cmd=(
        "$MODEL"
        --data "Morello_Top.css.scp.armcortexm7ct=$SCP_ROMFW@0x0"
        --data "Morello_Top.css.mcp.armcortexm7ct=$MCP_ROMFW@0x0"
        -C "Morello_Top.soc.scp_qspi_loader.fname=$SCP_RAMFW"
        -C "Morello_Top.soc.mcp_qspi_loader.fname=$MCP_RAMFW"
        -C "css.scp.armcortexm7ct.INITVTOR=0x0"
        -C "css.mcp.armcortexm7ct.INITVTOR=0x0"
        -C "css.trustedBootROMloader.fname=$AP_ROMFW"
        -C "board.ap_qspi_loader.fname=$FIP_BIN"
        -C "board.virtioblockdevice.image_path=$VIRTIO_FILE"
        -C "css.pl011_uart_ap.out_file=$UART0_LOG"
        -C "css.scp.pl011_uart_scp.out_file=$OUTPUT_DIR/scp-$datestamp.log"
        -C "css.mcp.pl011_uart0_mcp.out_file=$OUTPUT_DIR/mcp-$datestamp.log"
        -C "css.pl011_uart_ap.unbuffered_output=1"
        -C "displayController=1"
        -C "board.virtio_rng.enabled=1"
        -C "board.virtio_rng.seed=0"
        -C "num_clusters=$NUM_CLUSTERS"
        -C "num_cores=$NUM_CORES"
        ${net[@]+"${net[@]}"}
        ${trace[@]+"${trace[@]}"}
        ${virtio_p9[@]+"${virtio_p9[@]}"}
)

[[ ! -v DISPLAY || "$AUTOMATE" == "true" ]] && cmd+=(
        -C "disable_visualisation=true"
        -C "board.terminal_uart0_board.start_telnet=0"
        -C "board.terminal_uart1_board.start_telnet=0"
        -C "css.mcp.terminal_uart0.start_telnet=0"
        -C "css.mcp.terminal_uart1.start_telnet=0"
        -C "css.scp.terminal_uart_aon.start_telnet=0"
        -C "css.terminal_sec_uart_ap.start_telnet=0"
        -C "css.terminal_uart1_ap.start_telnet=0"
        -C "css.terminal_uart_ap.start_telnet=0"
)

[[ -f $DISK_IMG ]] && cmd+=(
        -C "pci.pcie_rc.ahci1.ahci.image_path=$DISK_IMG"
)

cmd+=("${fm_args[@]}")

if [[ "$AUTOMATE" != "true" ]]; then
        if [[ -v DISPLAY ]]; then
                echo "Executing Model Command:"
                echo "  ${cmd[*]}"
                exec "${cmd[@]}"
                # exec failed
                exit 1
        else
                tmp="$(mktemp -d)"
                trap "rm -rf $tmp" EXIT
                mkfifo $tmp/port

                cmd+=(
                        -C "css.terminal_uart_ap.start_telnet=1"
                        -C "css.terminal_uart_ap.terminal_command=echo %port > $tmp/port"
                )

                echo "Executing Model Command:"
                echo "  ${cmd[*]}"
                "${cmd[@]}" &
                read port < $tmp/port
                telnet localhost $port
                kill -INT %%
                wait
                exit
        fi
fi

set -e

SIGHDL_exit() {
        local code=$?
        kill_model
        ! test "${WORKDIR:-}" != "" || rm -rf "$WORKDIR"
        if test -v UART_PID ; then
                kill ${UART_PID:-0}  &>/dev/null
        fi

        if [ "$SUCCESS" = "0" ] ; then
                echo "[ERROR]: Boot test failed or timedout!"
                exit 1
        fi
        echo "[SUCCESS]: Boot test completed!"
        exit 0
}

SUCCESS=0
trap SIGHDL_exit EXIT TERM

echo "Executing Model Command:"
echo "  ${cmd[*]}"

"${cmd[@]}" &
if [ "$?" != "0" ] ; then
        echo "Failed to launch the model"
        exit 1
fi

echo "Model launched with pid: "$!
export MODEL_PID=$!

# wait for boot to complete and the model to be killed
case "$FILESYSTEM" in
("busybox")
        parse_log_file "$UART0_LOG" "/ #" 7200
        ;;
("android-nano")
        parse_log_file "$UART0_LOG" "console:/" 7200
        ;;
(*)
    echo "ERROR: Automation not supported on $FILESYSTEM" >&2
    exit 1
esac

echo "Console ready detected"
SUCCESS=1