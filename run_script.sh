#!/bin/bash
###############################################################################
#  Copyright (C) 2019 - K2 Cyber Security, Inc. All rights reserved.
#
#  This software is proprietary information of K2 Cyber Security, Inc and
#  constitutes valuable trade secrets of K2 Cyber Security, Inc. You shall
#  not disclose this information and shall use it only in accordance with the
#  terms of License.
#
#  K2 CYBER SECURITY, INC MAKES NO REPRESENTATIONS OR WARRANTIES ABOUT THE
#  SUITABILITY OF THE SOFTWARE, EITHER EXPRESS OR IMPLIED, INCLUDING BUT
#  NOT LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
#  PARTICULAR PURPOSE, OR NON-INFRINGEMENT. K2 CYBER SECURITY, INC SHALL
#  NOT BE LIABLE FOR ANY DAMAGES SUFFERED BY LICENSEE AS A RESULT OF USING,
#  MODIFYING OR DISTRIBUTING THIS SOFTWARE OR ITS DERIVATIVES.
#
#  "K2 Cyber Security, Inc"
#
################################################################################
help() {
  echo "To run a specific test and attack, ";
  echo "bash $0 sql-injection JAVA"
  echo "bash $0 verademo JAVA"
  echo "bash $0 forkexec JAVA"
  echo "bash $0 struts-cve-2017-5638 JAVA"
  echo "bash $0 easybuggy JAVA"
  echo "bash $0 spiracle JAVA"
  echo "bash $0 java-sec-code JAVA"
  echo "bash $0 tomcat-cve-2017-12617 JAVA"
  echo "bash $0 nginx BINARY"
  echo "bash $0 dnsmasq BINARY"
  echo "bash $0 node-demo-app sqli NODE.JS"
  echo "bash $0 node-demo-app rce NODE.JS"
  echo "bash $0 node-demo-app rci NODE.JS"
  echo "bash $0 node-demo-app ssrf NODE.JS"
  echo "bash $0 node-demo-app file-access NODE.JS"
  echo "bash $0 node-demo-app nosqli NODE.JS"
}
die() {
 ret=$1
 if [ ${ret} != 0 ]
 then
       echo "Error: $ret"
       exit 1;
 fi
}
start(){
    echo
    echo
    echo "Test [$1] "
    case $1 in
    "sql-injection"|"verademo"|"forkexec"|"struts-cve-2017-5638"|"spiracle"|"easybuggy"|"java-sec-code"|"tomcat-cve-2017-12617")
        docker rm -f test-$1
        docker rmi -f k2cyber/ic-test-application:${1}
        docker run --rm -v /opt/k2-ic:/opt/k2-ic -itd -p 8091:8080 -e K2_OPTS="-javaagent:/opt/k2-ic/K2-JavaAgent-1.0.0-jar-with-dependencies.jar" --name test-${1} k2cyber/ic-test-application:${1};
        ret=$?; die $ret
            ;;
    "node-demo-app")
        docker rm -f test-$1
        docker rmi -f k2cyber/ic-test-application:${1}
        docker run --rm -v /opt/k2-ic:/opt/k2-ic -itd -p 9090:9090 -e K2_OPTS="--require /opt/k2-ic/k2-njs-agent" --name test-${1} k2cyber/ic-test-application:${1};
        ret=$?; die $ret
            ;;
    "dnsmasq")
      docker stop test-$1
      docker rm -f test-$1
      aslr=`cat /proc/sys/kernel/randomize_va_space`
      echo "Current ASLR status $aslr"
      echo "Turning off ASLR"
      echo 0 | sudo tee /proc/sys/kernel/randomize_va_space >& /dev/null
      docker exec k2agent bash -c ">/tmp/monitorstatus.txt"
      docker rmi -f k2cyber/ubuntu-dnsmasq1
      docker run --rm  --name test-${1} -d k2cyber/ubuntu-dnsmasq1
      ret=$?; die $ret
      docker exec test-${1} ip addr show eth0|grep inet6 >& /dev/null
      if [ $? -ne 0 ]; then
                  echo "Failed: IPV6 not enabled on docker daemon"
                  echo "Refer To Docker Documentation At:"
                  echo -e "https://docs.docker.com/v17.09/engine/userguide/networking/default_network/ipv6/"
          docker stop test-$1
          docker rm -f test-$1
                  exit
      fi
            ;;
    "nginx")
        echo 2 | sudo tee /proc/sys/kernel/randomize_va_space >& /dev/null
        read -r -p "Stop/Remove Nginx Containers/Images? [y/N] " response
          case "$response" in
              [yY][eE][sS]|[yY])
               echo "Stopping Nginx Container and Removing Nginx Images"
               docker stop test-${1}
               docker rm -f test-${1}
               docker rmi -f k2cyber/nginx-1.4.0-exploit
               docker rmi -f k2cyber/nginx-1.4.0-exploiter-local
                  ;;
 
               *)
                  ;;
          esac
          out=`docker ps`
          if [[ $out == *"test-nginx"* ]]; then
            echo "nginx-1.4.0-exploit already running"
          else
            docker exec k2agent bash -c ">/tmp/monitorstatus.txt"
            docker run --rm -itd -p 80:80 --name test-nginx k2cyber/nginx-1.4.0-exploit
            ret=$?; die $ret
          fi
            ;;
    *)  help;echo "Invalid test name : $1";ret=-1;die $ret;;
    esac
    if [[ "$1" == "nginx" ]]
    then
      echo -e "\e[32m\e[1mStep 1: INITIALIZING K2 TO PROTECT NGINX SERVER (Can take about 5 min)"
      echo -e "\e[0mWaiting maximum 10 minute for test application to come up in watch interval of 30 seconds:$(date)"
      masternginx=`ps aux|grep nginx|grep master|awk -F " " '{print $2}'`
      if [ $? -ne 0 ]; then
                  echo "Could not file master nginx: ${masternginx}"
                  die
      fi
      workernginx=`ps aux|grep nginx|grep worker|awk -F " " '{print $2}'`
      if [ $? -ne 0 ]; then
           echo "Could not file worker nginx: ${workernginx}"
           die
      fi
      for i in {1..120}
      do
        docker exec k2agent cat /tmp/monitorstatus.txt |grep "Started Monitoring Pid:$masternginx" >& /dev/null
            ret=$?
            if [ $ret -ne 0 ]; then
                    echo "master nginx not monitored yet"
                    sleep 30
                    continue
           fi
       docker exec k2agent cat /tmp/monitorstatus.txt |grep "Started Monitoring Pid:$workernginx" >& /dev/null
           ret=$?
           if [ $ret -ne 0 ]; then
                   echo "worker nginx not monitored yet"
                   sleep 30
                   continue
           fi
           break
      done
      if [ $ret -ne 0 ]; then
         echo "failed to monitor nginx"
         die
      fi
      sleep 5
      docker run --net=host -it k2cyber/nginx-1.4.0-exploiter-local ruby exp-nginx-lc.rb 127.0.0.1 80
      echo "Test Done [$1] :$(date)"
    elif [[ "$1" == "dnsmasq" ]]
    then
      echo -e "\e[32m\e[1mStep 1: INITIALIZING K2 TO PROTECT DNSMASQ"
          echo -e "\e[0mWaiting maximum 10 minute for test application to come up in watch interval of 30 seconds:$(date)"
      dnspid=`ps aux|grep "test\/dnsmasq"|awk -F " " '{print $2}'`
      if [ $? -ne 0 ]; then
              echo "Could not file dnsmasq: ${dnspid}"
              die
      fi
          for i in {1..120}
          do
        docker exec k2agent cat /tmp/monitorstatus.txt |grep "Started Monitoring Pid:$dnspid" >& /dev/null
            ret=$?
            if [ $ret -ne 0 ]; then
                    echo "dnsmasq not monitored yet"
                    sleep 30
                    continue
            fi
            break
      done
      if [ $ret -ne 0 ]; then
          echo "failed to monitor dnsmasq"
          die
      fi
      echo -e "\033[01;32mStep 2: APPLICATION SETUP IS READY FOR ATTACK! \033[00m"
          sleep 5
      echo Press key to run attack
      read x
      echo -e "\033[01;32mStep 3: TRIGERRING THE ATTACK \033[00m"
          docker exec test-${1} python poc.py ::1 547
      echo -e "\033[01;32mStep 3: ATTACK SUCCESSFUL \033[00m"
      echo "Test Cleanup [$1] "
          sleep 30
          echo "Restoring ASLR to $aslr"
          echo $aslr | sudo tee /proc/sys/kernel/randomize_va_space >& /dev/null
      docker rm -f test-${1}
      docker rmi -f k2cyber/ubuntu-dnsmasq1
    elif [[ "$1" == "node-demo-app" ]]
    then
      echo -e "\033[01;32mStep 1: INSTALLING THE VULNERABLE NODE APPLICATION (Can take about 2 min) \033[00m"
      echo "Waiting maximum 1 minute for test application to come up in watch interval of 10 seconds"
      for i in {1..36}
      do
        status=$(docker exec -it test-${1} bash -c "ps -ef | grep /opt/k2-ic/k2-njs-agent" | wc -l)
        if [ ${status} -eq 3 ]; then
            echo "Test Container is up"
            echo -e "\033[01;32mStep 2: APPLICATION SETUP IS READY FOR ATTACK! \033[00m"
            break
        fi
        sleep 10
      done
      echo Press key to run attack
      read x
      docker exec -it test-${1} bash -c "/attack.sh ${2}"
      sleep 10
      echo "Test Cleanup [$1] "
      echo Press key to Clean up VULNERABLE Container
      read x
      docker rm -f test-${1}
      docker rmi -f k2cyber/ic-test-application:${1}
    else
      echo -e "\033[01;32mStep 1: INSTALLING THE VULNERABLE JAVA APPLICATION (Can take about 2 min) \033[00m"
      echo "Waiting maximum 1 minute for test application to come up in watch interval of 10 seconds"
      for i in {1..36}
      do
        status=$(docker exec -it test-${1} bash -c "ps -ef | grep K2-JavaAgent-1.0.0-jar-with-dependencies.jar" | wc -l)
        if [ ${status} -eq 3 ]; then
            echo "Test Container is up"
            echo -e "\033[01;32mStep 2: APPLICATION SETUP IS READY FOR ATTACK! \033[00m"
            break
        fi
        sleep 10
      done
      echo Press key to run attack
      read x
      docker exec -it test-${1} bash -c ./attack.sh
      sleep 10
      echo "Test Cleanup [$1] "
      echo Press key to Clean up VULNERABLE Container
      read x
      docker rm -f test-${1}
      docker rmi -f k2cyber/ic-test-application:${1}
    fi
}
if [ $# -eq 0 ]
then
   help;
else
    tests="$*"
    start ${tests}
fi
