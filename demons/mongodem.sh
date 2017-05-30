#!/bin/sh
#
# mysqld        This shell script takes care of starting and stop ping
#               the MySQL subsystem (mysqld).
#
# chkconfig: - 64 36
# description:  MySQL database server.
# processname: mysqld
# config: /etc/my.cnf
# pidfile: /var/run/mysqld/mysqld.pid
### BEGIN INIT INFO
# Provides: mysqld
# Required-Start: $local_fs $remote_fs $network $named $syslog $t ime
# Required-Stop: $local_fs $remote_fs $network $named $syslog $ti me
# Short-Description: start and stop MySQL server
# Description: MySQL database server
### END INIT INFO

# Source function library.
. /etc/rc.d/init.d/functions

# Source networking configuration.
. /etc/sysconfig/network


exec="/usr/bin/mysqld_safe"
prog="mysqld"

# Set timeouts here so they can be overridden from /etc/sysconfig
/mysqld
STARTTIMEOUT=120
STOPTIMEOUT=60

[ -e /etc/sysconfig/$prog ] && . /etc/sysconfig/$prog

lockfile=/var/lock/subsys/$prog


# extract value of a MySQL option from config files
# Usage: get_mysql_option SECTION VARNAME DEFAULT
# result is returned in $result
# We use my_print_defaults which prints all options from multiple
 files,
# with the more specific ones later; hence take the last match.
get_mysql_option(){
        result=`/usr/bin/my_print_defaults "$1" | sed -n "s/^--$2
=//p" | tail -n 1`
        if [ -z "$result" ]; then
            # not found, use default
            result="$3"
        fi
}

get_mysql_option mysqld datadir "/var/lib/mysql"
datadir="$result"
get_mysql_option mysqld socket "$datadir/mysql.sock"
socketfile="$result"
get_mysql_option mysqld_safe log-error "/var/log/mysqld.log"
errlogfile="$result"
get_mysql_option mysqld_safe pid-file "/var/run/mysqld/mysqld.pid
"
mypidfile="$result"


start(){
    [ -x $exec ] || exit 5
    # check to see if it's already running
    MYSQLDRUNNING=0
    if [ -f "$mypidfile" ]; then
        MYSQLPID=`cat "$mypidfile" 2>/dev/null`
        if [ -n "$MYSQLPID" ] && [ -d "/proc/$MYSQLPID" ] ; then
            MYSQLDRUNNING=1
        fi
    fi
    RESPONSE=`/usr/bin/mysqladmin --socket="$socketfile" --user=U
NKNOWN_MYSQL_USER ping 2>&1`
    if [ $MYSQLDRUNNING = 1 ] && [ $? = 0 ]; then
        # already running, do nothing
        action $"Starting $prog: " /bin/true
        ret=0
    elif [ $MYSQLDRUNNING = 1 ] && echo "$RESPONSE" | grep -q "Ac
cess denied for user"
    then
        # already running, do nothing
        action $"Starting $prog: " /bin/true
        ret=0
    else
        # prepare for start
        touch "$errlogfile" 2>/dev/null
        if [ $? -ne 0 ]; then
             # failed to touch log file, probably insufficient pe
rmissions
            action $"Starting $prog: " /bin/false
            return 4
        fi
        chown mysql:mysql "$errlogfile"
        chmod 0640 "$errlogfile"
        [ -x /sbin/restorecon ] && /sbin/restorecon "$errlogfile"
        if [ ! -d "$datadir/mysql" ] ; then
            # First, make sure $datadir is there with correct per
missions
            if [ ! -e "$datadir" -a ! -h "$datadir" ]
            then
                mkdir -p "$datadir" || exit 1
            fi
            chown mysql:mysql "$datadir"
            chmod 0755 "$datadir"
            [ -x /sbin/restorecon ] && /sbin/restorecon "$datadir
"
            # Now create the database
            action $"Initializing MySQL database: " /usr/bin/mysq
l_install_db --datadir="$datadir" --user=mysql
            ret=$?
            chown -R mysql:mysql "$datadir"
            if [ $ret -ne 0 ] ; then
                return $ret
            fi
        fi
        chown mysql:mysql "$datadir"
        chmod 0755 "$datadir"
        # We check if there is already a process using the socket
 file,
        # since otherwise this init script could report false pos
itive
        # result and mysqld_safe would remove the socket file, wh
ich
        # actually uses a different daemon.
        if fuser "$socketfile" &>/dev/null ; then
            echo "Socket file $socketfile exists. Is another MySQ
L daemon already running with the same unix socket?"
            action $"Starting $prog: " /bin/false
            return 1
        fi
        # Pass all the options determined above, to ensure consis
tent behavior.
        # In many cases mysqld_safe would arrive at the same conc
lusions anyway
        # but we need to be sure.  (An exception is that we don't
 force the
        # log-error setting, since this script doesn't really dep
end on that,
        # and some users might prefer to configure logging to sys
log.)
        # Note: set --basedir to prevent probes that might trigge
