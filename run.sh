#!/usr/bin/env bash

N_TEST_CASES=30

FILENAME=""
PROJECT_PATH=$PWD
CERTS="$PROJECT_PATH/certs/"
WWW="$PROJECT_PATH/www"
DOWNLOADS="$PROJECT_PATH/downloads"
RESULTS_DIR="$PROJECT_PATH/results"
LOG_PATH="$PROJECT_PATH/logs_$(date +"%d_%m_%Y_%H:%M:%S")"
WAITFORSERVER=server:443

setup_tests(){

    sudo modprobe -a udp_tunnel ip6_udp_tunnel || return 1

    if [ -f ../quic/modules/net/quic/quic.ko ]; then
		[ -d /sys/module/quic ] || sudo insmod ../quic/modules/net/quic/quic.ko || return 1
	else
		sudo modprobe quic || return 1
	fi

	pushd "$PROJECT_PATH/certs/" > /dev/null
	if [ -f ./ca.pem -a -f ./cert.pem -a -f ./priv.key ]; then
	    echo "Keys & Certificates already exist"
	else 
    	echo "Creating Keys & Certificates"
		bash ./certs.sh ./ 1
	fi
	popd > /dev/null

	if [ ! -d $WWW ]; then
	    mkdir $WWW
	fi

	if [ ! -d $DOWNLOADS ]; then
	    mkdir $DOWNLOADS
	fi

	if [ ! -d $LOG_PATH ]; then
	    mkdir $LOG_PATH
	fi

	# generate random file of 10MB if there's any on www/ directory
	if [ -z "$( ls -A "$PROJECT_PATH/www/")" ]; then
		FILENAME=$(openssl rand -hex 5)
	    dd if=/dev/urandom of="$PROJECT_PATH/www/$FILENAME" bs=1 count=$(expr 10 \* 1024 \* 1024)
	else
		FILES=("$PROJECT_PATH/www/*")
		FILENAME=$(basename ${FILES[0]})
	fi

	# remove file from downloads
	if [ -f "$DOWNLOADS/$FILENAME" ]; then
	    sudo rm "$DOWNLOADS/$FILENAME"
	fi
}

save_env_on_file(){
	printf '%s="%s"\n' \
		"CERTS" "$CERTS" \
		"WWW" "$WWW" \
		"DOWNLOADS" "$DOWNLOADS" \
		"CRON" "$CRON" \
		"IPERF_CONGESTION" "$IPERF_CONGESTION" \
		"SSLKEYLOGFILE" "$SSLKEYLOGFILE" \
		"QLOGDIR" "$QLOGDIR" \
		"REQUESTS" "$REQUESTS" \
		"SCENARIO" "$SCENARIO" \
		"TESTCASE_CLIENT" "$TESTCASE_CLIENT" \
		"TESTCASE_SERVER" "$TESTCASE_SERVER" \
		"CLIENT" "$CLIENT" \
		"SERVER" "$SERVER" \
		"CLIENT_PARAMS" "$CLIENT_PARAMS" \
		"SERVER_PARAMS" "$SERVER_PARAMS" \
		"SERVER_LOGS" "$SERVER_LOGS" \
		"CLIENT_LOGS" "$CLIENT_LOGS" \
		"WAITFORSERVER" "$WAITFORSERVER" > $1
}

