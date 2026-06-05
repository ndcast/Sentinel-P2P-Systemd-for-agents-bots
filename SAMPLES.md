# DVPN Script Output Samples

Example output from each script for reference and testing.

---

## sentinel-balance.sh

```
user@jumpbox:~$ bash sentinel-balance.sh
=== Fetching real balance via LCD API ===
142686813 udvpn = 142.686813 DVPN

→ Explorer: https://p2pscan.com/address/sent1325rxxxxxxxxxxxxxxxxxxxxxxxxxmz3t9
```

---

## sentinel-countdown.sh

```
user@jumpbox:~$ bash sentinel-countdown.sh
=== Sentinel Stale Sessions & Balance ===
142686813 udvpn = 142.686813 DVPN
→ Full balance & history: https://p2pscan.com/address/sent1235xxxxxxxxxxxxxxx9


=== Time until refunds ===

Session 4.262662e+07 → expires at 01:15:20 (50 min left)
Session 4.2626752e+07 → expires at 01:16:08 (51 min left)
Session 4.2626761e+07 → expires at 01:21:22 (56 min left)

=== Summary ===
• Tokens locked in inactive_pending sessions
• Deposits return automatically when timers hit 0
• Refresh p2pscan after sessions disappear from the list
user@jumpbox:~$
```

---

## sentinel-select-best-node.sh

```
user@admin-jumpbox:~$ bash sentinel-select-best-node.sh
[2026-05-26 00:26:20] === Selecting Best Node (NL\/DE\/FR) ===
[2026-05-26 00:26:31] ✅ Best EU node: sentnode1zxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx ()
```

---

## sentinel-cancel-session.sh

**Usage (no args):**
```
user@jumpbox:~$ bash sentinel-dvpncli/MyScripts/sentinel-cancel-session.sh
=== Sentinel Session Cancel Tool ===
Usage: sentinel-dvpncli/MyScripts/sentinel-cancel-session.sh <session_id> or sentinel-dvpncli/MyScripts/sentinel-cancel-session.sh -a
```

**Cancel all sessions:**
```
user@jumpbox:~$ bash sentinel-dvpncli/MyScripts/sentinel-cancel-session.sh -a
=== Sentinel Session Cancel Tool ===
Mode: Cancel ALL sessions
[00:27:18] Skipping 42626620 → already inactive_pending
[00:27:18] Skipping 42626752 → already inactive_pending
[00:27:18] Cancelling 42626761 → already inactive_pending
Finished. Tracked in: /home/user/sentinel-dvpncli/.sent_sessions
```


## systemd ExecStop — Clean ip rules on stop (non-root user)

When the service runs as `User=user`, add this as the **last** `ExecStop` line to remove custom WireGuard ip rules on stop:

```ini
ExecStop=/bin/bash -c 'while read x; do sudo ip rule del priority $x || true; done < <(ip rule show | grep -v "from all lookup" | cut -d: -f1)'
```

Tested working on 2026-06-02.

---

## Fully Operational Start & Stop

```
user@admin-jumpbox:~$ sudo systemctl start sentinel-favs-dvpn.service ; journalctl -fu sentinel-favs-dvpn.service
Jun 02 07:57:51 admin-jumpbox systemd[1]: Starting Sentinel dVPN Full Auto Connect — Favorite Providers...
Jun 02 07:57:51 admin-jumpbox sentinel-cancel-session.sh[36105]: === Sentinel Session Cancel Tool ===
Jun 02 07:57:51 admin-jumpbox sentinel-cancel-session.sh[36105]: Mode: Cancel ALL sessions
Jun 02 07:57:51 admin-jumpbox sentinel-cancel-session.sh[36105]: Finished. Tracked in: /home/user/sentinel-dvpncli/.sent_sessions
Jun 02 07:57:51 admin-jumpbox systemd[1]: Started Sentinel dVPN Full Auto Connect — Favorite Providers.
Jun 02 07:57:51 admin-jumpbox sentinel-connect.sh[36138]: [07:57:51] Starting Sentinel dVPN...
Jun 02 07:57:51 admin-jumpbox sentinel-connect.sh[36138]: [07:57:51] Using favorite node: sentnode1ldh7ke5x9896px23muen32twcyaykd8rf5a8hd
Jun 02 07:57:51 admin-jumpbox sentinel-connect.sh[36138]: [07:57:51] Checking balance...
Jun 02 07:57:52 admin-jumpbox sentinel-connect.sh[36138]: Balance: 1800 DVPN
Jun 02 07:57:52 admin-jumpbox sentinel-connect.sh[36138]: [07:57:52] Cancelling any existing sessions...
Jun 02 07:57:59 admin-jumpbox sentinel-connect.sh[36138]: [07:57:59] ✅ Session 43536251 created. Connecting...
Jun 02 07:57:59 admin-jumpbox sentinel-connect.sh[36138]: [07:57:59] Connect attempt 1 of 6...
Jun 02 07:57:59 admin-jumpbox sentinel-connect.sh[36204]: 2026-06-02T07:57:59Z INF Validating configuration
Jun 02 07:58:02 admin-jumpbox sentinel-connect.sh[36204]: 2026-06-02T07:58:02Z INF Setting up service
Jun 02 07:58:02 admin-jumpbox sentinel-connect.sh[36204]: 2026-06-02T07:58:02Z INF Starting service
Jun 02 07:58:02 admin-jumpbox sudo[36221]: user : PWD=/home/user ; USER=root ; COMMAND=/bin/bash -- /usr/bin/wg-quick up /home/user/sentinel-dvpncli/wireguard/wg0.conf
Jun 02 07:58:02 admin-jumpbox sudo[36221]: pam_unix(sudo:session): session opened for user root(uid=0) by (uid=1000)
Jun 02 07:58:02 admin-jumpbox sudo[36221]: pam_unix(sudo:session): session closed for user root
Jun 02 07:58:02 admin-jumpbox sentinel-connect.sh[36204]: 2026-06-02T07:58:02Z INF Client started successfully

^C
user@admin-jumpbox:~$ curl ipinfo.io
{
 "ip": "31.39.164.207",
 "city": "Paris",
 "region": "Île-de-France",
 "country": "FR",
 "org": "AS5410 Bouygues Telecom SA",
```

**Stop and verify return to normal:**
```
user@admin-jumpbox:~$ sudo systemctl stop sentinel-favs-dvpn.service
user@admin-jumpbox:~$ curl ipinfo.io
{
 "ip": "50.19.12.144",   #<< these values got changed obvioulsly
 "city": "-----",
 "region": "",
 "country": "-",
 "org": "---- OVH SAS",
```
## Example Successful Installation Output

```
========================================
  INSTALLATION COMPLETE
========================================

 Address : sent1f4k34ddr3ssxz9ql3980q6d6ypuchhchjga

 ACTION REQUIRED — FUND THIS ADDRESS

 Send DVPN tokens to:
  sent1f4k34ddr3ssxz9ql3980q6d6ypuchhchjga

Remember to :
- Add any additional IP you will SSH from to this file : ~/sentinel-dvpncli/whitelist-gws.lst
- Edit ~/sentinel-dvpncli/.country_filter to change the allowed country list.

 Once funded, test with:
   export PATH=$PATH:~/go/bin
   bash ~/sentinel-dvpncli/MyScripts/sentinel-balance.sh
   bash ~/sentinel-dvpncli/MyScripts/sentinel-connect.sh

 To enable systemd service:
   sudo systemctl enable sentinel-dvpn.service
   sudo systemctl start sentinel-dvpn.service
```


