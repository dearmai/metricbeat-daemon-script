#!/bin/bash

SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do
  DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  SOURCE=$(readlink "$SOURCE")
  [[ $SOURCE != /* ]] && SOURCE=$DIR/$SOURCE
done
DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )

cd ${DIR}/..
TARGET_PATH=${PWD}


source ${DIR}/variables
source ${DIR}/common


PID_PATH=${TARGET_PATH}/pid
PROCESS_KEYWORD="./metricbeat"

function init() { 
    print "Daemon script path : ${DIR}"
    print "${TARGET_NAME} path : ${TARGET_PATH}"

     status_pidfile > /dev/null 2>&1

    if [ -f "${TARGET_PATH}/metricbeat" ]; then
        return 0
    else
        print_err "스크립트 파일은 ${TARGET_NAME} 하위 폴더 내 설치 되어야 합니다."
        return 1
    fi
}

function usage() {
    print "사용법"
    echo "$(basename "$0") <command> (options)"
    echo "command"
    echo -e "\t- status : 프로세스 상태 조회"
    echo -e "\t- run : Foreground 모드 실행"
    echo -e "\t- start : Daemon(background) 모드 실행"
    echo -e "\t- stop : 종료(SIGTERM)"
    echo -e "\t- kill : 강제 종료(SIGKILL)"
}

function get_pid() {
    if [ -e ${PID_PATH} ]; then
        echo $(cat ${PID_PATH} 2> /dev/null)

        return 0
    else
        echo "'pid' not found"
        return 1
    fi
}

function find_pid() {
    local pid=$(ps au | grep ${PROCESS_KEYWORD} | grep -v grep | awk '{print $2}')
    if [ $? -ne 0 ]; then
        echo "not found"
        return 1
    fi
    echo ${pid}
    return 0
}

function status_pidfile() {
    if [ -e ${PID_PATH} ]; then
        pgrep -F ${PID_PATH}
        if [ $? -eq 0 ]; then
            return 0
        else
            echo "process died."
            rm -rf ${PID_PATH}
            return 2
        fi
        
    else
        echo "'pid' not found"
        return 1
    fi
}

function check_netstat() {
    local netstat=$(netstat -nat | grep ":${KB_PORT} " | grep "LISTEN" | wc -l)
    if [ ${netstat} -eq 0 ]; then
        echo "die"
        return 1
    fi
    echo "alive"
    return 0
}

function wait_status() {
    local timeout=10
    local count=1

    while [ ${count} -le ${timeout} ]
    do
        echo -n "."
        sleep 1
        ((count++))
    done
}

function show_status() {
    echo -e "$(date +%Y-%m-%dT%H:%M:%S%z)\tPID : $(get_pid)"
}

init

case $1 in
    status)
        sleep 1

        print "Status"
        echo "Process ID : $(get_pid)"
        echo "Process ID file check : $(status_pidfile)"
        ;;
    run)
        print "Run"
        cd ${TARGET_PATH}
        exec ./metricbeat -e
        ;;
    start)
        if [ -e ${PID_PATH} ]; then
            # PID 파일이 있으나 실제 실행중이지 않을 경우 처리
            if [ -e "/proc/$(get_pid)" ]; then
                print_err "이미 실행 중 입니다."
                echo "PID_PATH : ${PID_PATH}"
                echo "PID : $(get_pid)"
                exit 1
            else 
                # PID 파일 삭제
                print "PID 파일이 존재 하나 동작중이지 않은 상태로 확인됨(PID : $(get_pid))"
                rm -f ${PID_PATH}                
            fi 
        else
            print "Daemon start"
        fi

        cd ${TARGET_PATH}
        eval nohup "./metricbeat" > /dev/null 2>&1 "&"
        echo $! > ${PID_PATH}

        while :
        do
            show_status
            if [ -e ${PID_PATH} ]; then
                print "${TARGET_NAME} 가 정상적으로 시작됨"
                break;
            fi
            sleep 1
        done;
        ;;
    stop)
        get_pid > /dev/null 2>&1
        if [ -e ${PID_PATH} ]; then
            print "Daemon stop - y/n"
        else
            print_err "실행 중이지 않습니다."
            echo "PID_PATH : ${PID_PATH}"
            exit 1
        fi
        
        echo ${PID_PATH} | xargs -p pkill -15 -F

        if [ $? -eq 0 ]; then
            while :
            do
                status_pidfile > /dev/null 2>&1
                show_status
                if ! [ -e ${PID_PATH} ]; then
                    print "${TARGET_NAME} 정상적으로 종료 됨"
                    break;
                fi
                sleep 1
            done;
        fi
        ;;
    kill)
        if [ -e ${PID_PATH} ]; then
            kill -9 $(cat ${PID_PATH})
        else
            # pid 파일 못찾음.. pid 찾기 시도
            echo "PID 파일이 존재 하지 않아 프로세스에서 직접 PID 찾기 시도"
            pid=$(find_pid)

            if [ -z ${pid} ]; then
                echo "프로세스 목록에서 ${TARGET_NAME} 을 찾지 못함"
                exit 1
            else 
                echo "PID : ${pid}"
                echo ${pid} | xargs -p kill -9
                exit 0
            fi
        fi
        ;;
    *)
        usage
        ;;
esac
