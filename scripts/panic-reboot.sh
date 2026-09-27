#!/bin/bash
echo 1 >/proc/sys/kernel/sysrq
echo s >/proc/sysrq-trigger
sleep 2
echo u >/proc/sysrq-trigger
sleep 2
echo b >/proc/sysrq-trigger
