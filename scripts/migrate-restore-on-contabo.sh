#!/usr/bin/env bash
# Rode na Contabo em /opt/evolution-go, com o .tgz do backup já copiado.
set -euo pipefail

ARCHIVE="${1:?Uso: $0 evolution-migrate-backup-....tgz}"
cd /opt/evolution-go

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
tar -xzf "$ARCHIVE" -C "$WORKDIR"
BUNDLE="$(find "$WORKDIR" -mindepth 1 -maxdepth 1 -type d | head -1)"

[ -f "$BUNDLE/.env" ] && cp -a "$BUNDLE/.env" .env
chmod 600 .env 2>/dev/null || true

# Ajustes para ambiente local (bibiloca na mesma VPS)
if grep -q '^WADEBUG=DEBUG' .env 2>/dev/null; then
  sed -i 's/^WADEBUG=DEBUG/WADEBUG=INFO/' .env
fi

docker compose -f docker-compose.prod.yml up -d postgres
echo "Aguardando Postgres..."
sleep 8

PG_PASS="$(grep '^POSTGRES_PASSWORD=' .env | cut -d= -f2- | tr -d '"' || echo postgres)"
export PGPASSWORD="$PG_PASS"

for db in evogo_auth evogo_users; do
  DUMP="$BUNDLE/${db}.dump"
  if [ -f "$DUMP" ]; then
    docker exec -i evolution-postgres psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname='$db'" | grep -q 1 \
      || docker exec -i evolution-postgres createdb -U postgres "$db"
    docker exec -i evolution-postgres pg_restore -U postgres -d "$db" --clean --if-exists <"$DUMP" \
      || docker cp "$DUMP" evolution-postgres:/tmp/restore.dump \
        && docker exec evolution-postgres pg_restore -U postgres -d "$db" --clean --if-exists /tmp/restore.dump
    echo "Restored $db"
  fi
done

if [ -f "$BUNDLE/evolution_data.tgz" ]; then
  docker compose -f docker-compose.prod.yml up -d evolution-go
  sleep 3
  docker run --rm \
    -v evolution-go_evolution_data:/data \
    -v "$BUNDLE":/backup \
    alpine sh -c 'rm -rf /data/* /data/.[!.]* 2>/dev/null; tar -xzf /backup/evolution_data.tgz -C /data'
  echo "Restored evolution_data volume"
fi

docker compose -f docker-compose.prod.yml up -d
docker compose -f docker-compose.prod.yml ps
echo "Teste: curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:4000/"