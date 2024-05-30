#!/bin/sh
#
# Icinga Plugin Script (Check Command). It calculate the percentage of Disk usage from received SNMP data
# Aleksey Maksimov <aleksey.maksimov@it-kb.ru>
# Tested on Debian GNU/Linux 8.7 (Jessie) with Icinga r2.6.3-1
# Put here: /usr/lib/nagios/plugins/snmp_memusage_percent.sh
# Usage example:
# ./snmp_memusage_percent.sh -H netdev01.holding.com -P 1 -C public -t 1.3.6.1.4.1.332.11.6.1.8.0 -f 1.3.6.1.4.1.332.11.6.1.9.0 -w 85 -c 95
#
PLUGIN_NAME="Icinga Plugin Check Command to calculate the percentage of Disk used (from SNMP data)"
PLUGIN_VERSION="2017.05.01"
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
LIMITCRITICAL=100
LIMITWARNING=100
#
Usage() {
  echo "$PRINTINFO"
  echo "Usage: $0 [OPTIONS]

Option   GNU long option        Meaning
------   ---------------        -------
 -H      --hostname             Host name, IP Address
 -P      --protocol             SNMP protocol version. Possible values: 1|2c|3
 -C      --community            SNMPv1/2c community string for SNMP communication (for example,"public")
 -L      --seclevel             SNMPv3 securityLevel. Possible values: noAuthNoPriv|authNoPriv|authPriv
 -a      --authproto            SNMPv3 auth proto. Possible values: MD5|SHA
 -x      --privproto            SNMPv3 priv proto. Possible values: DES|AES
 -U      --secname              SNMPv3 username
 -A      --authpassword         SNMPv3 authentication password
 -X      --privpasswd           SNMPv3 privacy password
 -t      --total-mem-oid        Total Disk OID
 -f      --free-mem-oid         Free Disk OID
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
#
OPTS=`getopt -o H:P:C:L:a:x:U:A:X:t:f:w:c:qv -l hostname:,protocol:,community:,seclevel:,authproto:,privproto:,secname:,authpassword:,privpasswd:,total-mem-oid:,free-mem-oid:,warning:,critical:,help,version -- "$@"`
eval set -- "$OPTS"
while true; do
   case $1 in
     -H|--hostname) HOSTNAME=$2 ; shift 2 ;;
     -P|--protocol)
        case "$2" in
        "1"|"2c"|"3") PROTOCOL=$2 ; shift 2 ;;
        *) printf "Unknown value for option %s. Use '1' or '2c' or '3'\n" "$1" ; exit $codeUNKNOWN ;;
        esac ;;
     -C|--community)     COMMUNITY=$2 ; shift 2 ;;
     -L|--seclevel)
        case "$2" in
        "noAuthNoPriv"|"authNoPriv"|"authPriv") v3SECLEVEL=$2 ; shift 2 ;;
        *) printf "Unknown value for option %s. Use 'noAuthNoPriv' or 'authNoPriv' or 'authPriv'\n" "$1" ; exit $codeUNKNOWN ;;
        esac ;;
     -a|--authproto)
        case "$2" in
        "MD5"|"SHA") v3AUTHPROTO=$2 ; shift 2 ;;
        *) printf "Unknown value for option %s. Use 'MD5' or 'SHA'\n" "$1" ; exit $codeUNKNOWN ;;
        esac ;;
     -x|--privproto)
        case "$2" in
        "DES"|"AES") v3PRIVPROTO=$2 ; shift 2 ;;
        *) printf "Unknown value for option %s. Use 'DES' or 'AES'\n" "$1" ; exit $codeUNKNOWN ;;
        esac ;;
     -U|--secname)       v3SECNAME=$2 ; shift 2 ;;
     -A|--authpassword)  v3AUTHPWD=$2 ; shift 2 ;;
     -X|--privpasswd)    v3PRIVPWD=$2 ; shift 2 ;;
     -t|--total-mem-oid) MEMTOTALOID=$2 ; shift 2 ;;
     -f|--free-mem-oid)  MEMFREEOID=$2 ; shift 2 ;;
     -w|--warning)       LIMITWARNING=$2 ; shift 2 ;;
     -c|--critical)      LIMITCRITICAL=$2 ; shift 2 ;;
     -q|--help)          Usage ; exit $codeOK ;;
     -v|--version)       echo "$PRINTINFO" ; exit $codeOK ;;
     --) shift ; break ;;
     *)  Usage ; exit $codeUNKNOWN ;;
   esac
done
#
# Set SNMP connection paramaters
#
vCS=$( echo " -O qvn -v $PROTOCOL" )
if [ "$PROTOCOL" = "1" ] || [ "$PROTOCOL" = "2c" ]
then
   vCS=$vCS$( echo " -c $COMMUNITY" );
elif [ "$PROTOCOL" = "3" ]
then
   vCS=$vCS$( echo " -l $v3SECLEVEL" );
   vCS=$vCS$( echo " -a $v3AUTHPROTO" );
   vCS=$vCS$( echo " -x $v3PRIVPROTO" );
   vCS=$vCS$( echo " -A $v3AUTHPWD" );
   vCS=$vCS$( echo " -X $v3PRIVPWD" );
   vCS=$vCS$( echo " -u $v3SECNAME" );
fi
#
# Calculate Disk usage percent
#
vMTOTAL=$( snmpget $vCS $HOSTNAME $MEMTOTALOID | sed "s/\"//g" )
vMFREE=$( snmpget $vCS $HOSTNAME $MEMFREEOID | sed "s/\"//g" )
vUSED=$( expr $vMTOTAL - $vMFREE )
vPERCENT=$( awk "BEGIN { pc=100*(1-${vUSED}/${vMTOTAL}); i=int(pc); print (pc-i<0.5)?i:i+1 }" )
#
# Icinga Check Plugin output
#
if [ "$vPERCENT" -ge "$LIMITCRITICAL" ]; then
    echo "Usage percent CRITICAL - $vPERCENT % | UsagePercent=$vPERCENT"
    exit $codeCRITICAL
elif [ "$vPERCENT" -ge "$LIMITWARNING" ]; then
    echo "Usage percent WARNING - $vPERCENT % | UsagePercent=$vPERCENT"
    exit $codeWARNING
elif [ "$vPERCENT" -lt "$LIMITWARNING" ]; then
    echo "Usage percent OK - $vPERCENT % | UsagePercent=$vPERCENT"
    exit $codeOK
fi
exit $codeUNKNOWN
