#! /bin/sh
# chkconfig: 345 97 10
# description: routed
# processname: osrm-routed
### BEGIN INIT INFO
# Provides:          routed
# Required-Start:    $remote_fs
# Required-Stop:     $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Route-finder daemon
# Description:       Route-finder daemon.
### END INIT INFO
export LD_LIBRARY_PATH=/opt/gcc49/lib:/opt/gcc49/lib64:$LD_LIBRARY_PATH

log_daemon_msg() { logger "$@"; }
log_end_msg() { [ $1 -eq 0 ] && RES=OK; logger ${RES:=FAIL}; }
. /etc/rc.d/init.d/functions


# Do NOT "set -e"

# PATH should only include /usr/* if it runs after the mountnfs.sh script
PATH=/sbin:/usr/sbin:/bin:/usr/bin
DESC="Route-finder daemon"
NAME=osrm-routed
DHOME=/home/osm
DAEMON=$DHOME/$NAME
SHMLOADER=$DHOME/osrm-datastore
SHMUNLOADER=$DHOME/osrm-springclean
DDATA="$DHOME/routed/japan-extract.osrm"
DAEMON_ARGS="--max_locations_distance_table 500 --sharedmemory --threads 4 --ip 0.0.0.0"
PIDFILE=/var/run/$NAME/$NAME.pid
SCRIPTNAME=/etc/init.d/routed

# Exit if the package is not installed
[ -x "$DAEMON" ] || exit 0

# Read configuration variable file if it is present
[ -r /etc/default/$NAME ] && . /etc/default/$NAME

# Load the VERBOSE setting and other rcS variables
#. /lib/init/vars.sh # Debian-specific

# Define LSB log_* functions.
# Depend on lsb-base (>= 3.0-6) to ensure that this file is present.
#. /lib/lsb/init-functions # Debian-specific

#
# Function that starts the daemon/service
#
do_start()
{
    mkdir -p /var/run/$NAME
    chown www-data:www-data /var/run/$NAME
    cd $DHOME
    if [ -f $PIDFILE ]; then return 2; fi
    $SHMLOADER $DDATA  | /usr/bin/logger -t routed
    RETVAL=$?
    if [ $RETVAL != 0 ]; then return 1; fi
    ($DAEMON $DAEMON_ARGS 2>&1 | /usr/bin/logger -t routed) &
    if [ $RETVAL != 0 ]; then return 1; fi
    echo $! > $PIDFILE
    return 0
    # Add code here, if necessary, that waits for the process to be ready
    # to handle requests from services started subsequently which depend
    # on this one.  As a last resort, sleep for some time.
}

#
# Function that stops the daemon/service
#
do_stop()
{
    # Return
    #   0 if daemon has been stopped
    #   1 if daemon was already stopped
    #   2 if daemon could not be stopped
    #   other if a failure occurred
    killproc -p $PIDFILE -d 5 $NAME
    RETVAL="$?"
    [ "$RETVAL" = 2 ] && return 2
    # Wait for children to finish too if this is a daemon that forks
    # and if the daemon is only ever run from this initscript.
    # If the above conditions are not satisfied then add some other code
    # that waits for the process to drop all resources that could be
    # needed by services started subsequently.  A last resort is to
    # sleep for some time.
    killproc -d 5 $DAEMON
    [ "$?" = 2 ] && return 2
    # Many daemons don't delete their pidfiles when they exit.
    rm -f $PIDFILE

    /usr/bin/yes Y | $SHMUNLOADER
    return "$RETVAL"
}

#
# Function that sends a SIGHUP to the daemon/service
#
do_reload() {
    # If the daemon can reload its configuration without
    # restarting (for example, when it is sent a SIGHUP),
    # then implement that here.
    #do_stop
    #do_start
    $SHMLOADER $DDATA  | /usr/bin/logger -t routed
    return 0
}

case "$1" in
    start) 
        log_daemon_msg "Starting $DESC" "$NAME"
        do_start
    case "$?" in
        0|1) log_end_msg 0 ;;
        2) log_end_msg 1 ;;
    esac
    ;;
    reload) 
        log_daemon_msg "Reloading $DESC" "$NAME"
        do_reload
    case "$?" in
        0|1) log_end_msg 0 ;;
        2) log_end_msg 1 ;;
    esac
    ;;
    stop)
        log_daemon_msg "Stopping $DESC" "$NAME"
        do_stop
    case "$?" in
       0|1) log_end_msg 0 ;;
       2) log_end_msg 1 ;;
    esac
    ;;
    #reload|force-reload)
    #
    # If do_reload() is not implemented then leave this commented out
    # and leave 'force-reload' as an alias for 'restart'.
    #
    #log_daemon_msg "Reloading $DESC" "$NAME"
    #do_reload
    #log_end_msg $?
    #;;
    restart|force-reload)
    #
    # If the "reload" option is implemented then remove the
    # 'force-reload' alias
    #
        log_daemon_msg "Restarting $DESC" "$NAME"
        do_stop
            case "$?" in
                0|1) do_start
                    case "$?" in
                        0) log_end_msg 0 ;;
                        1) log_end_msg 1 ;; # Old process is still running
                        *) log_end_msg 1 ;; # Failed to start
                    esac
                    ;;
                *)
                    # Failed to stop
                    log_end_msg 1
                    ;;
            esac
            ;;
    *)
        echo "Usage: $SCRIPTNAME {start|stop|restart|reload|force-reload}" >&2
        exit 3
        ;;
esac

:



