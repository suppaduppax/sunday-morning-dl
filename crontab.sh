#!/bin/bash

line="0 */1 * * 0,1 cd /home/alvin/sunday-morning-dl/ && ./cbs-sunday-morning-dl.sh"
if crontab -l | fgrep -q "${line}"; then
    echo "Entry already exists in crontab"
else
    (crontab -l 2>/dev/null; echo "${line}") | crontab -
    echo "Added to crontab!"
fi

