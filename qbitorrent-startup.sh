#!/bin/bash

#First Running qbitorrent script that starts qbitorrent adding '&' runs the script in the background so the next command can start immediately. 'wait' keeps the parent script alive, waiting for both background scripts. For 24/7 scripts, this ensures the container or terminal doesn’t exit.
./entrypoint.sh &
speed 20

#Running qbitorrent-monitor-seed.sh to monitor seeds avg speed and delete inactive ones
./config/qBittorrent/config/scripts/qbitorrent-monitor-seed.sh &

#Running qbitorrent-monitor-delete.sh to monitor seeds avg speed and delete inactive ones
./config/qBittorrent/config/scripts/qbitorrent-monitor-delete.sh &

wait