run_docker_compose(){
    TEST_TYPE="transfer"
	SCENARIO=$6

    TESTCASE_SERVER=$TEST_TYPE
    TESTCASE_CLIENT=$TEST_TYPE

    TEST_LOG_PATH=$1
    TEST_SIM_LOGS="$TEST_LOG_PATH/sim"
    TEST_SERVER_LOGS="$TEST_LOG_PATH/server"
    TEST_CLIENT_LOGS="$TEST_LOG_PATH/client"

    CLIENT=$2
    SERVER=$3
    REQUESTS="https://server4:443/$FILENAME"

	mkdir -p $TEST_SIM_LOGS $TEST_SERVER_LOGS $TEST_CLIENT_LOGS 

	save_env_on_file ./empty.env
	
	sudo bpftrace "syscalls.bt" "$4" "$5" > $TEST_LOG_PATH/bpftrace.txt &
	BPFTRACE_PID=$!
	sudo echo "" 
	docker-compose --env-file empty.env up --abort-on-container-exit --timeout 1 sim client server > $TEST_LOG_PATH/output.txt 2>&1
	kill -2 $BPFTRACE_PID

	# copy the pcaps and logs from: sim client server
	docker cp "$(docker ps -a --format '{{.ID}} {{.Names}}' | awk '/^.* sim$/ {print $1}'):/logs/." "$TEST_SIM_LOGS" > $TEST_LOG_PATH/output.txt 2>&1
    docker cp "$(docker ps -a --format '{{.ID}} {{.Names}}' | awk '/^.* client$/ {print $1}'):/logs/keys.log" "$TEST_SERVER_LOGS/keys.log" > $TEST_LOG_PATH/output.txt 2>&1
    docker cp "$(docker ps -a --format '{{.ID}} {{.Names}}' | awk '/^.* server$/ {print $1}'):/logs/keys.log" "$TEST_CLIENT_LOGS/keys.log" > $TEST_LOG_PATH/output.txt 2>&1

	# checking if files are equal
	if cmp --silent -- "$WWW/$FILENAME" "$DOWNLOADS/$FILENAME"; then
		echo "[SUCCESS] $TEST_TYPE"
	else
		echo "[FAILED]  $TEST_TYPE"
	fi

    # clean necessary files for the next test
	if [ -f "$DOWNLOADS/$FILENAME" ]; then
	    sudo rm -f "$DOWNLOADS/$FILENAME"
	fi
}

get_metrics(){
	# echo "Checking test..."
	TEST_LOG_PATH=$1
	INTEROP_IP4_SERVER="193.167.100.100"
	INTEROP_IP6_SERVER="fd00:cafe:cafe:100::100"
	TSHARK_FILTER="(quic) &&  (ip.src==$INTEROP_IP4_SERVER || ipv6.src==$INTEROP_IP6_SERVER) && quic.header_form==0" 
	TRACE_NODE_LEFT_PCAP_FILE="$TEST_LOG_PATH/sim/trace_node_left.pcap"
	CLIENT_KEY_LOG_FILES="$TEST_LOG_PATH/client/keys.log"

	
    # Filtering packets and moving goodput to file
	tshark -T json -e frame.time_epoch -r "$TRACE_NODE_LEFT_PCAP_FILE" -Y "$TSHARK_FILTER" -o tls.keylog_file:"$CLIENT_KEY_LOG_FILES" --disable-protocol http3 -d udp.port==443,quic \
	| jq -r '[ .[]._source.layers."frame.time_epoch".[0] ] | (.[-1]|tonumber) - (.[0]|tonumber)' >> $2

    # moving syscalls to file
    awk 'BEGIN {total_syscalls=0;} match($0, /^@[^\[]+\[[^\]]+\]: ?([0-9]+)$/, a) { total_syscalls += a[1] } END { print total_syscalls;}' "$TEST_LOG_PATH/bpftrace.txt" >> $3
}

