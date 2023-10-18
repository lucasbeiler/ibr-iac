#!/bin/bash
set -e
unalias -a
export LC_NUMERIC="en_US.UTF-8"

# Set the filenames that will be used to name the temporary files.
TMP_STATS_FILENAME=tmpstatsfile

# Write down the current directory and build the Go code.
CODE_DIR=$(pwd)
go mod init github.com/lsbeiler/ibr-iac && go get github.com/google/gopacket
go build extractor.go

# Verify if the working directory provided by the user is actually there.
if [ -d "$1" ]; then
  cd $1
  echo "Changed into $1."
  echo "[$(date +%H:%M:%S)] Gunzipping files..."
  gunzip -r .
  echo "[$(date +%H:%M:%S)] Removing temporary files before we start... The deleted files are going to be listed below."
  find . -type f -name "${TMP_STATS_FILENAME}*" ! -name '*.pcap' ! -name '*.txt' -delete -print
else
  echo "The directory $1 does not exist."
  exit 1
fi

# The find command below uses the Go program to read each regional PCAP in each region's directory, then it will pipe the output into a temporary file.
echo "[$(date +%H:%M:%S)] Composing sources for total statistics... May take a while."
find . -name '*.pcap' -print -execdir sh -c "${CODE_DIR}/extractor -input {} -output ${TMP_STATS_FILENAME}" \;  

# To be compared with each region's total packets in order to know (by percentage) how big the region is in the global picture.
echo "[$(date +%H:%M:%S)] Counting how many packets were captured globally..."
TOTAL_GLOBAL_PKTS=$(wc -l merges/*/$TMP_STATS_FILENAME | tail -1 | grep -i total$ | awk '{print $1}')

generate_global_stats() {
    local merged_list_src_ips=""
    local merged_list_tcp=""
    local merged_list_udp=""

    # Collect the TOP 20 from each region.
    for file in $(find merges -type f -name "*stats.txt" 2>/dev/null); do
        if [ -f "$file" ]; then
            lists=$(awk '/TOP 20 SRC IPs:/,/TOP 20 TCP PORTS:/ { if (NF > 1) print $1, $2 }' "$file")
            merged_list_src_ips=$(echo -e "$merged_list_src_ips\n$lists")

            lists=$(awk '/TOP 20 TCP PORTS:/,/TOP 20 UDP PORTS:/ { if (NF > 1) print $1, $2 }' "$file")
            merged_list_tcp=$(echo -e "$merged_list_tcp\n$lists")

            lists=$(awk '/TOP 20 UDP PORTS:/,/^$/ { if (NF > 1) print $1, $2 }' "$file")
            merged_list_udp=$(echo -e "$merged_list_udp\n$lists")
        fi
    done

    # Merge each TOP 20.
    sorted_list_src_ips=$(echo "$merged_list_src_ips" | awk '{ sum[$2] += $1 } END { for (title in sum) printf "%6d %s\n", sum[title], title }' | sort -nr | head -20)
    sorted_list_tcp=$(echo "$merged_list_tcp" | awk '{ sum[$2] += $1 } END { for (title in sum) printf "%6d %s\n", sum[title], title }' | sort -nr | head -20)
    sorted_list_udp=$(echo "$merged_list_udp" | awk '{ sum[$2] += $1 } END { for (title in sum) printf "%6d %s\n", sum[title], title }' | sort -nr | head -20)

    # Sum general statistics.
    TOTAL_PKTS=$(grep 'total packets:' merges/*/*stats.txt | tr -d ',' | awk '{sum += $4} END {print sum}')
    TOTAL_TCP_PKTS=$(grep 'total TCP packets:' merges/*/*stats.txt | tr -d ',' | awk '{sum += $5} END {print sum}')
    TOTAL_TCP_UNIQUE_CONNS=$(grep 'total TCP unique connections:' merges/*/*stats.txt | tr -d ',' | awk '{sum += $6} END {print sum}')
    TOTAL_UDP_PKTS=$(grep 'total UDP packets:' merges/*/*stats.txt | tr -d ',' | awk '{sum += $5} END {print sum}')
    TOTAL_ICMP_PKTS=$(grep 'total ICMP packets:' merges/*/*stats.txt | tr -d ',' | awk '{sum += $5} END {print sum}')
    
    # Save the results
    echo -e "Total packets: $(printf "%'d" $TOTAL_PKTS)"
    echo -e "Total TCP packets: $(printf "%'d" $TOTAL_TCP_PKTS)" 
    echo -e "Total TCP unique connections: $(printf "%'d" $TOTAL_TCP_UNIQUE_CONNS)" 
    echo -e "Total UDP packets: $(printf "%'d" $TOTAL_UDP_PKTS)" 
    echo -e "Total ICMP packets: $(printf "%'d" $TOTAL_ICMP_PKTS)" 
    echo -e "TOP 20 SRC IPs:\n$sorted_list_src_ips" 
    echo -e "TOP 20 TCP PORTS:\n$sorted_list_tcp" 
    echo -e "TOP 20 UDP PORTS:\n$sorted_list_udp" 
}

