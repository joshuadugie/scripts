#!/bin/bash

# http://sourceforge.net/projects/keepass/files/KeePass%201.x/
#
# Array.prototype.reverse.call(Array.prototype.map.call(
#   document.querySelectorAll("tbody a.name[href^='/projects']"),
#   function(a){ return a.outerText; }))
declare -a hist=( 0.8 0.81 0.82 0.83 0.83b 0.84 0.85 0.86 0.87 0.88a 0.89 \
    0.90a 0.91 0.92a 0.93a 0.93b 0.94a 0.95a 0.95b 0.96a 0.96b 0.97a 0.97b \
    0.97c 0.98a 0.98b 0.99a 0.99b 0.99c 1.00 1.01 1.02 1.03 1.04 1.05 1.06 \
    1.07 1.08 1.09 1.10 1.11 1.12 1.13 1.14 1.15 1.16 1.17 1.18 1.19 1.19b \
    1.20 1.21 1.22 1.23 1.24 1.25 1.26 1.27 )

pushd /home/user/KeePass-1.x &>/dev/null
for h in "${hist[@]}"; do
    rm -fr *
    echo "Creating revision ${h}"
    cp -p ../LICENSE ../README.md ./
    unzip /home/user/Downloads/keepass/KeePass-${h}-*.zip &>/dev/null
    git add -A .
    git commit --date="`date +%s -r /home/user/Downloads/keepass/KeePass-${h}-*.zip` +0000" -m"KeePass ${h}"
done
popd &>/dev/null
