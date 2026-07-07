# proxy

One-command Squid HTTP proxy installer for Ubuntu VPS.

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

## Supported OS

Tested target:

- Ubuntu 22.04
- Ubuntu 24.04
