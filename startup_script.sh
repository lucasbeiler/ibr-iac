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

# Install all the needed packages.
apk add --no-cache tcpdump aws-cli curl jq

# Alpine's AMI packages doas instead of sudo, hence this is a helpful alias for most people.
echo 'alias sudo="doas"' >> /etc/profile

export HAPPY_ENDING_EXECUTABLE="/usr/local/bin/happy-ending"
export TERMINATION_PROBES_EXECUTABLE="/usr/local/bin/probe-ec2-termination"
export EC2_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
export EC2_IP_PRIVATE=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
export EC2_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
export NET_DEV="eth0"
export ROTATION_PERIOD_SEC="43200" # 12 hours.
export SAVE_DIR="/tmp"

# Composing the tcpdump filter.
# Copying data to S3 generates traffic to the S3 APIs in the bucket's respective region, this needs to be filtered.
# Link-local, AWS APIs and the legitimate SSH port used for administration are never useful to capture, so deny them no matter what.
export DENY_LINK_LOCAL="not net 169.254.0.0/16"
export DENY_LEGITIMATE_SSH_PORT="not port 65535"
export DENY_S3_REGION_CIDR=$(curl -s https://ip-ranges.amazonaws.com/ip-ranges.json | jq -r '.prefixes[] | select(.service=="S3") | select(.region=='\"${S3_REGION}\"') | .ip_prefix' | xargs printf -- ' and not net %s ')

# For packets where the machine is the destination, the source cannot be an internal/local address (RFC-1918).
# Useful to capture packets from the Internet to the machine.
export ALLOW_HOST_AS_DST="dst host $EC2_IP_PRIVATE"
export DENY_RFC1918_ADDRESSES_AS_SRC="not src net 172.16.0.0/12 and not src net 10.0.0.0/8 and not src net 192.168.0.0/16"

# For packets where the machine is the source address, the destination cannot be an internal/local address (RFC-1918).
# Useful to capture packets from the machine to the Internet, but only responses are desired. 
# (TODO: Make sure EC2, Alpine Linux or any services running on the machine DO NOT ACTIVELY ESTABLISH connections to servers on the Internet!!!).
export ALLOW_HOST_AS_SRC="src host $EC2_IP_PRIVATE"
export DENY_RFC1918_ADDRESSES_AS_DST="not dst net 172.16.0.0/12 and not dst net 10.0.0.0/8 and not dst net 192.168.0.0/16"

# Set the tcpdump filters.
TCPDUMP_FILTERS="($DENY_LINK_LOCAL and $DENY_LEGITIMATE_SSH_PORT  $DENY_S3_REGION_CIDR) and (($ALLOW_HOST_AS_DST and $DENY_RFC1918_ADDRESSES_AS_SRC) or ($ALLOW_HOST_AS_SRC and $DENY_RFC1918_ADDRESSES_AS_DST))"

# Create and enable swapfile.
dd if=/dev/zero of=/swapfile bs=1024 count=1000024
chmod 0600 /swapfile
mkswap /swapfile
swapon /swapfile

# Create the script to pass into the `-z postrotate-command` tcpdump argument. This very same script will also be called when EC2 wants to terminate the instance.
# tcpdump will call this script every time it rotates (e.g. each 3600s).
cat << EOF > $HAPPY_ENDING_EXECUTABLE
#!/bin/sh

# If there is no valid argument passed, the script will try to find the file.
if [[ -f "\$1" ]]; then
  CURRENT_PCAP_OR_PCAPS=\$1
else
  CURRENT_PCAP_OR_PCAPS=\$(ls $SAVE_DIR/*pcap)
fi

# Fails if there is nothing to handle.
[[ -z "\$CURRENT_PCAP_OR_PCAPS" ]] && exit 1

# Exclusive lock handling with flock -x.
exec 8>/var/lock/\$(basename "\$0").lock
flock -n -x 8 || exit 1;

# Dealing with the possibility of multiple files because.
# If tcpdump failed multiple times before the rotation ends or before either the daemon or the instance are terminated, there will be multiple files to deal with, as OpenRC would have restarted it multiple times already.
for f in \$CURRENT_PCAP_OR_PCAPS; do
  # Save instance metadata and general debugging information.
  BASE_URL="http://169.254.169.254/latest/meta-data/"
  for metadata in \$(curl -s \$BASE_URL); do
    if [ "\$${metadata: -1}" != "/" ]; then
      echo "\$metadata is \$(curl -s \$BASE_URL/\$metadata)" >> \$f.txt
    fi
  done
  echo "Dropped packets: \$(grep $NET_DEV /proc/net/dev | awk '{print \$5}')" >> \$f.txt
  echo "tcpdumpd status: \$(rc-service tcpdumpd status)" >> \$f.txt

  # Gzip and upload data.
  gzip \$f
  aws s3 mv \$(dirname \$f) s3://${S3_NAME}/ --recursive --exclude "*" --include "\$f*"
done
EOF
chmod +x $HAPPY_ENDING_EXECUTABLE

# Create and run the script responsible for probing AWS APIs to check if a termination is about to happen. It will be called by cron every minute.
cat << EOF > $TERMINATION_PROBES_EXECUTABLE
#!/bin/sh

# It returns 200 if there's a termination about to happen.
HTTP_STATUS=\$(curl -s -w %\{http_code} -o /dev/null http://169.254.169.254/latest/meta-data/spot/instance-action)

if [[ "\$HTTP_STATUS" -eq 200 ]]; then
  rc-service tcpdumpd stop
fi
EOF
chmod +x $TERMINATION_PROBES_EXECUTABLE
echo "*	*	*	*	*	$TERMINATION_PROBES_EXECUTABLE" >> /etc/crontabs/root
rc-update  add crond default
rc-service crond start

# Create the service responsible for wrapping and supervisioning tcpdump.
cat << EOF > /etc/init.d/tcpdumpd
#!/sbin/openrc-run
name="tcpdumpd"
description="tcpdump running as a supervised daemon"

# supervise-daemon is able to handle unexpected terminations of a given command, further improving reliability.
supervisor="supervise-daemon"
command="/usr/bin/tcpdump"
command_args="-G $ROTATION_PERIOD_SEC -i $NET_DEV -z $HAPPY_ENDING_EXECUTABLE -w $SAVE_DIR/$EC2_ZONE-$EC2_IP-\%Y\%m\%d-\%H\%M.pcap $TCPDUMP_FILTERS"
pidfile=/run/tcpdumpd.pid

# stop_post runs right after the service is stopped, whether it was stopped by someone or by the system shutdown procedure.
stop_post()
{
  $HAPPY_ENDING_EXECUTABLE
}
EOF
chmod +x /etc/init.d/tcpdumpd
rc-update  add tcpdumpd default
rc-service tcpdumpd start