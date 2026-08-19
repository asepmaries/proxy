# proxy

One-command Squid HTTP proxy installer for Ubuntu VPS.

The default proxy port is `443`, which is commonly allowed by cloud firewalls.
The listener uses the HTTP proxy protocol (not an HTTPS website), so configure
clients with an `http://` proxy URL even though the port is 443.

Default credentials:

```text
Username: wdp
Password: Extra0109
```

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/asepmaries/proxy/main/install.sh | sudo bash
```

After install, the script prints:

```text
Host IP:Port@Username:Password
```

The same result is saved to:

```text
/root/proxy.txt
```

## Custom Password

```bash
curl -fsSL https://raw.githubusercontent.com/asepmaries/proxy/main/install.sh | sudo env PROXY_PASS='yourStrongPassword' bash
```

## Custom User, Password, Port

```bash
curl -fsSL https://raw.githubusercontent.com/asepmaries/proxy/main/install.sh | sudo env PROXY_USER='wdp' PROXY_PASS='yourStrongPassword' PROXY_PORT='8080' bash
```

If port `443` is occupied by the known `wdp-ssh-443.service`, the installer
checks that the main SSH listener on port `22` is active, disables the extra SSH
service, and then continues installing Squid automatically. Other port
conflicts still stop the installer without changing the conflicting service.

The installer waits up to 10 minutes by default when Ubuntu's
`unattended-upgrades` process holds the apt/dpkg lock. Temporary D-Bus resets
during `systemctl enable` or `systemctl restart` are retried automatically.
The wait can be changed with `APT_LOCK_TIMEOUT`, in seconds.

## Restrict Source IP

Default allows any source IP, but requires username and password.

To allow only one source IP:

```bash
curl -fsSL https://raw.githubusercontent.com/asepmaries/proxy/main/install.sh | sudo env ALLOW_CIDR='1.2.3.4/32' bash
```

## Test

Replace values with the output from installer:

```bash
curl -x http://USERNAME:PASSWORD@HOST:PORT https://api.ipify.org
```

The installer also performs an authenticated request through Squid locally. If
that passes but a test from your computer times out, allow inbound TCP traffic
to the proxy port in the VPS provider's firewall or security group. Operating
system firewall rules alone cannot open an AWS, GCP, or Azure cloud firewall.

## Supported OS

Tested target:

- Ubuntu 22.04
- Ubuntu 24.04
