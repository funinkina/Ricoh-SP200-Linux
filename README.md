# Ricoh SP 200 CUPS Driver (Linux & macOS)

## About

The Ricoh SP 200 is a cheap monochrome laser printer. It only ships with a Windows driver, and you won't find it in foo2zjs, OpenPrinting, HPLIP or Gutenprint.

This repo is a native CUPS driver for it, written from scratch by capturing the Windows driver's USB traffic. After installing, the printer appears in every app's normal Print dialog.

- Works over USB on Linux and macOS
- A4 and Letter, multi-page jobs, multiple copies
- Can be shared over the network, e.g. to print from Android

To learn how the protocol was decoded, see [docs/REVERSE_ENGINEERING.md](docs/REVERSE_ENGINEERING.md).

## Installation

Plug the printer in over USB and switch it on first.

### macOS

```bash
git clone https://github.com/funinkina/Ricoh-SP200-Linux
cd Ricoh-SP200-Linux
./install-macos.sh
```

The installer walks you through everything: it builds the driver, installs it, adds the printer, and can print a test page. You only need Xcode Command Line Tools (the script offers to install them) and your password. To remove the driver later, run `./install-macos.sh --uninstall`.

### Linux

Install the dependencies:

```bash
sudo pacman -S cups ghostscript jbigkit                                            # Arch
sudo apt install libcups2-dev libcupsimage2-dev libjbig-dev gcc ghostscript        # Debian / Ubuntu
sudo dnf install cups-devel jbigkit-devel gcc ghostscript                          # Fedora
```

Then build, install, and add the printer:

```bash
git clone https://github.com/funinkina/Ricoh-SP200-Linux
cd Ricoh-SP200-Linux
sudo make install      # build and install the filter + PPD
sudo make register     # add the printer to CUPS
echo "Hello" | lpr -P Ricoh_SP_200_DDST
```

To remove it, run `sudo make uninstall`.

---

## Sharing the Printer Over the Network (Android / Other Devices)

The CUPS filter runs only on Linux or macOS — it cannot run on Android or other devices directly. Instead, share the printer from the Linux machine over IPP. Android (4.4+) supports IPP natively and requires no extra app.

### Step 1 — Allow network access in CUPS

Edit `/etc/cups/cupsd.conf`:

```
# Change:
Listen localhost:631
# To:
Port 631

# Also add:
ServerAlias *
```

Add `Allow @LOCAL` to the relevant `<Location>` blocks:

```
<Location />
  Order allow,deny
  Allow @LOCAL
</Location>

<Location /admin>
  Order allow,deny
  Allow @LOCAL
</Location>

<Location /printers>
  Order allow,deny
  Allow @LOCAL
</Location>
```

### Step 2 — Restart CUPS and share the printer

```bash
sudo systemctl restart cups
sudo lpadmin -p Ricoh_SP_200_DDST -o printer-is-shared=true
sudo cupsctl --share-printers
```

### Step 3 — Open the firewall on port 631

```bash
# ufw
sudo ufw allow 631/tcp

# firewalld
sudo firewall-cmd --permanent --add-service=ipp && sudo firewall-cmd --reload
```

### Step 4 — Add the printer on Android

1. **Settings → Connected devices → Printing → Default Print Service**
2. The printer should auto-discover as `Ricoh_SP_200_DDST`.
3. If not, tap **Add printer** and enter the IPP URL manually:
   ```
   ipp://<linux-machine-ip>:631/printers/Ricoh_SP_200_DDST
   ```

Both devices must be on the same local network. Android sends a standard IPP job to CUPS, which runs it through the `rastertoricohjbig` filter and forwards the PJL+JBIG1 stream to the printer via USB — identical to printing from the Linux machine directly.

---

## Troubleshooting

**Printer not found by `lpinfo -v`**
```bash
lsusb | grep -i ricoh
```

**Filter not invoked (job disappears silently)**
```bash
ls -la /usr/lib/cups/filter/rastertoricohjbig
# Must be: -rwxr-xr-x root root
sudo chmod 755 /usr/lib/cups/filter/rastertoricohjbig
sudo chown root:root /usr/lib/cups/filter/rastertoricohjbig
```

**CUPS shows printer stopped**
```bash
sudo cupsenable Ricoh_SP_200_DDST
sudo cupsaccept Ricoh_SP_200_DDST
```

**Check CUPS error log**
```bash
sudo tail -40 /var/log/cups/error_log
```

**Build fails — missing jbig.h**
```bash
# Arch:   sudo pacman -S jbigkit
# Debian: sudo apt install libjbig-dev
# Fedora: sudo dnf install jbigkit-devel
```

**macOS: installer says printer not found**
```bash
ioreg -p IOUSB -l -w0 | grep -i '"SP 200"'   # is it on USB at all?
lpinfo -v | grep -i ricoh                    # does CUPS see it?
```
The printer drops off USB when switched off or asleep — power-cycle it and press Enter in the installer.
