#!/bin/sh
nohup hugo server --bind 0.0.0.0 -p 20002 -w --environment production >nohup.out  2>&1 &
