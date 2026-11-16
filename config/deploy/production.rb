# Dedicated Muzeum identity/path are proposed, not provisioned. Never use admin/deploy
# as an implicit fallback. Port 3011 was free during read-only inventory.
server "88.99.245.24", user: "muzeum", roles: %w[app web db]