r SELinux
        # alarms, per bug #547485
        $exec   --datadir="$datadir" --socket="$socketfile" \
                --pid-file="$mypidfile" \
                --basedir=/usr --user=mysql >/dev/null 2>&1 &
        safe_pid=$!
        # Spin for a maximum of N seconds waiting for the server
to come up;
        # exit the loop immediately if mysqld_safe process disapp
ears.
        # Rather than assuming we know a valid username, accept a
n "access
        # denied" response as meaning the server is functioning.
        ret=0
        TIMEOUT="$STARTTIMEOUT"
        while [ $TIMEOUT -gt 0 ]; do
            RESPONSE=`/usr/bin/mysqladmin --socket="$socketfile"
--user=UNKNOWN_MYSQL_USER ping 2>&1`
            mret=$?
            if [ $mret -eq 0 ]; then
                break
            fi
            # exit codes 1, 11 (EXIT_CANNOT_CONNECT_TO_SERVICE) a
re expected,
            # anything else suggests a configuration error
            if [ $mret -ne 1 -a $mret -ne 11 ]; then
                echo "$RESPONSE"
                echo "Cannot check for MySQL Daemon startup becau
se of mysqladmin failure."
                ret=1
                break
            fi
            echo "$RESPONSE" | grep -q "Access denied for user" &
& break
            if ! /bin/kill -0 $safe_pid 2>/dev/null; then
                echo "MySQL Daemon failed to start."
                ret=1
                break
            fi
            sleep 1
            let TIMEOUT=${TIMEOUT}-1
        done
        if [ $TIMEOUT -eq 0 ]; then
            echo "Timeout error occurred trying to start MySQL Da
emon."
            ret=1
        fi
        if [ $ret -eq 0 ]; then
            action $"Starting $prog: " /bin/true
            chmod o+r $mypidfile >/dev/null 2>&1
            touch $lockfile
        else
            action $"Starting $prog: " /bin/false
        fi
    fi
    return $ret
}

stop(){
        if [ ! -f "$mypidfile" ]; then
            # not running; per LSB standards this is "ok"
            action $"Stopping $prog: " /bin/true
            return 0
        fi
        MYSQLPID=`cat "$mypidfile" 2>/dev/null`
        if [ -n "$MYSQLPID" ]; then
            /bin/kill "$MYSQLPID" >/dev/null 2>&1
            ret=$?
            if [ $ret -eq 0 ]; then
                TIMEOUT="$STOPTIMEOUT"
                while [ $TIMEOUT -gt 0 ]; do
                    /bin/kill -0 "$MYSQLPID" >/dev/null 2>&1 || b
reak
                    sleep 1
                    let TIMEOUT=${TIMEOUT}-1
                done
                if [ $TIMEOUT -eq 0 ]; then
                    echo "Timeout error occurred trying to stop M
ySQL Daemon."
                    ret=1
                    action $"Stopping $prog: " /bin/false
                else
                    rm -f $lockfile
                    rm -f "$socketfile"
                    action $"Stopping $prog: " /bin/true
                fi
            else
                action $"Stopping $prog: " /bin/false
            fi
        else
            # failed to read pidfile, probably insufficient permi
ssions
            action $"Stopping $prog: " /bin/false
            ret=4
        fi
        return $ret
}

restart(){
    stop
    start
}

condrestart(){
    [ -e $lockfile ] && restart || :
}


# See how we were called.
case "$1" in
  start)
    start
    ;;
  stop)
    stop
    ;;
  status)
    status -p "$mypidfile" $prog
    ;;
  restart)
    restart
    ;;
  condrestart|try-restart)
    condrestart
    ;;
  reload)
    exit 3
    ;;
  force-reload)
    restart
    ;;
  *)
    echo $"Usage: $0 {start|stop|status|restart|condrestart|try-r
estart|reload|force-reload}"
    exit 2
esac

exit $?