# Function to fetch statistics out of the temporary files.
fetch_statistics() {
  current_dir="$(dirname $f)/"
  region=$(basename $current_dir)

  tmp_stats_file="${current_dir}${TMP_STATS_FILENAME}"

  TOTAL_PKTS=$(cat $tmp_stats_file | wc -l)
  PERCENTAGE=$(awk "BEGIN {print (($TOTAL_PKTS/$TOTAL_GLOBAL_PKTS)*100)}")
  echo "${region}'s total packets: $(printf "%'d" $TOTAL_PKTS) ($(printf "%.2f\n" $PERCENTAGE)% of all regions)"
  
  TOTAL_TCP=$(awk '$3 == "TCP" { count++ } END { print count }'  $tmp_stats_file)
  TCP_PERCENTAGE_VS_TOTAL=$(awk "BEGIN {print (($TOTAL_TCP/$TOTAL_PKTS)*100)}")
  echo "${region}'s total TCP packets: $(printf "%'d" $TOTAL_TCP) ($(printf "%.2f\n" $TCP_PERCENTAGE_VS_TOTAL)% of all ${region}'s packets)"
  
  TOTAL_TCP_UNIQUE_CONNS=$(awk '$3 == "TCP" && $4 == "IS_TCP_SYN" { count++ } END { print count }' $tmp_stats_file)
  TCP_UNIQUE_CONNS_PERCENTAGE_VS_TOTAL=$(awk "BEGIN {print (($TOTAL_TCP_UNIQUE_CONNS/$TOTAL_PKTS)*100)}")
  echo "${region}'s total TCP unique connections: $(printf "%'d" $TOTAL_TCP_UNIQUE_CONNS) ($(printf "%.2f\n" $TCP_UNIQUE_CONNS_PERCENTAGE_VS_TOTAL)% of all ${region}'s packets)"
  
  TOTAL_UDP=$(awk '$3 == "UDP" { count++ } END { print count }'  $tmp_stats_file)
  UDP_PERCENTAGE_VS_TOTAL=$(awk "BEGIN {print (($TOTAL_UDP/$TOTAL_PKTS)*100)}")
  echo "${region}'s total UDP packets: $(printf "%'d" $TOTAL_UDP) ($(printf "%.2f\n" $UDP_PERCENTAGE_VS_TOTAL)% of all ${region}'s packets)"
  
  TOTAL_ICMP=$(awk '$3 == "ICMPV4" { count++ } END { print count }'  $tmp_stats_file)
  ICMP_PERCENTAGE_VS_TOTAL=$(awk "BEGIN {print (($TOTAL_ICMP/$TOTAL_PKTS)*100)}")
  echo "${region}'s total ICMP packets: $(printf "%'d" $TOTAL_ICMP) ($(printf "%.2f\n" $ICMP_PERCENTAGE_VS_TOTAL)% of all ${region}'s packets)"
  
  TOP20_SRC_IPS=$(awk '{print $1}' $tmp_stats_file | sort | uniq -c | sort -nr | head -20)
  echo -e "${region}'s TOP 20 SRC IPs:\n $TOP20_SRC_IPS" 
   
  TOP20_TCP_PORTS=$(awk '$3 == "TCP" { print $2 }'  $tmp_stats_file | sort | uniq -c | sort -nr | head -20)
  echo -e "${region}'s TOP 20 TCP PORTS:\n $TOP20_TCP_PORTS"

  TOP20_UDP_PORTS=$(awk '$3 == "UDP" { print $2 }' $tmp_stats_file | sort | uniq -c | sort -nr | head -20)
  echo -e "${region}'s TOP 20 UDP PORTS:\n $TOP20_UDP_PORTS"
}

# Generates regional stats. The resulting files are going to be located in each region's directory.
for subdir in merges/*; do
  stats_out_file="$subdir/$(basename -- $subdir)_stats.txt"
  rm -f $stats_out_file
  for f in $subdir/*.pcap; do
    echo "[$(date +%H:%M:%S)] Generating stats for $(basename -- $subdir)..."
    fetch_statistics >> $stats_out_file
  done;
done;

# Generates global stats. The resulting file will be located in the root of your working directory (./global_stats.txt)
echo "[$(date +%H:%M:%S)] Calculating global stats..."
generate_global_stats > ./global_stats.txt

# Cleaning your working directory.
echo "[$(date +%H:%M:%S)] Deleting temporary files... The deleted files are going to be listed below."
find . -type f -name "${TMP_STATS_FILENAME}*" ! -name '*.pcap' ! -name '*.txt' -delete -print
