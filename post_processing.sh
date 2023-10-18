#!/bin/bash
set -e
unalias -a

if [ -d "$1" ]; then
  echo "You have set the working directory as $1."
  read -p "ENTER 'continue' IF THAT'S RIGHT AND IF YOU HAVE A BACKUP OF THESE FILES ELSEWHERE: " input
  [[ "$input" != 'continue' ]] && echo "BYE!" && exit
  cd $1
else
  echo "The directory $1 does not exist."
  echo "You should provide the directory where all your .pcap or .pcap.gz files are."
  exit 1
fi

# Variables.
REGION_PREFIXES=$(/bin/ls *.pcap | grep -oP '^[a-z]+-[a-z]+-\d+' | sort | uniq) # Fetch all the regions.
LOCAL_CIDR="172.16.0.0/12" # This is what tcprewrite will replace with the respective public IP. Set accordingly.

function remove_months_with_less_than_5_days_of_pcaps() {
  months=$(ls *.pcap* | grep -oE "[0-9]{6}" | sort | uniq)

  for month in $months; do
    days=$(ls *-$month*.pcap* | grep -oE "[0-9]{8}" | sort | uniq | wc -w)
    if [ "$days" -le 5 ]; then
      rm -f *-$month*.pcap* && echo "Removed files from $month."
    fi
  done
}

# Function to rewrite PCAP files following specific criteria.
# It will rewrite each local AWS IP to the public IP associated with the current file, iteratively.
# Additionally, it will remove HTTP, HTTPS, DoT, NTP, DNS, QUIC and ICMP responses (a plausible way to remove noise caused by responses in connections initiated by the machine itself).
rewrite_pcap_files() {
  mkdir -p rewritten
  for f in *.pcap; do
    if [ -f "$f" ]; then
      rm -f rewritten_file1-$f rewritten_file2-$f 
      publicAddress=$(echo "$f" | grep -oP '\d+\.\d+\.\d+\.\d+')
      echo "[$(date +%H:%M:%S)] Removing undesired packets from $f..."
      tshark -r $f -w rewritten_file1-$f -Y "not ((tcp.srcport eq 80 or tcp.srcport eq 443 or tcp.srcport eq 853) and tcp.dstport >= 32768) and not ((udp.srcport eq 53 or udp.srcport eq 123 or udp.srcport eq 443) and udp.dstport >= 32768) and not (icmp.type == 0 or icmp.type == 3 or icmp.type == 5 or icmp.type == 11 or icmp.type == 14)"
      echo "[$(date +%H:%M:%S)] Rewriting $f..."
      tcprewrite --fixcsum --infile=rewritten_file1-$f --outfile=rewritten_file2-$f --dstipmap=${LOCAL_CIDR}:${publicAddress} 2>/dev/null
      mv rewritten_file2-$f $f && rm -f rewritten_file1-$f
      mv $f rewritten/
    else
      echo "File $f does not exist. Skipping gracefully."
    fi
  done;

  # Now that all the iterations are done and there is nothing left to rewrite, it will move everything back here and remove the temporary "rewritten" directory.
  if [ -z "$(ls -A *.pcap 2>/dev/null)" ] && [ -n "$(ls -A ./rewritten/*.pcap 2>/dev/null)" ]; then
    mv rewritten/*.pcap . && rm -rf rewritten/
  fi
}

# Function to merge captures from each region into a single big file per region.
merge_per_region() {
  for rp in $REGION_PREFIXES; do
    mkdir -p merges/$rp/
    rm -f merges/$rp/${rp}.pcap
    echo "[$(date +%H:%M:%S)] Merging everything from $rp together..."
    mergecap -w merges/$rp/${rp}.pcap $rp*.pcap
    mkdir -p merges/$rp/all/
    mv ${$rp}*.pcap merges/$rp/all/
    gzip -r merges/$rp/
  done
}

# Main script
find . -type f -empty -delete # Remove empty files
echo "[$(date +%H:%M:%S)] Gunzipping files..."
gunzip -r .
rm -f *.pcap.txt
remove_months_with_less_than_5_days_of_pcaps

until rewrite_pcap_files; do echo 'Something gone wrong. Probably ran out of memory. Retrying...'; done;
until merge_per_region; do echo 'Something gone wrong. Probably ran out of memory. Retrying...'; done;
