#!/bin/bash
# 1. Update and install Apache
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd

# 2. Get the Instance Metadata
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

HOSTNAME=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/hostname)

IP_ADDRESS=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/local-ipv4)

# 3. Create the HTML page
cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>AltSchool Africa - Cloud Lab</title>
<style>
    body { 
        font-family: 'Segoe UI', Arial, sans-serif; 
        text-align: center; 
        margin: 0;
        padding-top: 50px; 
        /* Your background gradient */
        background: linear-gradient(135deg, #1D2791 0%, #512888 100%); 
        min-height: 100vh;
        color: white; /* Makes all text white by default */
    }

    .card { 
        /* Semi-transparent dark purple background */
        background: rgba(255, 255, 255, 0.1); 
        padding: 40px; 
        border-radius: 15px; 
        display: inline-block; 
        /* Glass effect: blurs what is behind the card */
        backdrop-filter: blur(10px);
        -webkit-backdrop-filter: blur(10px);
        border: 1px solid rgba(255, 255, 255, 0.2);
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
        max-width: 80%;
    }

    h1 { 
        color: #ffffff; /* White for the name */
        margin-bottom: 10px;
    }

    hr {
        border: 0;
        height: 1px;
        background: rgba(255, 255, 255, 0.3);
        margin: 20px 0;
    }

    .info { 
        /* Neon pink/magenta to pop against the blue/purple */
        color: #ff00ff; 
        font-weight: bold; 
        font-family: monospace; /* Professional 'Cloud' look for IPs */
    }

    p {
        color: rgba(255, 255, 255, 0.8);
    }
</style>

</head>
<body>
    <div class='card'>
        <h1>Odo Kingsley Uchenna</h1>
        <p>Cloud Engineering Student - <strong>AltSchool Africa</strong></p>
        <P>Currently on my final semester, specializing in Cloud Engineering.</p>
        <p>I have a strong passion for cloud technologies and am eager to apply my skills in real-world projects.</p>

        <hr>
        <P>Welcome to my personal lab project page!</p>
        <p>This is my personal lab project: 3-Tier Architecture via Terraform</p>
        <p><strong>Current Instance Hostname:</strong> <span class='info'>$HOSTNAME</span></p>
        <p><strong>Current Instance Private IP:</strong> <span class='info'>$IP_ADDRESS</span></p>
    </div>
</body>
</html>
EOF

# 4. Ensure permissions are correct for Apache to read the file
chown apache:apache /var/www/html/index.html