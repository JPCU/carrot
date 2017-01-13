#!/bin/sh
cd $(dirname $0)
rm -f log/[0-9]* log/index log/kernel.log log/sasl.log

exec erl \
    +P 5000000 \
    +K true \
    -pa ebin \
    -pa deps/*/ebin \
    -s carrot \
    -sname carrot_dev
