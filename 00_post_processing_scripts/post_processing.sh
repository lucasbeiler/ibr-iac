#!/bin/bash
set -e
unalias -a

which mergecap tcprewrite tshark >/dev/null 2>&1 || { echo "You need the following binaries: tshark, mergecap and tcprewrite. They're part of Wireshark and tcpreplay suites."; exit 1; }

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

find . -type f -empty -delete # Remove empty files
echo "[$(date +%H:%M:%S)] Gunzipping files..."
gunzip -r .
rm -f *.pcap.txt # Remove debugging logs.

# Variables.
REGION_PREFIXES=$(/bin/ls *.pcap | grep -oP '^[a-z]+-[a-z]+-\d+' | sort | uniq) # Populate array with all the AWS regions.
LOCAL_CIDR="172.16.0.0/12" # This is what tcprewrite will replace with the respective public IP. Set accordingly.

# Function to rewrite PCAP files following specific criteria.
# It will rewrite each local AWS IP to the public IP associated with the current file, iteratively.
rewrite_pcap_files() {
  read -p "Do you really need to rewrite IPs now (y/N)? " -r
  [[ ! $REPLY =~ ^[Yy]$ ]] || exit
  mkdir -p rewritten
  for f in *.pcap; do
    if [ -f "$f" ]; then
      publicAddress=$(echo "$f" | grep -oP '\d+\.\d+\.\d+\.\d+')
      rm -f rewritten_file1-$f
      
      echo "[$(date +%H:%M:%S)] Rewriting destination IPs [$f]..."
      tcprewrite --fixcsum --infile=$f --outfile=rewritten_file1-$f --dstipmap=${LOCAL_CIDR}:${publicAddress} 2>/dev/null
      mv rewritten_file1-$f rewritten/$f && rm -f $f rewritten_file1-$f
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
    mv ${rp}*.pcap merges/$rp/all/
  done
}

# Main script
until rewrite_pcap_files; do echo 'Something gone wrong. Probably ran out of memory. Retrying...'; done;
until merge_per_region; do echo 'Something gone wrong. Probably ran out of memory. Retrying...'; done;
gzip -r .
