## IMPORTANT
1. Copy all *.pcap.gz files from the AWS S3 bucket to a local directory. From now on we will refer to this directory as the working directory.
2. **BACKUP:** Now this is important. Copy the working directory somewhere safe now, before making any changes to it.

### post_processing.sh
The script takes only one argument, which is the path to the working directory.

In order to run the script, do the following:
1. Download all the files from the S3 bucket to a local directory.
2. Make a copy of that local directory to a safe place to avoid having to download it again in case something goes wrong.
3. Run the post_processing script passing the working directory as an argument: `./post_processing.sh ~/path/to/the/working/directory/`.
4. When the script is done running, your working directory is fine to be shared with your researching group.


This script automatically:
1. Delete empty files;
2. Gunzip all PCAP files;
3. Rewrite the files to replace the EC2 local IPs with the respective public IP address of each instance;
4. Combine all files from each region into one large file per region.

You can also edit the script to change its behavior when necessary.

### to_csv.sh
The script takes only one argument, which is the path to the working directory.
This script will get certain fields from all the PCAPs in the working directory into a large CSV file that you can then import into some database, data lake, or any type of data analytics facility capable of importing CSV files.

You can also edit the script to change the fields yourself when necessary.
Run the to_csv.sh script with: `./to_csv.sh ~/path/to/the/working/directory/`.