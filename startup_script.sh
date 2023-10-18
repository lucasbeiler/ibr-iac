#!/bin/sh

# Tells the Linux kernel to disable the implementation of the IPv6 protocol, since IPv6 is out of the scope of this project.
# Other unwanted things are also disabled.
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1
sysctl -w kernel.unprivileged_userns_clone=0

# Install all the needed packages.
apk add --no-cache tcpdump aws-cli curl jq # haproxy docker

# Move the SSH port to another one, out of our 'researching range'.
sed -i 's/#Port 22/Port 65535/' /etc/ssh/sshd_config
rc-service sshd restart

# Ensure proper UTC time synchronization with busybox's ntpd.
setup-timezone -z UTC
sed -i 's/pool.ntp.org/169.254.169.123/' /etc/conf.d/ntpd
setup-ntp busybox

# Alpine's AMI packages doas instead of sudo, hence this is a helpful alias for most people.
echo 'alias sudo="doas"' >> /etc/profile

export HAPPY_ENDING_EXECUTABLE="/usr/local/bin/happy-ending"
export TERMINATION_PROBES_EXECUTABLE="/usr/local/bin/probe-ec2-termination"
export EC2_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
export EC2_IP_PRIVATE=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
export EC2_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
export NET_DEV="eth0"
export ROTATION_PERIOD_SEC="86400" # 24 hours
export SAVE_DIR="/tmp"

# Composing the tcpdump filter.
export RFC1918_ADDRESSES="not src net 172.16.0.0/12 and not src net 10.0.0.0/8 and not src net 192.168.0.0/16"
export LINK_LOCAL="not net 169.254.0.0/16"
export LEGITIMATE_SSH_PORT="not port 65535"
# Copying data to S3 generates traffic to the S3 APIs in the bucket's respective region, this needs to be filtered.
export FILTERED_S3_CIDR=$(curl -s https://ip-ranges.amazonaws.com/ip-ranges.json | jq -r '.prefixes[] | select(.service=="S3") | select(.region=='\"${S3_REGION}\"') | .ip_prefix' | xargs printf -- ' and not net %s ')

# Set the tcpdump filters.
TCPDUMP_FILTERS="$RFC1918_ADDRESSES and $LINK_LOCAL and $LEGITIMATE_SSH_PORT $FILTERED_S3_CIDR"
# TCPDUMP_FILTERS="$LINK_LOCAL and $LEGITIMATE_SSH_PORT $FILTERED_S3_CIDR"

# Create and enable swapfile.
dd if=/dev/zero of=/swapfile bs=1024 count=1000024
chmod 0600 /swapfile
mkswap /swapfile
swapon /swapfile

# Create the script to pass into the `-z postrotate-command` tcpdump argument. This very same script will also be called when EC2 wants to terminate the instance.
# tcpdump will call this script every time it rotates (e.g. each 3600s).
cat << EOF > $HAPPY_ENDING_EXECUTABLE
#!/bin/sh

# When no specific file is passed, deal with every PCAP file in SAVE_DIR to address potential dangling files.
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
  echo "Rotation killed by: \$(ps -o pid,comm | grep \$PPID | awk '{ print \$2 }')" >> \$f.txt
  echo "Spot terminating: \$(ls /tmp/spot_term >/dev/null 2>&1 && echo yes || echo no)" >> \$f.txt

  # Gzip and upload data.
  gzip \$f
  aws s3 mv \$(dirname \$f) s3://${S3_NAME}/ --recursive --exclude "*" --include "\$f*" --region ${S3_REGION}
done
EOF
chmod +x $HAPPY_ENDING_EXECUTABLE

# Create the rc-service responsible for wrapping and supervisioning tcpdump.
cat << EOF > /etc/init.d/tcpdumpd
#!/sbin/openrc-run
name="tcpdumpd"
description="tcpdump running as a supervised daemon"

# supervise-daemon is able to handle unexpected terminations of a given command, further improving reliability.
supervisor="supervise-daemon"
command="/usr/bin/tcpdump"
command_args="-G $ROTATION_PERIOD_SEC -i $NET_DEV -z $HAPPY_ENDING_EXECUTABLE -w $SAVE_DIR/$EC2_ZONE-$EC2_IP-\%Y\%m\%d-\%H\%M.pcap $TCPDUMP_FILTERS"
pidfile=/run/tcpdumpd.pid

# stop_post runs right after the rc-service is stopped, whether it was stopped by someone or by the system shutdown procedure.
stop_post()
{
  $HAPPY_ENDING_EXECUTABLE
}
EOF
chmod +x /etc/init.d/tcpdumpd
rc-update  add tcpdumpd default
rc-service tcpdumpd start

# Create and run the script responsible for probing AWS APIs to check if a termination is about to happen. It will be called by crond.
cat << EOF > $TERMINATION_PROBES_EXECUTABLE
#!/bin/sh

# It returns 200 if there's a termination about to happen.
HTTP_STATUS=\$(curl -s -w %\{http_code} -o /dev/null http://169.254.169.254/latest/meta-data/spot/instance-action)

if [[ "\$HTTP_STATUS" -eq 200 ]]; then
  touch /tmp/spot_term
  rc-service tcpdumpd stop
fi
EOF
chmod +x $TERMINATION_PROBES_EXECUTABLE
echo "*	*	*	*	*	$TERMINATION_PROBES_EXECUTABLE" >> /etc/crontabs/root
rc-update  add crond default
rc-service crond start