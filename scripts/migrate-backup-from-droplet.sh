#!/usr/bin/env bash
# Rode NO DROPLET de origem (ex.: 167.99.157.167) como root, dentro do diretório do compose.
set -euo pipefail

OUT_DIR="${1:-/root/evolution-migrate-backup-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT_DIR"

echo "==> Salvando .env e compose"
for f in .env docker-compose.yml docker-compose.prod.yml; do
  [ -f "$f" ] && cp -a "$f" "$OUT_DIR/"
done

echo "==> docker compose ps"
docker compose ps 2>/dev/null || docker ps

echo "==> Dump Postgres (evogo_auth + evogo_users)"
PG_USER="${POSTGRES_USER:-postgres}"
for db in evogo_auth evogo_users; do
  docker exec evolution-postgres pg_dump -U "$PG_USER" -Fc "$db" >"$OUT_DIR/${db}.dump" 2>/dev/null \
    || echo "WARN: dump $db falhou (container ou DB ausente?)"
done

echo "==> Volume evolution_data (sessões WhatsApp)"
EVO_VOL="$(docker volume inspect evolution_data -f '{{.Mountpoint}}' 2>/dev/null || true)"
if [ -n "$EVO_VOL" ] && [ -d "$EVO_VOL" ]; then
  tar -C "$EVO_VOL" -czf "$OUT_DIR/evolution_data.tgz" .
else
  docker run --rm -v evolution_data:/data -v "$OUT_DIR":/backup alpine \
    tar -czf /backup/evolution_data.tgz -C /data . 2>/dev/null \
    || echo "WARN: backup evolution_data falhou"
fi

ARCHIVE="${OUT_DIR}.tgz"
tar -C "$(dirname "$OUT_DIR")" -czf "$ARCHIVE" "$(basename "$OUT_DIR")"
echo "==> Pronto: $ARCHIVE"
echo "Baixe com: scp root@SEU_IP:$ARCHIVE ."