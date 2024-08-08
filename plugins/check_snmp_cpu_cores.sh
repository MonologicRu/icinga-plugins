#!/bin/bash
#
# Icinga Plugin Script (Check Command). Ccalculates the average percentage of CPU load over multiple cores from SNMPWALK
# Shchukin Maxim <dev@monologic.ru>
# Tested on CentOS GNU/Linux 6.5 with Icinga r2.6.3-1
# Put here: /usr/lib/nagios/plugins/check_snmp_cpu_cores.sh
# Usage example:
# ./check_snmp_cpu_cores.sh -H 10.0.1.1 -C public -t .1.3.6.1.2.1.25.3.3.1.2 -w 85 -c 95
#
PLUGIN_NAME="Icinga Plugin Check Command to calculate average CPU Load over Cores List (from SNMP data)"
PLUGIN_VERSION="2019.08.04"
PRINTINFO=`printf "\n%s, version %s\n \n" "$PLUGIN_NAME" "$PLUGIN_VERSION"`
#
# Exit codes
#
codeOK=0
codeWARNING=1
codeCRITICAL=2
codeUNKNOWN=3
#
# Default limits
#
LIMITCRITICAL=95
LIMITWARNING=85
#
Usage() {
  echo "$PRINTINFO"
  echo "Usage: $0 [OPTIONS]

Option   GNU long option        Meaning
------   ---------------        -------
 -H      --hostname             Host name, IP Address
 -C      --community            SNMPv1/2c community string for SNMP communication (for example,"public")
 -t      --cpu-list-oid         CPU Cores Load Parent Listing OID
 -w      --warning              Warning threshold for Disk usage percents
 -c      --critical             Critical threshold for Disk usage percents
 -q      --help                 Show this message
 -v      --version              Print version information and exit

"
}
#
# Parse arguments
#
if [ -z $1 ]; then
    Usage; exit $codeUNKNOWN;
fi

OPTS=`getopt -o H:P:C:L:a:x:U:A:X:t:f:w:c:qv -l hostname:,protocol:,community:,seclevel:,authproto:,privproto:,secname:,authpassword:,privpasswd:,total-mem-oid:,free-mem-oid:,warning:,critical:,help,version -- "$@"`
eval set -- "$OPTS"
while true; do
   case $1 in
     -H|--hostname)      HOSTNAME=$2 ; shift 2 ;;
     -C|--community)     COMMUNITY=$2 ; shift 2 ;;
     -t|--cpu-list-oid)  CPULISTOID=$2 ; shift 2 ;;
     -w|--warning)       LIMITWARNING=$2 ; shift 2 ;;
     -c|--critical)      LIMITCRITICAL=$2 ; shift 2 ;;
     -q|--help)          Usage ; exit $codeOK ;;
     -v|--version)       echo "$PRINTINFO" ; exit $codeOK ;;
     --) shift ; break ;;
     *)  Usage ; exit $codeUNKNOWN ;;
   esac
done

#
# Calculate Average CPU Usage Prcent
#


while read -r LINE; do
    # echo $LINE
    SUM=$( expr $SUM + $LINE )
    COUNT=$( expr $COUNT + 1 )
done <<< "$(/usr/bin/snmpwalk -v 2c -c $COMMUNITY -O e $HOSTNAME $CPULISTOID | sed "s/\"//g" | awk {' print $4 '}  )"
RESULT=$( expr $SUM / $COUNT )

# echo $COUNT
# echo $SUM
# echo $RESULT

vPERCENT=$RESULT

#
# Icinga Check Plugin output
#

if [ "$vPERCENT" -ge "$LIMITCRITICAL" ]; then
    echo "CPU Load percent CRITICAL - $vPERCENT % | CPULoadPercent=$vPERCENT"
    exit $codeCRITICAL
elif [ "$vPERCENT" -ge "$LIMITWARNING" ]; then
    echo "CPU Load percent WARNING - $vPERCENT % | CPULoadPercent=$vPERCENT"
    exit $codeWARNING
elif [ "$vPERCENT" -lt "$LIMITWARNING" ]; then
    echo "CPU Load percent OK - $vPERCENT % | CPULoadPercent=$vPERCENT"
    exit $codeOK
fi
exit $codeUNKNOWN
