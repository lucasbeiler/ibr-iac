#!/bin/bash
set -e
unalias -a

if [ -d "$1" ]; then
  echo "You have set the working directory as $1."
  echo "MAKE SURE YOU HAVE A BACKUP!"
  cd $1
else
  echo "The directory $1 does not exist."
  exit 1
fi

OUTPUT_FILENAME="$(pwd)/global_dataset.csv"
CSV_HEADER="region,frame.time_epoch,ip.src,ip.dst,ip.proto,ip.geoip.src_country,tcp.srcport,tcp.dstport,udp.srcport,udp.dstport,icmp.type,icmp.code,frame.len,tcp.flags,http.request.method,http.request.uri,http.user_agent,data.data"
CSV_HEADER_CMD=$(echo "$CSV_HEADER" | sed 's/region,/-e/g' | sed 's/,/ -e /g')
FILTER='-Y "not ((tcp.srcport eq 80 or tcp.srcport eq 443 or tcp.srcport eq 853) and tcp.dstport >= 32768) and not ((udp.srcport eq 53 or udp.srcport eq 123 or udp.srcport eq 443) and udp.dstport >= 32768) and not (icmp.type == 0 or icmp.type == 3 or icmp.type == 5 or or icmp.type == 9 or icmp.type == 10 or icmp.type == 11 or icmp.type == 12 or icmp.type == 14)"'
echo $CSV_HEADER > $OUTPUT_FILENAME


for filename in $(find . -type f \( -name "*.pcap" -o -name "*.pcap.gz" \) 2>/dev/null); do
  region=$(basename -- $filename | grep -oP '^[a-z]+-[a-z]+-\d+')
  echo "[$(date +%H:%M:%S) -- $(du -h $OUTPUT_FILENAME | awk '{print $1}')] Appending data from ${region} ($(basename -- $filename)) into the CSV file..."

  tshark -nq -r ${filename} ${FILTER} -T fields ${CSV_HEADER_CMD} -E header=n -E separator=, -E quote=d -E occurrence=f 2>/dev/null | awk -v region="\"$region\"" '{print region "," $0}' 2>/dev/null >> $OUTPUT_FILENAME
done;
