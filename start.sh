#!/bin/sh
nohup hugo server --bind 0.0.0.0 -p 20002 -w --environment production 2>&1 &
