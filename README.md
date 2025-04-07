k3s Setup Script
Disclaimer:
This script has only been tested on a clean installation of Ubuntu Server 24.04.1 LTS. Use at your own risk.

How to Get the Script
You have two options to obtain the script:

Option 1: Download via cURL
Use the following command to download the script directly:
curl -O https://github.com/0xh34z/k3s-setup-script/blob/main/script.sh
Note: The -O flag saves the file with its original name.

Option 2: Copy-Paste & Execute
SSH into your server:
ssh username@host_or_ip
Replace username with your actual username and host_or_ip with the server's address.

Open a new file to paste the script:
sudo nano script.sh
Paste the script contents into the editor and then save the file by pressing Ctrl + O and exit with Ctrl + X.

Make the script executable:
sudo chmod +x script.sh

Run the script:
sudo ./script.sh
