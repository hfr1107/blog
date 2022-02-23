#!/bin/sh
nohup hugo server -D --bind 0.0.0.0 -p 20002 -w --disableLiveReload --environment production >nohup.out  2>&1 &
