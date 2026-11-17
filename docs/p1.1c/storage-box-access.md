# Storage Box SSH access preparation

The user confirmed the dedicated server is FSN1-DC1, Falkenstein, Germany, and the planned Storage Box is `harvj-backups`, BX11 (1 TB), Helsinki, Finland. The Box has not yet been ordered. No purchase or Storage Box account provisioning is authorized by key preparation.

Under explicit authorization, generated one dedicated OpenSSH Ed25519 key pair on `harvj` (88.99.245.24). Existing-key paths were checked; key generation refused overwrites and final files were created exclusively. The server's existing SSH host identity was checked with StrictHostKeyChecking=yes.

- Private key: `/etc/harvj-backups/ssh/hetzner-storagebox-ed25519`, root:root, mode **0600**.
- Public key: same path with `.pub`, root:root, mode **0644**.
- Parent directories `/etc/harvj-backups` and `/etc/harvj-backups/ssh`: root:root, mode **0700**.
- Fingerprint: `SHA256:NtEhgkaarLWWGwv2bxOT3FQW0+TaGsu1siHssznlkOY` (256-bit Ed25519).
- Comment: `harvj-backups Storage Box bootstrap key on harvj FSN1-DC1`.

Verified the public key with ssh-keygen and verified that its key material matches the public half derived from the private key entirely on the server. Only the public key and metadata were returned; private material was never displayed, copied off-host or committed. The dedicated unattended key has no passphrase and is protected by root-only directory traversal and file permissions. No service account or new privilege grant was needed.

This is a Storage Box bootstrap/access key, not permission to share one key across future applications. Each application's subaccount/repository still needs its own credentials and Restic password when provisioned. Keep Storage Box account/snapshot-management credentials outside the application server.

Exact server changes: the two new protected directories and this key pair only. No existing key, application credential, backup job, service, SSH configuration, DNS or database was changed. No Storage Box connection attempted. Subsequent repository access/host-key verification, backup installation and restore proof remain pending the Box and isolated subaccounts. Muzeum deployment remains unapproved.