run_tests(){
    DIR_TEST=$1
    SCENARIO_TEST=$5

    GOODPUT_RESULT_FILE="$DIR_TEST/goodput_results.txt"
	SYSCALLS_RESULT_FILE="$DIR_TEST/syscalls_results.txt"
	touch $GOODPUT_RESULT_FILE $SYSCALLS_RESULT_FILE

	docker-compose down > /dev/null 2>&1 # Stop any container running

	for ((i=1; i<=N_TEST_CASES; i++ )); do
	    run_docker_compose "$DIR_TEST/$i" "$2" "$2" "$3" "$4" "$SCENARIO_TEST"
		
		get_metrics "$DIR_TEST/$i" "$GOODPUT_RESULT_FILE" "$SYSCALLS_RESULT_FILE"
	done

    # printing mean and error of Goodput and Syscalls
    echo $DIR_TEST
    awk '{g=8*10000/$0;s+=g;s2+=g^2} END{printf "Goodput(kbps): %.2f +-%.2f\n", s/NR, sqrt(s2/NR-(s/NR)^2)}' "$GOODPUT_RESULT_FILE"
    awk '{g=$0;s+=g;s2+=g^2} END{printf "Syscalls: %.2f +-%.2f\n", s/NR, sqrt(s2/NR-(s/NR)^2)}' "$SYSCALLS_RESULT_FILE"
}


setup_tests || exit $?

INPLEM_ROW_N=3
INPLEM_COL_N=4
INPLEMENTATIONS=(
	linuxquic linuxquic interop_test interop_test
	msquic ghcr.io/microsoft/msquic/qns:main quicinteropserver quicinterop
	ngtcp2 ghcr.io/ngtcp2/ngtcp2-interop:latest h09wsslserver h09wsslclient
)

# Interate over each implemantion on $INPLEMENTATIONS  
for ((row=0; row<INPLEM_ROW_N; row++)); do
	
    i_name=$(( $row*$INPLEM_COL_N + 0 ))  # index of column 0
	i_image=$(( $row*$INPLEM_COL_N + 1 ))   # index of column 1
	i_server=$(( $row*$INPLEM_COL_N + 2 ))    # index of column 2
	i_client=$(( $row*$INPLEM_COL_N + 3 ))    # index of column 3


	IMPL_NAME="${INPLEMENTATIONS[$i_name]}"
    IMAGE_TEST="${INPLEMENTATIONS[$i_image]}"
    SERVER_PROCESS_NAME="${INPLEMENTATIONS[$i_server]}"
    CLIENT_PROCESS_NAME="${INPLEMENTATIONS[$i_client]}"


	printf "Running %s...\n" $IMPL_NAME

	DIR_NORMAL="$LOG_PATH/$IMPL_NAME/normal"
	mkdir -p $DIR_NORMAL
    run_tests "$DIR_NORMAL" "$IMAGE_TEST" "$SERVER_PROCESS_NAME" "$CLIENT_PROCESS_NAME" "simple-p2p --delay=15ms --bandwidth=10Mbps --queue=25"

	DIR_DROP1="$LOG_PATH/$IMPL_NAME/drop1"
	mkdir -p $DIR_DROP1
    run_tests "$DIR_DROP1" "$IMAGE_TEST" "$SERVER_PROCESS_NAME" "$CLIENT_PROCESS_NAME"  "drop-rate --delay=15ms --bandwidth=10Mbps --queue=25 --rate_to_client=1 --rate_to_server=1 --burst_to_client=3 --burst_to_server=3"

	DIR_DROP5="$LOG_PATH/$IMPL_NAME/drop5"
	mkdir -p $DIR_DROP5
    run_tests "$DIR_DROP5" "$IMAGE_TEST" "$SERVER_PROCESS_NAME" "$CLIENT_PROCESS_NAME"  "drop-rate --delay=15ms --bandwidth=10Mbps --queue=25 --rate_to_client=5 --rate_to_server=5 --burst_to_client=3 --burst_to_server=3"

	DIR_DROP10="$LOG_PATH/$IMPL_NAME/drop10"
	mkdir -p $DIR_DROP10
    run_tests "$DIR_DROP10" "$IMAGE_TEST" "$SERVER_PROCESS_NAME" "$CLIENT_PROCESS_NAME"  "drop-rate --delay=15ms --bandwidth=10Mbps --queue=25 --rate_to_client=10 --rate_to_server=10 --burst_to_client=3 --burst_to_server=3"
done

