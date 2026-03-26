#!/bin/bash
# Script para agregar cuentas de email al mailserver
# Uso: ./scripts/setup-mail-accounts.sh admin@tudominio.com TuPassword123
#
# Nota: Este script agrega cuentas DESPUÉS de que el contenedor está corriendo.
# Para la cuenta inicial, usa la variable MAIL_ACCOUNTS en .env

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."

if [ $# -lt 2 ]; then
    echo "=== Mailserver Account Setup ==="
    echo ""
    echo "Uso: $0 <email> <password>"
    echo "Ejemplo: $0 admin@tudominio.com SecurePass123"
    echo ""
    echo "Nota: El contenedor 'mail' debe estar corriendo."
    echo ""
    echo "Alternativa: Agrega MAIL_ACCOUNTS en .env antes del primer inicio:"
    echo "  MAIL_ACCOUNTS=admin@tudominio.com|TuPassword|5000:5000"
    exit 1
fi

EMAIL=$1
PASSWORD=$2

# Verificar si docker compose está disponible
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
else
    echo "Error: docker compose no encontrado"
    exit 1
fi

# Verificar si el contenedor está corriendo
if ! docker ps --format '{{.Names}}' | grep -q "^mail$"; then
    echo "⚠️  El contenedor 'mail' no está corriendo."
    echo ""
    echo "Opciones:"
    echo "1. Inicia el servicio: cd $PROJECT_DIR && $COMPOSE_CMD up -d"
    echo "2. O usa MAIL_ACCOUNTS en .env antes del primer inicio"
    exit 1
fi

echo "📧 Agregando cuenta de email..."
echo ""

# Agregar cuenta usando docker-mailserver setup
docker exec mail setup email add "$EMAIL" "$PASSWORD"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Cuenta '$EMAIL' agregada exitosamente"
    echo ""
    echo "Para verificar:"
    echo "  docker exec mail setup email list"
else
    echo ""
    echo "❌ Error al agregar la cuenta"
    exit 1
fi
