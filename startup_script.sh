#!/bin/sh

# Tells the Linux kernel to disable the implementation of the IPv6 protocol, since IPv6 is out of the scope of this project.
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1

# Move the SSH port to another one, out of our 'researching range'.
sed -i 's/#Port 22/Port 65535/' /etc/ssh/sshd_config
service sshd restart

# Ensure proper UTC time synchronization with busybox's ntpd.
setup-timezone -z UTC
setup-ntp busybox

# Install the packages we need.
apk add --no-cache tcpdump aws-cli curl jq

# Alpine's AMI packages doas instead of sudo, hence this is a helpful alias for most people.
echo 'alias sudo="doas"' >> /etc/profile

export HAPPY_ENDING_EXECUTABLE="/usr/local/bin/happy-ending"
export NET_DEV="eth0"
export TERMINATION_PROBES_EXECUTABLE="/usr/local/bin/probe-ec2-termination"
export EC2_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
export EC2_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
export FILTERED_S3_CIDR=$(curl -s https://ip-ranges.amazonaws.com/ip-ranges.json | jq -r '.prefixes[] | select(.service=="S3") | select(.region=='\"${S3_REGION}\"') | .ip_prefix' | xargs printf -- ' and not net %s ')

# Set the tcpdump filters.
TCPDUMP_FILTERS="not src net 172.16.0.0/12 and not src net 10.0.0.0/8 and not src net 192.168.0.0/16 and not net 169.254.0.0/16 and not port 65535 $FILTERED_S3_CIDR"

# Create and enable swapfile.
dd if=/dev/zero of=/swapfile bs=1024 count=1000024
chmod 0600 /swapfile
mkswap /swapfile
swapon /swapfile
# echo "/swapfile none swap defaults 0 0" >> /etc/fstab  # Potentially unnecessary. A same given instance is not supposed to reboot, ever.

# Create the script to pass into the `-z postrotate-command` tcpdump argument. This very same script will also be called when EC2 wants to terminate the instance.
# tcpdump will call this script each time it rotates (e.g. each 3600s).
cat << EOF > $HAPPY_ENDING_EXECUTABLE
#!/bin/sh

# Save instance metadata.
BASE_URL="http://169.254.169.254/latest/meta-data/"
for metadata in \$(curl -s \$BASE_URL); do
  if [ "\$${metadata: -1}" != "/" ]; then
    echo "\$metadata is \$(curl -s \$BASE_URL/\$metadata)" >> \$1.txt
  fi
done
echo "Dropped packets: " \$(grep $NET_DEV /proc/net/dev | awk '{print \$5}') >> \$1.txt

gzip \$1
aws s3 mv \$(dirname \$1 | tail -1) s3://${S3_NAME}/ --recursive --exclude "*" --include "\$1*"

EOF
chmod +x $HAPPY_ENDING_EXECUTABLE

# Create and run the script responsible for probing AWS APIs to check if a termination is about to happen.
cat << EOF > $TERMINATION_PROBES_EXECUTABLE
#!/bin/sh
while sleep 10; do
    # It returns 200 if there's a termination about to happen.
    HTTP_STATUS=\$(curl -s -w %\{http_code} -o /dev/null http://169.254.169.254/latest/meta-data/spot/instance-action)

    if [[ "\$HTTP_STATUS" -eq 200 ]] ; then
        killall -TERM tcpdump
        break
    fi
done
EOF
chmod +x $TERMINATION_PROBES_EXECUTABLE

# The line below starts, in the background, the script responsible for probing AWS APIs to check if a termination is about to happen.
./$TERMINATION_PROBES_EXECUTABLE &

# The first line below forces tcpdump to run until it exits successfully or receives a legitimate interruption.
# The last line will run when tcpdump exits for whatever reason, either by legitimate interruption (likely/expected) or anything that caused a successful exit code. 
# "/tmp/*pcap" is safe to pass as there will be only the last file, from the ongoing rotation, every past rotation has already gzipped, uploaded and deleted their respective files.
until tcpdump -G 3600 -i $NET_DEV -z $HAPPY_ENDING_EXECUTABLE -w /tmp/$EC2_ZONE\_$EC2_IP\_\%Y−\%m−\%d_\%H-00-00.pcap $TCPDUMP_FILTERS; do sleep 5; done;
./$HAPPY_ENDING_EXECUTABLE $(ls /tmp/*pcap)